import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart'
    show ValueNotifier, ValueListenable, debugPrint, kDebugMode;
import 'package:terra_town_core/terra_town_core.dart';
import 'package:terra_town_location/terra_town_location.dart'
    show
        HexOpeningSpendOutcome,
        HexOpeningSpendResult,
        HexOpeningSpendService,
        LocationPointRecord,
        hexIdToFeatureId;

import 'opening_point_accrual_coordinator.dart';
import 'terrain_yield_accrual_coordinator.dart';

/// [TerrainYieldPipeline.openHexWithPoints] の結果（Issue #151・T064）。
class HexOpeningAttemptResult {
  const HexOpeningAttemptResult._({
    required this.success,
    this.denialReason,
    this.disclosedHex,
    this.collectedLandmarks = const [],
  });

  factory HexOpeningAttemptResult.success(
    DisclosedHex disclosedHex, {
    List<LandmarkCollectionRecord> collectedLandmarks = const [],
  }) =>
      HexOpeningAttemptResult._(
        success: true,
        disclosedHex: disclosedHex,
        collectedLandmarks: collectedLandmarks,
      );

  factory HexOpeningAttemptResult.denied(HexOpeningDenialReason reason) =>
      HexOpeningAttemptResult._(success: false, denialReason: reason);

  final bool success;

  /// [success] が false の場合の拒否理由。
  final HexOpeningDenialReason? denialReason;

  /// [success] が true の場合に新規開示された [DisclosedHex]。
  final DisclosedHex? disclosedHex;

  /// 開放と同時に新規収集された名所（Issue #159・T070）。[success] が false、
  /// または名所の無いヘクスだった場合は空リスト。`HexOpeningSheet` が閉じた
  /// **後**に `map_screen.dart` がこれを読んでSnackBarを表示する
  /// （`HexOpeningSheet` クラスdoc「『閉じる』で確定結果を呼び出し元へ返す」参照。
  /// モーダル表示中にSnackBarを出すと背面に隠れて見えないため）。
  final List<LandmarkCollectionRecord> collectedLandmarks;
}

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

/// [TerrainYieldPipeline] が処理済みの位置について保持する、開放ポイント
/// （歩行距離換算）の観測用スナップショット（Issue #143）。
///
/// ## `kDebugMode` 専用ではなくなった（Issue #149・T062）
/// 当初は `kDebugMode` のデバッグパネル（[OpeningPointDebugPanel]）表示専用
/// だったが、[sessionDistanceMeters]・[sessionStepCount]・[sessionHasStepData] の
/// 追加により、release ビルドでも常に表示する製品UIの HUD
/// （`app/lib/features/map/widgets/walk_stats_hud.dart`）もこの型を読む。
/// [points]・[remainderMillimeters]・[watermarkRowId]・[lastSegmentDistanceMeters]・
/// [lastAppliedMultiplier]・[lastReason] は引き続きデバッグパネル向けの詳細診断値
/// という位置づけのまま変更していない。
class OpeningPointPipelineStats {
  const OpeningPointPipelineStats({
    required this.points,
    required this.remainderMillimeters,
    required this.watermarkRowId,
    this.lastSegmentDistanceMeters,
    this.lastAppliedMultiplier,
    this.lastReason,
    this.sessionDistanceMeters = 0,
    this.sessionStepCount = 0,
    this.sessionHasStepData = false,
  });

  factory OpeningPointPipelineStats.initial() => const OpeningPointPipelineStats(
        points: 0,
        remainderMillimeters: 0,
        watermarkRowId: 0,
      );

  /// 現在の開放ポイント所持数（0〜[openingPointStockCap]）。
  final int points;

  /// 次の1Pまでの端数〔ミリメートル〕。
  final int remainderMillimeters;

  /// 直近のウォーターマーク（最後に計上した行id）。
  final int watermarkRowId;

  /// 直近で計上に使われた区間の移動距離〔m〕。
  final double? lastSegmentDistanceMeters;

