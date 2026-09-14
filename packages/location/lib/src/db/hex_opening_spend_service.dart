// ignore_for_file: prefer_initializing_formals
// 公開の名前付き引数（regionPack・now）をプライベートフィールド（_regionPack・
// _now）へそのまま代入する箇所があり、initializing formal（this._regionPack 等）
// にすると外部呼び出し側の引数名がプライベート名になってしまうため使えない
// （`region_pack_repository.dart` と同じ判断）。

import 'package:terra_town_core/terra_town_core.dart';

import 'collection_repository.dart';
import 'disclosed_hex_repository.dart';
import 'game_database.dart';
import 'landmark_collection_support.dart';
import 'opening_point_ledger.dart';

/// [HexOpeningSpendService.spend] の結果種別（Issue #151・T064）。
enum HexOpeningSpendOutcome {
  /// 開放に成功した（ポイント減算・`disclosed_hex` への追加の両方がコミット済み）。
  opened,

  /// トランザクション内で再確認した時点で既に開示済みだった
  /// （呼び出し直前の判定〔`evaluateHexOpening`〕から確定までの間に、歩行等の
  /// 別経路で先に開示された競合。Issue #151「入手と消費の競合」）。
  alreadyDisclosed,

  /// トランザクション内で再確認した時点でポイントが不足していた
  /// （呼び出し直前の判定から確定までの間に、別の消費操作が先にポイントを
  /// 使い切った競合）。
  insufficientPoints,
}

/// [HexOpeningSpendService.spend] の戻り値。
class HexOpeningSpendResult {
  const HexOpeningSpendResult._({
    required this.outcome,
    required this.remainingPoints,
    this.disclosedHex,
    this.collectedLandmarks = const [],
  });

  final HexOpeningSpendOutcome outcome;

  /// トランザクション確定直後の実残高（成功・失敗いずれの場合も、その時点の
  /// 正しい残高を返す。呼び出し側はこれをキャッシュの同期に使える。
  /// `OpeningPointLedgerStore.applyAccrual` の戻り値と同じ考え方）。
  final int remainingPoints;

  /// [outcome] が [HexOpeningSpendOutcome.opened] の場合のみ非null。
  final DisclosedHex? disclosedHex;

  /// 開放と同時に新規収集された名所（Issue #159・T070）。
  ///
  /// [outcome] が [HexOpeningSpendOutcome.opened] でない場合、または
  /// [HexOpeningSpendService] に `regionPack`（`collectionRepository`）が
  /// 渡されていない場合は常に空リスト。名所の無いヘクスを開放した場合も
  /// 空リストになる（`collectMethod: point` で記録される。
  /// `docs/landmark_objects.md` §3.2）。
  final List<LandmarkCollectionRecord> collectedLandmarks;
}

