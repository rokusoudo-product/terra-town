// Tab 2: fog of war 性能計測（Issue #24 R2・plan.md §8・research.md §6.4 に対応）。
// 使い捨て検証ハーネス。製品コード（app/ packages/）には一切依存しない。
//
// 計測A: 穴あきポリゴン1枚のGeoJSONに対し、setGeoJsonSource で1ヘクスずつ「開示」を
//        追加していく更新を選択ヘクス数ぶん繰り返し、1回あたりの実行時間(ms)の
//        min/median/max/avgを出す。plan.md §8 の基準=200ms以内。
// 計測B: SchedulerBinding.addTimingsCallback によるFrameTimings収集。
//        計測Aのループ実行中の自動収集（更新自体が引き起こすジャンク）に加え、
//        「開示完了後にユーザーが手動でパン・ズームする区間」を start/stop で
//        個別に計測できるようにしている（自動操作はできないため、ここだけは代表の手動操作が必要）。
//        plan.md §8 の基準=1万ヘクス開示状態で55fps以上。

import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import 'frame_stats.dart';
import 'hex_grid.dart';

const List<int> kHexCountOptions = [1000, 5000, 10000];
const double kUpdateTargetMs = 200.0;
const double kFpsTarget = 55.0;

class FogBenchmarkPage extends StatefulWidget {
  const FogBenchmarkPage({super.key});

  @override
  State<FogBenchmarkPage> createState() => _FogBenchmarkPageState();
}

class _FogBenchmarkPageState extends State<FogBenchmarkPage> {
  MapLibreMapController? _controller;
  int _selectedCount = kHexCountOptions.first;
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

  bool _fogSourceReady = false;
  static const String _fogSourceId = 'fog_benchmark_source';
  static const String _fogLayerId = 'fog_benchmark_layer';

  final List<String> _log = [];

  void _appendLog(String message) {
    final line = '[${DateTime.now().toIso8601String()}] $message';
    developer.log(line, name: 'map_spike_gl.fog');
    if (!mounted) return;
    setState(() {
      _log.insert(0, line);
      if (_log.length > 300) _log.removeLast();
    });
  }

  Map<String, dynamic> _buildFogGeoJson(
    List<List<List<double>>> revealedHoles,
    List<List<double>> outerRing,
  ) {
    return {
      'type': 'FeatureCollection',
      'features': [
        {
          'type': 'Feature',
          'properties': {},
          'geometry': {
            'type': 'Polygon',
            'coordinates': [outerRing, ...revealedHoles],
          },
        },
      ],
    };
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
      _fogSourceReady = false;
    });

    _appendLog('ベンチマーク開始: hexCount=$_selectedCount');
    final centers = generateHexGrid(_selectedCount);
    final outerRing = boundingBoxRing(centers, marginMeters: 100);
    final List<List<List<double>>> holes = [];
    final List<double> updateDurationsMs = [];

    try {
      // 初期状態（フル fog・穴なし）でソースを作成。
      final initialGeojson = _buildFogGeoJson(const [], outerRing);
      await controller.addGeoJsonSource(_fogSourceId, initialGeojson);
      await controller.addLayer(
        _fogSourceId,
        _fogLayerId,
        const FillLayerProperties(fillColor: '#000000', fillOpacity: 0.55),
      );
      setState(() => _fogSourceReady = true);
      _appendLog('fogソース/レイヤー作成完了。ここから1ヘクスずつ開示していく');

      _updateCollector.start();

      for (int i = 0; i < centers.length; i++) {
        holes.add(hexRing(centers[i]));
        final geojson = _buildFogGeoJson(holes, outerRing);

        final sw = Stopwatch()..start();
        await controller.setGeoJsonSource(_fogSourceId, geojson);
        sw.stop();
        final ms = sw.elapsedMicroseconds / 1000.0;
        updateDurationsMs.add(ms);

        if (!mounted) return;
        setState(() {
          _progress = i + 1;
          _lastUpdateMs = ms;
        });

        // UIが完全にフリーズして見えないよう、80回に1回だけ経過ログを出す
        // （毎回ログを出すこと自体がベンチマークを汚染しないよう間引く）。
        if (i % 80 == 0 || i == centers.length - 1) {
          _appendLog('更新 ${i + 1}/${centers.length}: ${ms.toStringAsFixed(1)}ms');
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
      _appendLog('ベンチマーク失敗: ${e.runtimeType}: $e');
      developer.log('fog benchmark failed', error: e, stackTrace: st);
      if (_updateCollector.isCollecting) _updateCollector.stop();
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
        _updateStats != null && _updateStats!.maxMs <= kUpdateTargetMs;
    final fpsPass =
        _manualFrameStats != null && _manualFrameStats!.fps >= kFpsTarget;

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
                color: Colors.amber.shade50,
                child: const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text(
                    '目標値（plan.md §8）: 開示1ヘクス追加の更新は200ms以内 / '
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
                  for (final n in kHexCountOptions)
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
                    : '② fog生成 + 更新ベンチマーク実行'),
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