  /// 直近で計上に使われた区間の付与倍率（`RewardPolicy.classify` が返す値）。
  final double? lastAppliedMultiplier;

  /// 直近の区間の [RewardSegmentReason]（倍率がその値になった理由）。
  final RewardSegmentReason? lastReason;

  /// 今回の記録での歩行距離〔m〕の積算値（HUD 用・Issue #149）。
  /// `OpeningPointAccrualCoordinator.sessionDistanceMeters` のドキュメント参照。
  final double sessionDistanceMeters;

  /// 今回の記録での歩数の積算値（HUD 用・Issue #149）。[sessionHasStepData] が
  /// false の間は意味を持たない。
  final int sessionStepCount;

  /// 今回の記録で歩数センサーの値を一度でも観測できたか（HUD 用・Issue #149）。
  /// false の間、HUD は歩数欄そのものを表示しない。
  final bool sessionHasStepData;
}

/// 位置1件ごとに「地形産出の計上」→「開放ポイント（歩行距離換算）の計上」→
/// 「開示判定・霧の解除」を**この順序で・直列に**行う composition root 用の
/// パイプライン（Issue #138・#143）。
///
/// ## なぜ1本の直列パイプラインにするか
/// `DisclosureCoordinator`（Issue #137）は位置ストリームに対する購読を1つに
/// 保つことを重視していたが、Issue #138 はさらに踏み込み、**同じ位置
/// ストリームに2つ目のリスナー（地形産出の計上用）を追加しない**。リスナーが
/// 2つあると、それぞれの `await` した DB 書き込みが入れ違い、
/// 「区間の産出には区間開始時点の開示済みヘクスを使う」（＝先に産出を計上し、
/// その後にその区間の終点を開示する）という順序を保証できなくなる。
///
/// Issue #143（開放ポイントの入手）もこの方針を踏襲し、**新たに3つ目の
/// リスナーを追加せず**、既存の直列パイプラインへ処理ステップを1つ足す形で
/// 実装した（`OpeningPointAccrualCoordinator.accrue` は地形産出の計上・開示判定の
/// どちらとも独立した計算のため、両者のどちらの前後に置いても結果は変わらないが、
/// 経済まわりの計上（地形産出・開放ポイント）を先にまとめて行い、最後に
/// 開示判定を行う順序に揃えた）。
///
/// 本クラスは [recordedPositionUpdates] を [StreamIterator] で直接読み、
/// 1件ごとに `await` で「産出の計上（[TerrainYieldAccrualCoordinator.accrue]）」
/// → 「開放ポイントの計上（[OpeningPointAccrualCoordinator.accrue]）」→
/// 「開示判定（[disclosureService.recordPosition]）・新規開示なら
/// [reveal]」の**すべてが完了してから次の位置に進む**。
///
/// ## `DisclosureCoordinator` を置き換える（composition root）
/// 本番の位置ストリーム（`NativePositionProvider.recordedPositionUpdates`）は
/// 本クラスが購読する。既存の `DisclosureCoordinator` はそのままテスト・
/// 単体クラスとして残すが、`app/lib/features/map/map_screen.dart` の
/// composition root は本クラスに置き換える（`docs/terrain-yield.md` 参照）。
///
/// ## 手動開示（「地図の中心のヘクスを開示」デバッグボタン）
/// [recordManualPosition] は、`NativePositionProvider` を経由しない直接呼び出し
/// （行id・経過時間の概念が無い一発の観測）のため、**地形産出・開放ポイントの
/// どちらの計上も行わず**開示判定と霧の解除だけを行う。ただし新規開示の場合は
/// 必ず [terrainHexCounter] を更新すること（更新しないと、地域パック範囲外に
/// いる代表の端末でこのボタンから開示したヘクスが「地形別件数」に反映されず、
/// 実機確認で地形産出が一切進まないという誤った結果になる。advisor 指摘）。
///
/// ## エラー時の挙動
/// 位置ストリーム自体がエラーを送出した場合（`StreamIterator.moveNext()` が
/// 例外を投げた場合）、`StreamIterator` は内部で `cancelOnError: true` の
/// 購読を使うため購読が終了し、以後 `moveNext()` は常に `false` を返す
/// （`DisclosureCoordinator` がストリームのエラーで購読を終了するのと同じ
/// 挙動）。一方、個々の位置の処理中（[TerrainYieldAccrualCoordinator.accrue]・
/// [OpeningPointAccrualCoordinator.accrue]・[disclosureService.recordPosition]・
/// [reveal]）で発生した例外はログに残したうえでその位置をスキップし、
/// パイプライン自体は継続する。
class TerrainYieldPipeline {
  TerrainYieldPipeline({
    required this.disclosureService,
    required this.reveal,
    required this.accrualCoordinator,
    required this.openingPointCoordinator,
    required this.terrainHexCounter,
    required this.disclosedHexRepository,
    required this.recordedPositionUpdates,
    required this.hexOpeningSpendService,
  });