/// 開放ポイントを消費して未踏破ヘクスを開放する、DBトランザクションを伴う実処理
/// （Issue #151・T064）。
///
/// ## 責務の境界（`evaluateHexOpening`・`core` との分担）
/// 「隣接しているか」「地域パックに収録されているか（地形タイプ）」の判定は
/// **本クラスの責務ではない**。これらは開示が一度成立すれば以後ずっと真であり
/// （単調・`docs/opening_points.md` §5.2 の隣接制約は「一度地続きになった場所は
/// 地続きのまま」）、呼び出し側が [spend] を呼ぶ前に
/// `evaluateHexOpening`（`packages/core`）で判定済みであることを前提とする
/// （advisor 指摘: 「adjacency can be pre-checked outside — disclosure is
/// monotonic, so "adjacent" never becomes false」）。
///
/// 本クラスが**トランザクション内で再確認する**のは、時間とともに変化しうる
/// 2つの状態だけである:
///   - 既に開示済みでないか（[HexOpeningSpendOutcome.alreadyDisclosed]）—
///     歩行による開示（`DisclosureService`）が呼び出し直前の判定から確定までの
///     間に同じヘクスを先に開示している競合。`DisclosedHexRepository.save` の
///     `insertOrIgnore` に頼らず [DisclosedHexRepository.findById] で明示的に
///     再確認する（`insertOrIgnore` に任せると、競合時に「開放は失敗したのに
///     ポイントだけ減る」という誤りを見逃してしまうため）。
///   - ポイント残高が足りているか（[HexOpeningSpendOutcome.insufficientPoints]）—
///     別の消費操作（同時タップ等）が先にポイントを使い切っている競合。
///
/// ## 二重管理をしない（Issue #143 の入手側と同じ保存先）
/// 既定の [OpeningPointBalanceStore] は [OpeningPointBalanceRepository]
/// （`opening_point_ledger.dart`）であり、`OpeningPointLedger`（歩行距離換算の
/// 入手側・Issue #143）と**同じ** `settings.opening_point.points` を読み書きする。
/// 開放ポイントの残高を別の場所に持たない。
///
/// ## 消費と開示は同一トランザクション（Issue #151 受け入れ基準）
/// [spend] はポイントの減算と [DisclosedHexRepository.save] を
/// [GameDatabase.transaction] 内で行う。どちらか一方だけが反映される状態は
/// 起こらない（Issue #138・#143 と同じ方針）。
///
/// ## 入手（歩行距離換算）との競合に対する安全性（Issue #151「入手と消費の競合」）
/// Drift の `transaction()` は同一コネクション上で排他的に実行される
/// （`_StatementBasedTransactionExecutor.ensureOpen` が「Block the main
/// database... while this transaction is active」と明記しており、実装上も
/// 親executorの `_lock` を掴んだまま `BEGIN`〜`COMMIT`/`ROLLBACK` まで
/// 保持し続ける）。そのため、本クラスの [spend] と
/// `OpeningPointLedger.applyAccrual`（歩行距離換算の計上）が同じ
/// [GameDatabase] に対してほぼ同時に呼ばれても、片方のトランザクションが
/// 完全に確定してからもう片方が開始する——DBレベルでの残高のロスト
/// アップデートは起こらない（`hex_opening_spend_service_test.dart`
/// 「入手と消費が同時に起きても残高が食い違わない」で検証）。
///
/// ただし、これはDB上の残高についての保証であり、呼び出し側
/// （`OpeningPointAccrualCoordinator._points`）が持つ**メモリ上のキャッシュ**は
/// 別途同期が必要である。呼び出し側は [spend] の [HexOpeningSpendResult.remainingPoints]
/// を使って `OpeningPointAccrualCoordinator.syncPointsAfterExternalChange` を
/// 呼ぶこと（`TerrainYieldPipeline.openHexWithPoints` 参照）。
class HexOpeningSpendService {
  HexOpeningSpendService(
    this._database, {
    OpeningPointBalanceStore? balanceStore,
    DisclosedHexRepository? disclosedHexRepository,
    RegionPack? regionPack,
    CollectionRepository? collectionRepository,
    this.onCollected,
    DateTime Function() now = DateTime.now,
  })  : _balanceStore = balanceStore ?? OpeningPointBalanceRepository(_database),
        _disclosedHexRepository =
            disclosedHexRepository ?? DisclosedHexRepository(_database),
        _regionPack = regionPack,
        _collectionRepository = collectionRepository ?? CollectionRepository(_database),
        _now = now;

  final GameDatabase _database;
  final OpeningPointBalanceStore _balanceStore;
  final DisclosedHexRepository _disclosedHexRepository;

