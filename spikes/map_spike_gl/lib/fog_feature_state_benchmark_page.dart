// Tab 3: fog of war 性能計測・第二案（feature-state 方式、Issue #24 R2 の再検証）。
// 使い捨て検証ハーネス。製品コード（app/ packages/）には一切依存しない。
//
// 【第一案（fog_benchmark_page.dart）との違い】
// 第一案は、穴あきポリゴン1枚のGeoJSONを開示のたびに「まるごと再エンコード」して
// setGeoJsonSource で差し替えていた（1回の更新がO(n)、全体でO(n²)）。実機計測の結果、
// 0.26.2・0.27.0いずれでも基準未達（FAILの詳細はREADME参照）。
//
// 第二案はこれと発想が逆で、全ヘクスを「最初に1回だけ」ソースとして addGeoJsonSource し、
// 以後は各ヘクスの feature-state を setFeatureState でトグルするだけにする。
// 更新コストが「これまでに開示した数」に依存せず O(1) になることが期待される
// （＝毎回のGeoJSON再エンコードが発生しない）。
//
// 【feature-state Android対応】0.26.2 では Android 未実装（UnimplementedError）だったため、
// この方式はそもそも検証できなかった。release-0.27.0 で Android 実装
// （MapLibreMapController.java の source#setFeatureState / source#removeFeatureState）が
// 入ったことを確認済みなので、ここで初めて実地計測できる。
//
// 【Feature id の付与方式・ハマりどころ】
// maplibre_gl の setFeatureState ドキュメント（controller.dart）に明記されている通り、
// promoteId は web専用で、Androidでは機能しない
// （"Android has no promoteId, so there the GeoJSON itself must contain a top-level id"）。
// そのため properties.hexId のような形では不可で、各 Feature の**直下**に整数の `id` を
// 持たせる必要がある（本ファイルの _buildAllHexGeoJson 参照）。map_probe_page.dart の
// ⑤ addSource/addLayer 疎通が同じ方式（id: c.q * 1000 + c.r）を先に確立していたので、
// それを踏襲した。
//
// 計測A・B・PASS/FAIL算出は第一案（fog_benchmark_page.dart）と同一の方法・表示形式にしてある
// （比較のため）。

import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import 'frame_stats.dart';
import 'hex_grid.dart';

const List<int> kFsHexCountOptions = [1000, 5000, 10000];
const double kFsUpdateTargetMs = 200.0;
const double kFsFpsTarget = 55.0;

class FogFeatureStateBenchmarkPage extends StatefulWidget {
  const FogFeatureStateBenchmarkPage({super.key});

  @override
  State<FogFeatureStateBenchmarkPage> createState() =>
      _FogFeatureStateBenchmarkPageState();
}