  final DisclosureService disclosureService;
  final Future<void> Function(int featureId) reveal;
  final TerrainYieldAccrualCoordinator accrualCoordinator;

  /// 開放ポイント（歩行距離換算）の計上（Issue #143・T063）。
  final OpeningPointAccrualCoordinator openingPointCoordinator;
  final TerrainHexCounter terrainHexCounter;
  final Repository<DisclosedHex, HexId> disclosedHexRepository;
  final Stream<LocationPointRecord> recordedPositionUpdates;

  /// ポイント消費による未踏破ヘクスの開放（[openHexWithPoints]）で使う
  /// トランザクション本体（Issue #151・T064）。
  final HexOpeningSpendService hexOpeningSpendService;

  final ValueNotifier<TerrainYieldPipelineStats> _stats =
      ValueNotifier(TerrainYieldPipelineStats.initial());

  /// デバッグパネル表示用の観測データ（`kDebugMode` 限定の用途を想定）。
  ValueListenable<TerrainYieldPipelineStats> get stats => _stats;

  final ValueNotifier<OpeningPointPipelineStats> _openingPointStats =
      ValueNotifier(OpeningPointPipelineStats.initial());

  /// デバッグパネル表示用の開放ポイント観測データ（`kDebugMode` 限定の用途を想定・
  /// Issue #143）。
  ValueListenable<OpeningPointPipelineStats> get openingPointStats => _openingPointStats;

  final ValueNotifier<GeoPosition?> _currentPosition = ValueNotifier(null);

  /// 現在地表示（Issue #141・T058）用に公開する、直近に受け取った位置。
  ///
  /// ## なぜ [stats] に含めず別の [ValueNotifier] にしたか
  /// [stats] の更新は [accrualCoordinator.accrue]・[disclosureService.recordPosition]
  /// の両方の `await` が成功した後（`try` の末尾）にのみ行われる（クラスdoc
  /// 「エラー時の挙動」参照）。現在地表示は「その位置が地形産出・開示判定に
  /// 使えたか」とは独立した関心事であり、位置を1件受け取った時点（`try` に
  /// 入る前）で更新する方が、「GPSは届いているのに画面上の現在地が更新
  /// されない」という分かりにくい状態を避けられる。そのため本フィールドは
  /// `try` の外（[_run] のループ先頭）で更新する。
  ///
  /// ## 本 Issue の最重要点との関係（位置ストリームの購読を増やさない）
  /// 本パイプラインは既に [recordedPositionUpdates] を [StreamIterator] で
  /// 1本だけ購読している（クラスdoc「なぜ1本の直列パイプラインにするか」）。
  /// 現在地表示（`packages/location` の `MapView.currentLocation`）はこの
  /// [ValueListenable] を購読するだけであり、`NativePositionProvider` の
  /// ストリームを新たに購読しない（`stats` と全く同じ配線方式。
  /// `app/lib/features/map/map_screen.dart` から `MapView` へそのまま渡す）。
  ///
  /// ## [recordManualPosition] では更新しない
  /// デバッグ専用の「地図の中心のヘクスを開示」ボタン（[recordManualPosition]）
  /// は地図の中心座標を渡すだけの合成的な観測であり、実際の現在地ではない。
  /// これで本フィールドを更新すると、デバッグボタンを押すたびに現在地
  /// マーカーが画面中心へ飛ぶという紛らわしい挙動になるため、意図的に
  /// 更新対象から外している。
  ValueListenable<GeoPosition?> get currentPosition => _currentPosition;

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