  /// 名所の収集記録（Issue #159・T070）に使う地域パック。**`terrainOf` は
  /// 一切呼ばない**（本クラスは `RegionPack.terrainOf` を再度呼ばない設計を
  /// 保つ。クラスdoc参照）。`pointsOfInterestIn` の呼び出しのみに使う。
  ///
  /// null の場合（既存の呼び出し元・テストとの後方互換のため既定は null）は
  /// 名所の収集判定を一切行わない（[HexOpeningSpendResult.collectedLandmarks]
  /// は常に空リスト）。
  final RegionPack? _regionPack;
  final CollectionRepository _collectionRepository;
  final DateTime Function() _now;

  /// 開放と同時に新規収集された名所がある場合に、トランザクションのコミット後に
  /// 呼ばれる（Issue #159。`LandmarkAwareDisclosedHexRepository.onCollected` と
  /// 同じ方針——DBトランザクションの最中にUI更新の副作用を持ち込まない）。
  final void Function(List<LandmarkCollectionRecord> records)? onCollected;

  /// [hexId] を開放ポイントで開放する。
  ///
  /// 呼び出し側は事前に `evaluateHexOpening` で `canOpen: true`（隣接・地域パック
  /// 範囲内であること）を確認していること。[terrainType]・[packVersion] は
  /// その判定で得られた値（[HexOpeningEvaluation.terrainType]・
  /// `RegionPack.version`）をそのまま渡すこと——本クラスが `RegionPack` を
  /// 保持している場合（[_regionPack]・Issue #159の名所収集用）でも
  /// `RegionPack.terrainOf` は一切呼ばない（`pointsOfInterestIn` の呼び出しのみに
  /// 使う。`region_pack.dart`「呼んでよいのは新規開示の瞬間だけ」を、
  /// `evaluateHexOpening` の呼び出し1回に集約する設計。クラスdoc参照）。
  Future<HexOpeningSpendResult> spend({
    required HexId hexId,
    required TerrainType terrainType,
    required PackVersion packVersion,
    int cost = openingPointCostPerHex,
  }) async {
    var outcome = HexOpeningSpendOutcome.opened;
    DisclosedHex? disclosedHex;
    var remainingPoints = 0;
    var collectedLandmarks = const <LandmarkCollectionRecord>[];

    await _database.transaction(() async {
      final existing = await _disclosedHexRepository.findById(hexId);
      if (existing != null) {
        outcome = HexOpeningSpendOutcome.alreadyDisclosed;
        remainingPoints = await _balanceStore.read();
        return;
      }

      final currentPoints = await _balanceStore.read();
      if (currentPoints < cost) {
        outcome = HexOpeningSpendOutcome.insufficientPoints;
        remainingPoints = currentPoints;
        return;
      }

      remainingPoints = currentPoints - cost;
      await _balanceStore.write(remainingPoints);

      final hex = DisclosedHex(
        hexId: hexId,
        terrainType: terrainType,
        discoveredAtVersion: packVersion,
      );
      await _disclosedHexRepository.save(hex);
      disclosedHex = hex;
      outcome = HexOpeningSpendOutcome.opened;

      // 名所の収集記録（Issue #159・T070）。`disclosed_hex` の保存・ポイント
      // 減算と**同一トランザクション**（クラスdoc「消費と開示は同一
      // トランザクション」と同じ理由。途中で失敗すればポイント・開示状態
      // どちらも変化しない）。`_regionPack` が渡されていない呼び出し元
      // （既存テスト等）との後方互換のため、null なら何もしない。
      final regionPack = _regionPack;
      if (regionPack != null) {
        collectedLandmarks = await collectLandmarksForDisclosedHex(
          disclosedHex: hex,
          regionPack: regionPack,
          collectionRepository: _collectionRepository,
          collectMethod: CollectMethod.point,
          now: _now,
        );
      }
    });

    if (collectedLandmarks.isNotEmpty) {
      onCollected?.call(collectedLandmarks);
    }

    return HexOpeningSpendResult._(
      outcome: outcome,
      remainingPoints: remainingPoints,
      disclosedHex: disclosedHex,
      collectedLandmarks: collectedLandmarks,
    );
  }
}