class _FogFeatureStateBenchmarkPageState
    extends State<FogFeatureStateBenchmarkPage> {
  MapLibreMapController? _controller;
  int _selectedCount = kFsHexCountOptions.first;
  bool _running = false;
  int _progress = 0;
  int _progressTotal = 0;
  double? _lastUpdateMs;

  DurationStats? _updateStats;
  FrameStatsResult? _updateFrameStats;
  final FrameStatsCollector _updateCollector = FrameStatsCollector();

  final FrameStatsCollector _manualCollector = FrameStatsCollector();
  FrameStatsResult? _manualFrameStats;
  bool _manualCollecting = false;

  // ソースは「最初に1回だけ」追加する方式なので、どのヘクス数で構築済みかを覚えておく。
  // 選択ヘクス数を切り替えた場合のみ、ソース/レイヤーを作り直す
  // （これはベンチマークの計測対象ではない準備作業）。
  bool _fogSourceReady = false;
  int? _fogSourceHexCount;
  List<int> _featureIds = const [];

  static const String _fogSourceId = 'fog_fs_benchmark_source';
  static const String _fogLayerId = 'fog_fs_benchmark_layer';

  final List<String> _log = [];

  void _appendLog(String message) {
    final line = '[${DateTime.now().toIso8601String()}] $message';
    developer.log(line, name: 'map_spike_gl.fog_fs');
    if (!mounted) return;
    setState(() {
      _log.insert(0, line);
      if (_log.length > 300) _log.removeLast();
    });
  }

  /// 全ヘクスを1つのFeatureCollectionとして構築する。
  /// 各Featureには最上位フィールドとして整数の `id` を必ず付与する
  /// （properties の中では不可。Android は promoteId を実装していないため）。
  Map<String, dynamic> _buildAllHexGeoJson(
    List<HexCenter> centers,
    List<int> ids,
  ) {
    return {
      'type': 'FeatureCollection',
      'features': [
        for (int i = 0; i < centers.length; i++)
          {
            'type': 'Feature',
            'id': ids[i],
            'properties': {'hexId': ids[i]},
            'geometry': {
              'type': 'Polygon',
              'coordinates': [hexRing(centers[i])],
            },
          },
      ],
    };
  }

  /// ソース/レイヤーを（必要なら作り直して）用意する。これ自体は計測対象ではない
  /// 「一度だけの準備作業」。
  Future<void> _ensureFogSource() async {
    final controller = _controller;
    if (controller == null) {
      throw StateError('マップ未初期化');
    }
    if (_fogSourceReady && _fogSourceHexCount == _selectedCount) {
      // 既存ソースを再利用する場合も、前回開示した状態が残っていると
      // 「新規開示ぶんだけ計測する」という前提が崩れるため、全状態をリセットする。
      await controller.removeFeatureState(_fogSourceId);
      _appendLog('既存ソースを再利用（hexCount=$_selectedCount）。feature-stateを全リセット');
      return;
    }

    if (_fogSourceReady) {
      // ヘクス数を切り替えた場合は作り直す。
      await controller.removeLayer(_fogLayerId);
      await controller.removeSource(_fogSourceId);
      _appendLog('ヘクス数変更のためソース/レイヤーを再構築');
      setState(() => _fogSourceReady = false);
    }

    final centers = generateHexGrid(_selectedCount);
    final ids = [for (int i = 0; i < centers.length; i++) i];
    final geojson = _buildAllHexGeoJson(centers, ids);

    await controller.addGeoJsonSource(_fogSourceId, geojson);
    await controller.addLayer(
      _fogSourceId,
      _fogLayerId,
      const FillLayerProperties(
        // 0.62 は DESIGN.md の fog トークン rgba(20,22,16,0.62) のαに合わせている。
        fillColor: '#141610',
        fillOpacity: [
          'case',
          ['boolean', ['feature-state', 'revealed'], false],
          0.0, // 開示済み = 透明（霧が晴れる）
          0.62, // 未開示 = 霧
        ],
      ),
    );
    _featureIds = ids;
    setState(() {
      _fogSourceReady = true;
      _fogSourceHexCount = _selectedCount;
    });
    _appendLog(
        'fog(feature-state)ソース/レイヤーを新規作成完了: hexCount=$_selectedCount '
        '（このソース構築自体は計測対象外の準備作業。以後の開示は setFeatureState のみ）');
  }

  Future<void> _runBenchmark() async {
    final controller = _controller;
    if (controller == null) {
      _appendLog('ベンチマーク: マップ未初期化のため中止');
      return;
    }
    setState(() {
      _running = true;
      _progress = 0;
      _progressTotal = _selectedCount;
      _updateStats = null;
      _updateFrameStats = null;
    });

    try {
      await _ensureFogSource();
    } catch (e, st) {
      _appendLog('ソース準備に失敗: ${e.runtimeType}: $e');
      developer.log('fog(feature-state) source setup failed', error: e, stackTrace: st);
      if (mounted) setState(() => _running = false);
      return;
    }

    _appendLog('ベンチマーク開始（feature-state方式）: hexCount=$_selectedCount');
    final List<double> updateDurationsMs = [];

    try {
      _updateCollector.start();

      for (int i = 0; i < _featureIds.length; i++) {
        final featureId = _featureIds[i];

        final sw = Stopwatch()..start();
        await controller.setFeatureState(
          _fogSourceId,
          featureId.toString(),
          {'revealed': true},
        );
        sw.stop();
        final ms = sw.elapsedMicroseconds / 1000.0;
        updateDurationsMs.add(ms);

        if (!mounted) return;
        setState(() {
          _progress = i + 1;
          _lastUpdateMs = ms;
        });

        // UIが完全にフリーズして見えないよう、80回に1回だけ経過ログを出す
        // （毎回ログを出すこと自体がベンチマークを汚染しないよう間引く。第一案と同じ方針）。
        if (i % 80 == 0 || i == _featureIds.length - 1) {
          _appendLog('更新 ${i + 1}/${_featureIds.length}: ${ms.toStringAsFixed(1)}ms');
        }
      }

      final frameStats = _updateCollector.stop();
      final stats = DurationStats.fromMs(updateDurationsMs);
      if (!mounted) return;
      setState(() {
        _updateStats = stats;
        _updateFrameStats = frameStats;
      });
      _appendLog('ベンチマーク完了: ${stats.summary}');
      _appendLog('更新ループ中のフレーム統計: ${frameStats.summary}');
    } catch (e, st) {
      // setFeatureState が例外を投げた場合（版数を安定版に戻したときなど）はクラッシュさせず、
      // 例外の型とメッセージをそのまま画面に出す。それ自体が有効な検証結果。
      _appendLog('ベンチマーク失敗: ${e.runtimeType}: $e');
      developer.log('fog(feature-state) benchmark failed', error: e, stackTrace: st);
      if (_updateCollector.isCollecting) _updateCollector.stop();
      if (updateDurationsMs.isNotEmpty && mounted) {
        // 途中まで計測できていた分だけでも表示する（全滅ではなく部分結果として残す）。
        setState(() {
          _updateStats = DurationStats.fromMs(updateDurationsMs);
        });
      }
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  void _startManualCollection() {
    if (!_fogSourceReady) {
      _appendLog('手動fps計測: 先にベンチマークを実行して開示状態を作ってください');
      return;
    }
    _manualCollector.start();
    setState(() {
      _manualCollecting = true;
      _manualFrameStats = null;
    });
    _appendLog('手動fps計測: 開始。この後、地図をパン/ズーム操作してください');
  }

  void _stopManualCollection() {
    final result = _manualCollector.stop();
    setState(() {
      _manualCollecting = false;
      _manualFrameStats = result;
    });
    _appendLog('手動fps計測: 停止。${result.summary}');
  }

  @override
  Widget build(BuildContext context) {
    final updatePass =
        _updateStats != null && _updateStats!.maxMs <= kFsUpdateTargetMs;
    final fpsPass =
        _manualFrameStats != null && _manualFrameStats!.fps >= kFsFpsTarget;

    return Column(
      children: [
        SizedBox(
          height: 320,
          child: MapLibreMap(
            styleString: MapLibreStyles.demo,
            initialCameraPosition: CameraPosition(
              target: LatLng(kOriginLat, kOriginLng),
              zoom: 15,
            ),
            onMapCreated: (c) => _controller = c,
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(12),
            children: [
              Card(
                color: Colors.teal.shade50,
                child: const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text(
                    '第二案: feature-state方式。全ヘクスを最初に1回だけソース追加し、以後は '
                    'setFeatureState のトグルのみ（毎回のGeoJSON再エンコードなし）。'
                    '目標値（plan.md §8）: 開示1ヘクスの更新は200ms以内 / '
                    'ヘクス1万個開示状態でのパン・ズームは55fps以上',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text('① ヘクス数を選択', style: Theme.of(context).textTheme.titleMedium),
              Wrap(
                spacing: 8,
                children: [
                  for (final n in kFsHexCountOptions)
                    ChoiceChip(
                      label: Text('$n'),
                      selected: _selectedCount == n,
                      onSelected: _running
                          ? null
                          : (_) => setState(() => _selectedCount = n),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: _running ? null : _runBenchmark,
                child: Text(_running
                    ? '実行中… ($_progress/$_progressTotal)'
                    : '② ソース準備(初回のみ) + setFeatureStateベンチマーク実行'),
              ),
              if (_running) ...[
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: _progressTotal == 0 ? null : _progress / _progressTotal,
                ),
                if (_lastUpdateMs != null)
                  Text('直近の更新: ${_lastUpdateMs!.toStringAsFixed(1)}ms'),
              ],
              if (_updateStats != null) ...[
                const SizedBox(height: 12),
                Card(
                  color: updatePass ? Colors.green.shade50 : Colors.red.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '計測A: 更新レイテンシ ${updatePass ? "PASS" : "FAIL"}（基準: 最大値が200ms以内）',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Text(_updateStats!.summary),
                        if (_updateFrameStats != null)
                          Text('更新ループ中のフレーム統計: ${_updateFrameStats!.summary}'),
                      ],
                    ),
                  ),
                ),
              ],
              const Divider(height: 32),
              Text('③ 手動パン・ズームfps計測', style: Theme.of(context).textTheme.titleMedium),
              const Text(
                '自動操作はできないため、ここだけは代表の手動操作が必要です。'
                '「開始」を押した後、上の地図を数秒間パン/ズームしてから「停止」を押してください。',
              ),
              const SizedBox(height: 8),
              Wrap(spacing: 8, children: [
                ElevatedButton(
                  onPressed: (_fogSourceReady && !_manualCollecting)
                      ? _startManualCollection
                      : null,
                  child: const Text('開始'),
                ),
                ElevatedButton(
                  onPressed: _manualCollecting ? _stopManualCollection : null,
                  child: const Text('停止'),
                ),
              ]),
              if (_manualFrameStats != null) ...[
                const SizedBox(height: 12),
                Card(
                  color: fpsPass ? Colors.green.shade50 : Colors.red.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '計測B: 手動パン/ズームfps ${fpsPass ? "PASS" : "FAIL"}（基準: 55fps以上）'
                          '${_selectedCount != 10000 ? "（注: 現在の選択は$_selectedCount。厳密比較は1万ヘクス選択時に行うこと）" : ""}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Text(_manualFrameStats!.summary),
                      ],
                    ),
                  ),
                ),
              ],
              const Divider(height: 32),
              Text('ログ（debugPrintにも出力）', style: Theme.of(context).textTheme.titleMedium),
              Container(
                height: 240,
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: _log.isEmpty
                    ? const Text('（まだログはありません）',
                        style: TextStyle(color: Colors.white54))
                    : ListView.builder(
                        itemCount: _log.length,
                        itemBuilder: (context, i) => Text(
                          _log[i],
                          style: const TextStyle(
                            color: Colors.greenAccent,
                            fontFamily: 'monospace',
                            fontSize: 11,
                          ),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