    await openingPointCoordinator.initialize();
    _openingPointStats.value = OpeningPointPipelineStats(
      points: openingPointCoordinator.points,
      remainderMillimeters: openingPointCoordinator.remainderMillimeters,
      watermarkRowId: openingPointCoordinator.watermarkRowId,
      sessionDistanceMeters: openingPointCoordinator.sessionDistanceMeters,
      sessionStepCount: openingPointCoordinator.sessionStepCount,
      sessionHasStepData: openingPointCoordinator.sessionHasStepData,
    );

    final iterator = StreamIterator<LocationPointRecord>(recordedPositionUpdates);
    _iterator = iterator;
    unawaited(_run(iterator));
  }

  Future<void> _run(StreamIterator<LocationPointRecord> iterator) async {
    try {
      while (await iterator.moveNext()) {
        final record = iterator.current;
        // 現在地表示（currentPosition）は、地形産出の計上・開示判定の成否とは
        // 独立して、位置を受け取った時点で更新する（クラスdoc「なぜ stats に
        // 含めず別のValueNotifierにしたか」参照）。
        _currentPosition.value = record.position;
        try {
          await accrualCoordinator.accrue(record, terrainHexCounter.counts);
          await openingPointCoordinator.accrue(record);

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
          _publishOpeningPointStatsFromCoordinator();
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

  /// ポイント消費による未踏破ヘクスの開放（Issue #151・T064）。
  ///
  /// ## composition root（`map_screen.dart`）からの呼び出し方
  /// 地図タップ（`MapView.onFogHexTapped`）で得た `featureId` を、composition
  /// root が既に持つ `fogHexFeatureCollection` から [HexId] に変換したうえで
  /// 本メソッドを呼ぶ（`app/lib/map/hex_feature_lookup.dart` 参照）。
  ///
  /// ## 判定と実処理の分担
  /// 隣接・地域パック範囲内かどうか（[HexOpeningDenialReason.notAdjacentToDisclosed]・
  /// [HexOpeningDenialReason.outsidePack]）は本メソッドが `evaluateHexOpening`
  /// （`packages/core`）で判定する。ポイント残高・既に開示済みでないかの
  /// **最終確認**とDB書き込みは [hexOpeningSpendService]（`packages/location`）に
  /// 委ねる（`HexOpeningSpendService` クラスdoc「責務の境界」参照。隣接制約は
  /// 単調に真になるだけなのでトランザクション内での再確認は不要）。
  ///
  /// ## 開放成功時に更新する派生状態（`recordManualPosition` と同じ一式）
  /// 歩行による開示（[disclosureService.recordPosition]）が更新するのと同じ
  /// 派生状態——[disclosureService.known]・[terrainHexCounter]・fog の描画
  /// （[reveal]）——をここでも更新する。**[disclosureService.known] への追加を
  /// 忘れると**、後で同じヘクスへ歩いて到達した際に
  /// `DisclosureService.recordPosition` が「未知」と誤認して二重に
  /// `terrainHexCounter.increment` してしまう（advisor指摘）。
  ///
  /// 所持ポイントのキャッシュ（[openingPointCoordinator]）と HUD 表示
  /// （[openingPointStats]）は、成功・失敗（残高不足・既に開示済みの競合）の
  /// いずれの場合も [HexOpeningSpendResult.remainingPoints] で同期する
  /// （`OpeningPointAccrualCoordinator.syncPointsAfterExternalChange`
  /// クラスdoc参照）。
  Future<HexOpeningAttemptResult> openHexWithPoints(HexId hexId) async {
    final evaluation = evaluateHexOpening(
      hexId: hexId,
      regionPack: disclosureService.regionPack,
      known: disclosureService.known,
      currentPoints: openingPointCoordinator.points,
    );
    if (!evaluation.canOpen) {
      return HexOpeningAttemptResult.denied(evaluation.denialReason!);
    }

    final result = await hexOpeningSpendService.spend(
      hexId: hexId,
      terrainType: evaluation.terrainType!,
      packVersion: disclosureService.regionPack.version,
    );

    switch (result.outcome) {
      case HexOpeningSpendOutcome.alreadyDisclosed:
        openingPointCoordinator.syncPointsAfterExternalChange(result.remainingPoints);
        _publishOpeningPointStatsFromCoordinator();
        return HexOpeningAttemptResult.denied(HexOpeningDenialReason.alreadyDisclosed);
      case HexOpeningSpendOutcome.insufficientPoints:
        openingPointCoordinator.syncPointsAfterExternalChange(result.remainingPoints);
        _publishOpeningPointStatsFromCoordinator();
        return HexOpeningAttemptResult.denied(HexOpeningDenialReason.insufficientPoints);
      case HexOpeningSpendOutcome.opened:
        final disclosedHex = result.disclosedHex!;
        disclosureService.known.add(disclosedHex.hexId);
        terrainHexCounter.increment(disclosedHex.terrainType);
        await reveal(hexIdToFeatureId(disclosedHex.hexId.value));
        openingPointCoordinator.syncPointsAfterExternalChange(result.remainingPoints);
        _publishOpeningPointStatsFromCoordinator();
        return HexOpeningAttemptResult.success(
          disclosedHex,
          collectedLandmarks: result.collectedLandmarks,
        );
    }
  }

  /// `kDebugMode` 限定のデバッグ付与（Issue #151「秘書の実機の現在の状態:
  /// 所持0Pでは開放を試せない」への対応）。呼び出し元は `OpeningPointDebugPanel`
  /// （`kDebugMode` 限定のパネル）のみに限ること。**release ビルドの製品UIに
  /// 絶対に出さない**——本メソッド自体も冒頭で `kDebugMode` を確認し、万一
  /// release ビルドから誤って呼ばれても何もしない（多重の安全策）。
  Future<void> grantOpeningPointsForDebug(int amount) async {
    if (!kDebugMode) return;
    final newBalance = await openingPointCoordinator.ledger.applyAccrual(
      grantedPoints: amount,
      remainderMillimeters: openingPointCoordinator.remainderMillimeters,
      watermarkRowId: openingPointCoordinator.watermarkRowId,
    );
    openingPointCoordinator.syncPointsAfterExternalChange(newBalance);
    _publishOpeningPointStatsFromCoordinator();
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

  /// [openingPointCoordinator] の現在値から [openingPointStats] を再構築して
  /// 公開する（`_run` の通常経路・[openHexWithPoints]・
  /// [grantOpeningPointsForDebug] のいずれからも同じロジックを使う）。
  void _publishOpeningPointStatsFromCoordinator() {
    _openingPointStats.value = OpeningPointPipelineStats(
      points: openingPointCoordinator.points,
      remainderMillimeters: openingPointCoordinator.remainderMillimeters,
      watermarkRowId: openingPointCoordinator.watermarkRowId,
      lastSegmentDistanceMeters: openingPointCoordinator.lastSegmentDistanceMeters,
      lastAppliedMultiplier: openingPointCoordinator.lastAppliedMultiplier,
      lastReason: openingPointCoordinator.lastReason,
      sessionDistanceMeters: openingPointCoordinator.sessionDistanceMeters,
      sessionStepCount: openingPointCoordinator.sessionStepCount,
      sessionHasStepData: openingPointCoordinator.sessionHasStepData,
    );
  }

  void _log(String message) {
    developer.log(message, name: 'terra_town.terrain_yield_pipeline');
    debugPrint('[terra_town.terrain_yield_pipeline] $message');
  }
}
