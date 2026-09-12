import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart' show ValueNotifier, ValueListenable, debugPrint;
import 'package:terra_town_core/terra_town_core.dart';
import 'package:terra_town_location/terra_town_location.dart' show LocationPointRecord, hexIdToFeatureId;

import 'terrain_yield_accrual_coordinator.dart';

/// [TerrainYieldPipeline] が処理済みの位置について保持する観測用スナップショット
/// （`kDebugMode` のデバッグパネル表示専用。Issue #138）。
class TerrainYieldPipelineStats {
  const TerrainYieldPipelineStats({
    required this.processedCount,
    required this.watermarkRowId,
    required this.remainderMicros,
    this.lastProcessedRowId,
    this.lastProcessedTimestamp,
    this.lastProcessedSessionId,
  });

  factory TerrainYieldPipelineStats.initial() => const TerrainYieldPipelineStats(
        processedCount: 0,
        watermarkRowId: 0,
        remainderMicros: {},
      );

  /// パイプライン起動後に処理した位置の件数（開示済み・未開示・計上済み・
  /// 未計上を問わず、1件届くごとに1加算する）。
  final int processedCount;

  /// 直近のウォーターマーク（最後に計上した行id）。
  final int watermarkRowId;

  /// 直近の端数〔マイクロ秒〕（資材ごと）。
  final Map<Resource, int> remainderMicros;

  final int? lastProcessedRowId;

  /// 最後に処理した位置の単調時刻（[GeoPosition.timestamp]）。
  final DateTime? lastProcessedTimestamp;

  final String? lastProcessedSessionId;
}

/// 位置1件ごとに「地形産出の計上」→「開示判定・霧の解除」を**この順序で・
/// 直列に**行う composition root 用のパイプライン（Issue #138）。
///
/// ## なぜ1本の直列パイプラインにするか
/// `DisclosureCoordinator`（Issue #137）は位置ストリームに対する購読を1つに
/// 保つことを重視していたが、本 Issue（#138）はさらに踏み込み、**同じ位置
/// ストリームに2つ目のリスナー（地形産出の計上用）を追加しない**。リスナーが
/// 2つあると、それぞれの `await` した DB 書き込みが入れ違い、
/// 「区間の産出には区間開始時点の開示済みヘクスを使う」（＝先に産出を計上し、
/// その後にその区間の終点を開示する）という順序を保証できなくなる。
///
/// 本クラスは [recordedPositionUpdates] を [StreamIterator] で直接読み、
/// 1件ごとに `await` で「産出の計上（[TerrainYieldAccrualCoordinator.accrue]）」
/// → 「開示判定（[disclosureService.recordPosition]）・新規開示なら
/// [reveal]」の**両方が完了してから次の位置に進む**。
///
/// ## `DisclosureCoordinator` を置き換える（composition root）
/// 本番の位置ストリーム（`NativePositionProvider.recordedPositionUpdates`）は
/// 本クラスが購読する。既存の `DisclosureCoordinator` はそのままテスト・
/// 単体クラスとして残すが、`app/lib/features/map/map_screen.dart` の
/// composition root は本クラスに置き換える（`docs/terrain-yield.md` 参照）。
///
/// ## 手動開示（「地図の中心のヘクスを開示」デバッグボタン）
/// [recordManualPosition] は、`NativePositionProvider` を経由しない直接呼び出し
/// （行id・経過時間の概念が無い一発の観測）のため、**地形産出の計上は行わず**
/// 開示判定と霧の解除だけを行う。ただし新規開示の場合は必ず
/// [terrainHexCounter] を更新すること（更新しないと、地域パック範囲外に
/// いる代表の端末でこのボタンから開示したヘクスが「地形別件数」に反映されず、
/// 実機確認で地形産出が一切進まないという誤った結果になる。advisor 指摘）。
///
/// ## エラー時の挙動
/// 位置ストリーム自体がエラーを送出した場合（`StreamIterator.moveNext()` が
/// 例外を投げた場合）、`StreamIterator` は内部で `cancelOnError: true` の
/// 購読を使うため購読が終了し、以後 `moveNext()` は常に `false` を返す
/// （`DisclosureCoordinator` がストリームのエラーで購読を終了するのと同じ
/// 挙動）。一方、個々の位置の処理中（[TerrainYieldAccrualCoordinator.accrue]・
/// [disclosureService.recordPosition]・[reveal]）で発生した例外はログに残した
/// うえでその位置をスキップし、パイプライン自体は継続する。
class TerrainYieldPipeline {
  TerrainYieldPipeline({
    required this.disclosureService,
    required this.reveal,
    required this.accrualCoordinator,
    required this.terrainHexCounter,
    required this.disclosedHexRepository,
    required this.recordedPositionUpdates,
  });

