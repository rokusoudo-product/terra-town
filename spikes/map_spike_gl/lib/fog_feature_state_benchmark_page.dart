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
//
// 【ソース構築コスト計測（Issue #24 追補）】
// 上記の計測A・Bはいずれも「全ヘクスを1回だけソースとして追加した後」の話であり、
// その「最初の1回のソース構築」自体はこれまで「計測対象外の準備作業」としてログに出すだけで、
// 所要時間を数値化していなかった。しかし実測で maxFrame=1,077.3ms（10,000ヘクス）という
// 約1秒の描画フレームが観測されており、これはソース追加直後の初回描画と推測される。
// 実際の地域パックのヘクス数は10,000を大きく上回る可能性があるため、
// 「起動時・エリア切替時に何秒待たされるか」を明らかにする目的で、ソース構築フェーズを
// 4段階（①ヘクスジオメトリ生成 ②addGeoJsonSource ③addLayer ④初回描画の観測ウィンドウ）に
// 分解して計測する。既存の計測A（setFeatureStateのトグル計測）・計測Bの算出方法は一切変更しない。
// 詳細な定義・近似の限界はREADMEを参照。

import 'dart:async' show unawaited;
import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import 'frame_stats.dart';
import 'hex_grid.dart';

const List<int> kFsHexCountOptions = [1000, 5000, 10000, 50000, 100000];
const double kFsUpdateTargetMs = 200.0;
const double kFsFpsTarget = 55.0;

/// 大きいヘクス数ほど初回描画の「落ち着き」に時間がかかる可能性があるため、
/// ソース構築後にフレーム統計を収集する観測ウィンドウの長さをヘクス数に応じて伸ばす。
/// 固定期間である以上、真の「描画完了」を厳密に検出するものではない（README参照）。
Duration postSourceBuildSettleWindow(int hexCount) {
  if (hexCount <= 10000) return const Duration(seconds: 2);
  if (hexCount <= 50000) return const Duration(seconds: 5);
  return const Duration(seconds: 10);
}

/// ソース構築（最初の1回だけ発生するコスト）の内訳計測結果。
/// 例外で失敗した場合は [error] のみが埋まり、他のフィールドは null になる
/// （＝それ自体が有効な検証結果として画面に残す）。
class SourceBuildResult {
  final int hexCount;
  final double? geometryMs;
  final double? addSourceMs;
  final double? addLayerMs;
  final double? settleWindowMs;
  final double? maxFrameMsInWindow;
  final int? frameCountInWindow;
  final int? jankFrameCountInWindow;
  final double? totalMs;
  final DateTime measuredAt;
  final String? error;

  SourceBuildResult({
    required this.hexCount,
    this.geometryMs,
    this.addSourceMs,
    this.addLayerMs,
    this.settleWindowMs,
    this.maxFrameMsInWindow,
    this.frameCountInWindow,
    this.jankFrameCountInWindow,
    this.totalMs,
    DateTime? measuredAt,
    this.error,
  }) : measuredAt = measuredAt ?? DateTime.now();

  factory SourceBuildResult.failure({
    required int hexCount,
    required String error,
  }) {
    return SourceBuildResult(hexCount: hexCount, error: error);
  }

  bool get isFailure => error != null;

  String get summary {
    if (isFailure) {
      return 'hexCount=$hexCount 失敗: $error';
    }
    return 'hexCount=$hexCount: '
        '①geometry=${geometryMs!.toStringAsFixed(1)}ms '
        '②addSource=${addSourceMs!.toStringAsFixed(1)}ms '
        '③addLayer=${addLayerMs!.toStringAsFixed(1)}ms '
        '④観測ウィンドウ${settleWindowMs!.toStringAsFixed(0)}ms中の'
        'maxFrame=${maxFrameMsInWindow!.toStringAsFixed(1)}ms '
        '(frames=$frameCountInWindow jank=$jankFrameCountInWindow) '
        '⑤合計(①+②+③+④maxFrame)=${totalMs!.toStringAsFixed(1)}ms';
  }
}

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

  // --- スタイル再読み込み時のちらつき確認（research.md §6.4「残る未計測事項」） ---
  // controller.setStyle はスタイル全体（ソース・レイヤーを含む）を差し替えるため、
  // 開示済みフォグは一度消え、onStyleLoadedCallback発火後に作り直すまで表示されない。
  // その空白時間・フレーム落ちを「ちらつき」の客観的な近似指標として計測する。
  final FrameStatsCollector _styleReloadCollector = FrameStatsCollector();
  FrameStatsResult? _styleReloadFrameStats;
  bool _styleReloadInProgress = false;
  DateTime? _styleReloadStartedAt;
  double? _styleReloadCallbackElapsedMs;
  double? _styleReloadRebuildTotalElapsedMs;

  // ソースは「最初に1回だけ」追加する方式なので、どのヘクス数で構築済みかを覚えておく。
  // 選択ヘクス数を切り替えた場合のみ、ソース/レイヤーを作り直す
  // （これはベンチマークの計測対象ではない準備作業）。
  bool _fogSourceReady = false;
  int? _fogSourceHexCount;
  List<int> _featureIds = const [];

  // ソース構築コスト計測結果。ヘクス数を切り替えながら比較できるよう、
  // 実行するたびに先頭へ追加していく（上書きしない）。
  final List<SourceBuildResult> _sourceBuildResults = [];
  bool _rebuildingSource = false;

  static const String _fogSourceId = 'fog_fs_benchmark_source';
  static const String _fogLayerId = 'fog_fs_benchmark_layer';

  final List<String> _log = [];

  void _appendLog(String message) {
    final line = '[${DateTime.now().toIso8601String()}] $message';
    developer.log(line, name: 'map_spike_gl.fog_fs');
    // developer.log は VM service 経由のため、`flutter run` を使わず
    // 単体起動した端末の `adb logcat` には出てこない。仕様どおり debugPrint
    // でも出しておく（`adb logcat` から追えるようにするため）。
    debugPrint(line);
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

    await _buildSourceWithMeasurement(controller);
  }

  /// ソース構築（最初の1回だけのコスト）を4段階に分解して計測する。
  /// ①ヘクスジオメトリ生成 ②addGeoJsonSource ③addLayer
  /// ④ソース追加直後の観測ウィンドウ中のフレーム統計（初回描画の近似指標）。
  /// 計測方法の詳細・限界はREADMEの「ソース構築コスト計測」節を参照。
  ///
  /// 例外（メモリ不足等）が発生した場合はcrashさせず、型とメッセージを
  /// [_sourceBuildResults] にも残したうえで呼び出し元へ再送出する
  /// （呼び出し元がベンチマーク全体を中断できるように）。
  Future<void> _buildSourceWithMeasurement(
      MapLibreMapController controller) async {
    final hexCount = _selectedCount;
    final bigWarning = hexCount >= 50000
        ? '（大規模。数秒〜数十秒かかる場合や、メモリ不足で応答なし/強制終了になる場合があります）'
        : '';
    _appendLog('ソース構築コスト計測開始: hexCount=$hexCount$bigWarning');

    final buildCollector = FrameStatsCollector();
    try {
      final geomSw = Stopwatch()..start();
      final centers = generateHexGrid(hexCount);
      final ids = [for (int i = 0; i < centers.length; i++) i];
      final geojson = _buildAllHexGeoJson(centers, ids);
      geomSw.stop();
      final geometryMs = geomSw.elapsedMicroseconds / 1000.0;
      _appendLog(
          '① ヘクスジオメトリ生成: ${geometryMs.toStringAsFixed(1)}ms (features=${centers.length})');

      // ここから、addGeoJsonSource〜観測ウィンドウ終了までのフレームを収集する。
      buildCollector.start();

      final addSourceSw = Stopwatch()..start();
      await controller.addGeoJsonSource(_fogSourceId, geojson);
      addSourceSw.stop();
      final addSourceMs = addSourceSw.elapsedMicroseconds / 1000.0;
      _appendLog('② addGeoJsonSource: ${addSourceMs.toStringAsFixed(1)}ms');

      final addLayerSw = Stopwatch()..start();
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
      addLayerSw.stop();
      final addLayerMs = addLayerSw.elapsedMicroseconds / 1000.0;
      _appendLog('③ addLayer: ${addLayerMs.toStringAsFixed(1)}ms');

      _featureIds = ids;
      if (!mounted) return;
      setState(() {
        _fogSourceReady = true;
        _fogSourceHexCount = hexCount;
      });

      final settleWindow = postSourceBuildSettleWindow(hexCount);
      _appendLog(
          '④ 初回描画の観測ウィンドウ待機中: ${settleWindow.inMilliseconds}ms '
          '（厳密な描画完了検出ではない近似計測。詳細はREADME参照）');
      await Future.delayed(settleWindow);

      final frameStats = buildCollector.stop();
      // ⑤合計は①+②+③+④の値。④の「値」は観測ウィンドウの長さ（固定の待機時間）ではなく
      // その中で観測された最大フレーム時間（maxFrame）であることに注意
      // （観測ウィンドウの長さはヘクス数の階層で決め打ちの定数のため、それを合計に混ぜると
      // 合計がヘクス数の実測コストではなく階層の境界でジャンプするだけの数値になってしまう）。
      final totalMs =
          geometryMs + addSourceMs + addLayerMs + frameStats.maxFrameMs;

      final result = SourceBuildResult(
        hexCount: hexCount,
        geometryMs: geometryMs,
        addSourceMs: addSourceMs,
        addLayerMs: addLayerMs,
        settleWindowMs: settleWindow.inMilliseconds.toDouble(),
        maxFrameMsInWindow: frameStats.maxFrameMs,
        frameCountInWindow: frameStats.frameCount,
        jankFrameCountInWindow: frameStats.jankFrameCount,
        totalMs: totalMs,
      );

      _appendLog('ソース構築コスト計測完了: ${result.summary}');
      if (!mounted) return;
      setState(() => _sourceBuildResults.insert(0, result));
    } catch (e, st) {
      if (buildCollector.isCollecting) buildCollector.stop();
      final message = '${e.runtimeType}: $e';
      _appendLog('ソース構築コスト計測失敗: $message (hexCount=$hexCount)');
      developer.log('fog source build measurement failed',
          error: e, stackTrace: st);
      if (mounted) {
        setState(() => _sourceBuildResults.insert(
              0,
              SourceBuildResult.failure(hexCount: hexCount, error: message),
            ));
      }
      rethrow;
    }
  }

  /// 既存ソースを破棄して強制的に作り直し、ソース構築コストだけを単独で
  /// 再計測する（同じヘクス数のまま計測をやり直したい場合の手段。
  /// 通常のベンチマークボタン②はヘクス数を切り替えた時だけ再構築するため、
  /// 同一ヘクス数で複数回計測したいときに使う）。
  Future<void> _forceRebuildSource() async {
    final controller = _controller;
    if (controller == null) {
      _appendLog('ソース再構築: マップ未初期化のため中止');
      return;
    }
    if (_running || _rebuildingSource) return;
    setState(() => _rebuildingSource = true);
    try {
      if (_fogSourceReady) {
        await controller.removeLayer(_fogLayerId);
        await controller.removeSource(_fogSourceId);
        _appendLog('ソース再構築（計測やり直し）のため既存ソース/レイヤーを削除');
        setState(() => _fogSourceReady = false);
      }
      await _buildSourceWithMeasurement(controller);
    } catch (_) {
      // 失敗の詳細は _buildSourceWithMeasurement 内で既にログ・結果一覧へ反映済み。
    } finally {
      if (mounted) setState(() => _rebuildingSource = false);
    }
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

  /// スタイル再読み込み（`controller.setStyle`）を実行し、ちらつきを近似計測する。
  /// setStyleはソース・レイヤーを含むスタイル全体を差し替えるため、直前まで開示していた
  /// フォグは一度全て消える。onStyleLoadedCallback発火後にフォグを作り直すまでの
  /// 経過時間とフレーム統計を記録し、代表が「実際にどう見えたか」を目視確認できるようにする。
  Future<void> _reloadStyleAndCheckFlicker() async {
    final controller = _controller;
    if (controller == null) {
      _appendLog('スタイル再読み込み: マップ未初期化のため中止');
      return;
    }
    if (!_fogSourceReady) {
      _appendLog(
          'スタイル再読み込み: 先に②のベンチマークを実行してフォグを表示させてください'
          '（フォグが無いとちらつきの有無が判断できません）');
      return;
    }
    setState(() {
      _styleReloadInProgress = true;
      _styleReloadFrameStats = null;
      _styleReloadCallbackElapsedMs = null;
      _styleReloadRebuildTotalElapsedMs = null;
    });
    _styleReloadStartedAt = DateTime.now();
    _styleReloadCollector.start();
    _appendLog(
        'スタイル再読み込み開始: setStyleを呼び出しました。フォグが一時的に消える見込みです。'
        '画面を目視し、消えている間の見た目（背景色のちらつき・空白等）を確認してください');
    try {
      // onStyleLoadedCallback（MapLibreMapのコールバック、下のbuild()参照）が
      // 発火したら _onStyleReloaded がフォグの再構築を行う。
      await controller.setStyle(MapLibreStyles.demo);
      // 発火しなかった場合にボタンが永久に押せなくなる（無言のスタック）のを防ぐ
      // ウォッチドッグ。正常系（callbackが発火して_rebuildFogAfterStyleReloadが完走した
      // 場合）は_styleReloadInProgressが既にfalseになっているため何もしない。
      unawaited(_watchdogForStuckStyleReload());
    } catch (e, st) {
      _appendLog('スタイル再読み込み: setStyle失敗 ${e.runtimeType}: $e');
      developer.log('style reload setStyle failed', error: e, stackTrace: st);
      if (_styleReloadCollector.isCollecting) _styleReloadCollector.stop();
      if (mounted) setState(() => _styleReloadInProgress = false);
    }
  }

  /// onStyleLoadedCallbackが発火しない/フォグ再構築が完走しない場合に、
  /// ボタンが永久に無効のまま残ることを防ぐための保険。
  Future<void> _watchdogForStuckStyleReload() async {
    await Future.delayed(const Duration(seconds: 10));
    if (!mounted || !_styleReloadInProgress) return;
    _appendLog(
        'スタイル再読み込み: onStyleLoadedCallbackが10秒経っても発火しませんでした（要確認）。'
        '計測を打ち切ります');
    if (_styleReloadCollector.isCollecting) _styleReloadCollector.stop();
    setState(() => _styleReloadInProgress = false);
  }

  /// MapLibreMapのonStyleLoadedCallback。初回スタイル読込時にも発火するため、
  /// 「再読み込みちらつき確認」を実行中のときだけフォグの再構築を行う。
  void _onStyleReloaded() {
    if (!_styleReloadInProgress) return;
    final startedAt = _styleReloadStartedAt;
    final callbackElapsedMs = startedAt == null
        ? null
        : DateTime.now().difference(startedAt).inMicroseconds / 1000.0;
    _styleReloadCallbackElapsedMs = callbackElapsedMs;
    _appendLog(
        'スタイル再読み込み: onStyleLoadedCallback発火（setStyleから'
        '${callbackElapsedMs?.toStringAsFixed(1)}ms経過）。'
        'フォグのソース/レイヤーを再構築します（setStyleで消えているため）');
    unawaited(_rebuildFogAfterStyleReload());
  }

  /// スタイル再読み込みで失われたフォグのソース/レイヤーを作り直す。
  /// 【既知の制約】どのヘクスが開示済みだったかの集合を別途保持していないため、
  /// 再構築後は全ヘクス未開示（フォグ全面表示）の状態に戻る。これも「スタイル再読み込みで
  /// 開示状態が失われる」という観測結果の一部として扱い、README に明記する。
  Future<void> _rebuildFogAfterStyleReload() async {
    final controller = _controller;
    final hexCount = _fogSourceHexCount ?? _selectedCount;
    try {
      if (controller == null) {
        throw StateError('マップ未初期化');
      }
      final centers = generateHexGrid(hexCount);
      final ids = [for (int i = 0; i < centers.length; i++) i];
      final geojson = _buildAllHexGeoJson(centers, ids);
      await controller.addGeoJsonSource(_fogSourceId, geojson);
      await controller.addLayer(
        _fogSourceId,
        _fogLayerId,
        const FillLayerProperties(
          fillColor: '#141610',
          fillOpacity: [
            'case',
            ['boolean', ['feature-state', 'revealed'], false],
            0.0,
            0.62,
          ],
        ),
      );
      _featureIds = ids;

      // 再構築完了後もしばらくフレーム統計を集め続け、初回描画のスパイクまで含めて
      // 「ちらつき」の近似指標に反映する（ソース構築コスト計測と同じ考え方）。
      await Future.delayed(postSourceBuildSettleWindow(hexCount));
      final frameStats = _styleReloadCollector.stop();
      final totalElapsedMs = _styleReloadStartedAt == null
          ? null
          : DateTime.now().difference(_styleReloadStartedAt!).inMicroseconds /
              1000.0;
      _styleReloadRebuildTotalElapsedMs = totalElapsedMs;
      if (mounted) setState(() => _styleReloadFrameStats = frameStats);
      _appendLog(
          'スタイル再読み込み: フォグ再構築完了（例外なし）。'
          'setStyleから合計${totalElapsedMs?.toStringAsFixed(1)}ms。'
          '${frameStats.summary}。'
          '開示状態はリセットされ全面フォグに戻っています（既知の制約・README参照）');
    } catch (e, st) {
      if (_styleReloadCollector.isCollecting) _styleReloadCollector.stop();
      _appendLog('スタイル再読み込み: フォグ再構築失敗 ${e.runtimeType}: $e');
      developer.log('style reload fog rebuild failed', error: e, stackTrace: st);
    } finally {
      if (mounted) setState(() => _styleReloadInProgress = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final updatePass =
        _updateStats != null && _updateStats!.maxMs <= kFsUpdateTargetMs;
    // 判定には activeFps（無操作区間を除いた fps）を使う。naiveFps は参考値
    // （2026-09-09・Issue #24 実機セッションで発覚。frame_stats.dart 冒頭コメント参照）。
    final fpsPass =
        _manualFrameStats != null && _manualFrameStats!.activeFps >= kFsFpsTarget;

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
            onStyleLoadedCallback: _onStyleReloaded,
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
                    'ヘクス1万個開示状態でのパン・ズームは55fps以上。'
                    '「最初の1回のソース構築」自体のコストも②\'で内訳計測する'
                    '（plan.mdに合格基準の定義がないためPASS/FAIL判定はせず数値のみ表示）。',
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
              if (_selectedCount >= 50000) ...[
                const SizedBox(height: 8),
                Card(
                  color: Colors.orange.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      '注意: $_selectedCount ヘクスは大規模です。ソース構築に数秒〜数十秒かかったり、'
                      '端末がメモリ不足で応答なし（ANR）や強制終了になる可能性があります。'
                      'その場合もそれ自体が有効な検証結果です。無理に連打せず、結果（またはクラッシュ）を'
                      'そのまま記録してください。',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
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
              Text('②\' ソース構築コスト計測（最初の1回だけのコスト）',
                  style: Theme.of(context).textTheme.titleMedium),
              const Text(
                '上のボタン②を押すと、ヘクス数を切り替えた時（＝ソースを新規に作る時）だけ '
                '自動的に計測される。同じヘクス数のまま計測をやり直したい場合は下のボタンで '
                '強制的に作り直す。内訳: ①ヘクスジオメトリ生成 ②addGeoJsonSource ③addLayer '
                '④ソース追加後の観測ウィンドウ中のフレーム統計（初回描画の近似指標。定義はREADME参照）。',
              ),
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: (_running || _rebuildingSource)
                    ? null
                    : _forceRebuildSource,
                child: Text(_rebuildingSource
                    ? '再構築・計測中…'
                    : 'ソースを破棄して再構築（計測やり直し・hexCount=$_selectedCount）'),
              ),
              if (_sourceBuildResults.isEmpty) ...[
                const SizedBox(height: 8),
                const Text('（まだソース構築の計測結果はありません）'),
              ] else ...[
                const SizedBox(height: 8),
                Text(
                    '結果一覧（新しい順・${_sourceBuildResults.length}件。ヘクス数ごとに比較できるよう'
                    '消さずに積み上げていく）',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                for (final r in _sourceBuildResults)
                  Card(
                    color: r.isFailure ? Colors.red.shade50 : Colors.blue.shade50,
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'hexCount=${r.hexCount}  (${r.measuredAt.toIso8601String()})',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          if (r.isFailure)
                            Text('失敗: ${r.error}')
                          else ...[
                            Text('① ヘクスジオメトリ生成: ${r.geometryMs!.toStringAsFixed(1)}ms'),
                            Text('② addGeoJsonSource: ${r.addSourceMs!.toStringAsFixed(1)}ms'),
                            Text('③ addLayer: ${r.addLayerMs!.toStringAsFixed(1)}ms'),
                            Text(
                                '④ 観測ウィンドウ ${r.settleWindowMs!.toStringAsFixed(0)}ms中の '
                                'maxFrame=${r.maxFrameMsInWindow!.toStringAsFixed(1)}ms '
                                '(frames=${r.frameCountInWindow} jank=${r.jankFrameCountInWindow})'),
                            Text('⑤ 合計（①+②+③+④のmaxFrame）: '
                                '${r.totalMs!.toStringAsFixed(1)}ms',
                                style: const TextStyle(fontWeight: FontWeight.bold)),
                          ],
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
                          '計測B: 手動パン/ズームfps ${fpsPass ? "PASS" : "FAIL"}'
                          '（基準: activeFps=55fps以上。判定指標はactiveFps。naiveFpsは参考値）'
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
              Text('④ スタイル再読み込み時のちらつき確認 [research.md §6.4「残る未計測事項」]',
                  style: Theme.of(context).textTheme.titleMedium),
              const Text(
                '②でフォグを表示させた状態で押すこと。controller.setStyleでスタイル全体を'
                '差し替え、フォグが一時的に消えてから再構築されるまでを観測する。'
                '数値（経過時間・フレーム統計）に加えて、代表が実際の見た目'
                '（消える瞬間・空白時間・再表示時のガクつき等）を目視で確認すること。'
                '再構築後は開示状態がリセットされ全面フォグに戻る（既知の制約）。',
              ),
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: (_fogSourceReady && !_styleReloadInProgress)
                    ? _reloadStyleAndCheckFlicker
                    : null,
                child: Text(_styleReloadInProgress ? '再読み込み・観測中…' : 'スタイル再読み込みを試す'),
              ),
              if (_styleReloadCallbackElapsedMs != null) ...[
                const SizedBox(height: 8),
                Text(
                    'onStyleLoadedCallbackまで: '
                    '${_styleReloadCallbackElapsedMs!.toStringAsFixed(1)}ms'),
              ],
              if (_styleReloadFrameStats != null) ...[
                const SizedBox(height: 8),
                Card(
                  color: Colors.blueGrey.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'フォグ再構築完了まで合計: '
                          '${_styleReloadRebuildTotalElapsedMs?.toStringAsFixed(1)}ms',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Text('観測ウィンドウ中のフレーム統計: ${_styleReloadFrameStats!.summary}'),
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