  final DisclosureService disclosureService;
  final Future<void> Function(int featureId) reveal;
  final TerrainYieldAccrualCoordinator accrualCoordinator;
  final TerrainHexCounter terrainHexCounter;
  final Repository<DisclosedHex, HexId> disclosedHexRepository;
  final Stream<LocationPointRecord> recordedPositionUpdates;

  final ValueNotifier<TerrainYieldPipelineStats> _stats =
      ValueNotifier(TerrainYieldPipelineStats.initial());

  /// デバッグパネル表示用の観測データ（`kDebugMode` 限定の用途を想定）。
  ValueListenable<TerrainYieldPipelineStats> get stats => _stats;

  bool _started = false;
  StreamIterator<LocationPointRecord>? _iterator;

  /// 地形カウンタの初期化（[disclosedHexRepository] からの読み出し）・
  /// [accrualCoordinator] の初期化（ウォーターマーク・端数の読み出し）を行い、
  /// 位置ストリームの購読を開始する。**[known]（[DisclosedHexSet]）への復元
  /// （`restoreDisclosedHexes`）が完了した後に呼ぶこと**
  /// （`DisclosureCoordinator` クラスdoc「呼び出し順序が重要」と同じ理由）。
  ///
  /// 2回目以降の呼び出しは何もしない（`DisclosureCoordinator.start` と同じ方針）。
  Future<void> start() async {
    if (_started) return;
    _started = true;

    final hexes = await disclosedHexRepository.findAll();
    terrainHexCounter.initializeFrom(hexes.map((hex) => hex.terrainType));

    await accrualCoordinator.initialize();
    _stats.value = TerrainYieldPipelineStats(
      processedCount: 0,
      watermarkRowId: accrualCoordinator.watermarkRowId,
      remainderMicros: accrualCoordinator.remainderMicros,
    );

    final iterator = StreamIterator<LocationPointRecord>(recordedPositionUpdates);
    _iterator = iterator;
    unawaited(_run(iterator));
  }

  Future<void> _run(StreamIterator<LocationPointRecord> iterator) async {
    try {
      while (await iterator.moveNext()) {
        final record = iterator.current;
        try {
          await accrualCoordinator.accrue(record, terrainHexCounter.counts);

          final disclosed = await disclosureService.recordPosition(record.position);
          if (disclosed != null) {
            terrainHexCounter.increment(disclosed.terrainType);
            await reveal(hexIdToFeatureId(disclosed.hexId.value));
          }

          _stats.value = TerrainYieldPipelineStats(
            processedCount: _stats.value.processedCount + 1,
            watermarkRowId: accrualCoordinator.watermarkRowId,
            remainderMicros: accrualCoordinator.remainderMicros,
            lastProcessedRowId: record.rowId,
            lastProcessedTimestamp: record.position.timestamp,
            lastProcessedSessionId: record.position.trackingSessionId,
          );
        } catch (e, stackTrace) {
          _log('位置の処理中にエラーが発生しました（この位置はスキップして次に進みます）: $e');
          developer.log(
            'TerrainYieldPipeline: 位置の処理中にエラーが発生しました',
            name: 'terra_town.terrain_yield_pipeline',
            error: e,
            stackTrace: stackTrace,
            level: 1000,
          );
        }
      }
    } catch (e, stackTrace) {
      _log('位置ストリームの処理中にエラーが発生し、パイプラインが終了しました: $e');
      developer.log(
        'TerrainYieldPipeline: 位置ストリームの処理中にエラーが発生しました'
        '（以後、位置の更新は産出・開示判定に反映されません）',
        name: 'terra_town.terrain_yield_pipeline',
        error: e,
        stackTrace: stackTrace,
        level: 1000,
      );
    }
  }

  /// デバッグ専用「地図の中心のヘクスを開示」ボタンから呼ぶ（クラスdoc「手動開示」
  /// 参照）。地形産出の計上は行わない。
  Future<DisclosedHex?> recordManualPosition(GeoPosition position) async {
    final disclosed = await disclosureService.recordPosition(position);
    if (disclosed != null) {
      terrainHexCounter.increment(disclosed.terrainType);
      await reveal(hexIdToFeatureId(disclosed.hexId.value));
    }
    return disclosed;
  }

  /// 購読を止める（画面破棄時に呼ぶ）。
  Future<void> stop() async {
    final iterator = _iterator;
    _iterator = null;
    _started = false;
    if (iterator != null) {
      await iterator.cancel();
    }
  }

  void _log(String message) {
    developer.log(message, name: 'terra_town.terrain_yield_pipeline');
    debugPrint('[terra_town.terrain_yield_pipeline] $message');
  }
}
