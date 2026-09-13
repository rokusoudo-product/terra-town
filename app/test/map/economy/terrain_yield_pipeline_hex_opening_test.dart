import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:terra_town_core/terra_town_core.dart';
import 'package:terra_town_location/terra_town_location.dart';

import 'package:terra_town/map/economy/opening_point_accrual_coordinator.dart';
import 'package:terra_town/map/economy/terrain_yield_accrual_coordinator.dart';
import 'package:terra_town/map/economy/terrain_yield_pipeline.dart';

/// [TerrainYieldPipeline.openHexWithPoints]・[TerrainYieldPipeline.grantOpeningPointsForDebug]
/// （Issue #151・T064）の統合テスト。
///
/// `hex_opening_spend_service_test.dart`（`packages/location`）が
/// トランザクションの原子性・入手との競合を検証済みのため、本ファイルは
/// **パイプラインが担う派生状態の更新**——`disclosureService.known` への追加・
/// `terrainHexCounter` の増分・`reveal`（fog解除）の呼び出し・
/// `openingPointStats`（HUD 用キャッシュ）の同期——が正しく行われることに絞る
/// （advisor 指摘: `known` を更新し忘れると、後で同じヘクスに歩いて到達した際に
/// 二重に `terrainHexCounter.increment` してしまう）。

class _FakeRegionPack implements RegionPack {
  _FakeRegionPack({required this.terrainByHex, this.neighborsByHex = const {}});

  @override
  final PackVersion version = const PackVersion('test-v1');

  final Map<HexId, TerrainType> terrainByHex;
  final Map<HexId, List<HexId>> neighborsByHex;

  @override
  TerrainType? terrainOf(HexId hexId) => terrainByHex[hexId];

  @override
  DistrictId? districtOf(HexId hexId) => null;

  @override
  List<District> get districts => const [];

  @override
  List<PointOfInterest> get pointsOfInterest => const [];

  @override
  Iterable<HexId> neighborsOf(HexId hexId) => neighborsByHex[hexId] ?? const [];
}

class _FakeTerrainYieldLedger implements TerrainYieldLedgerStore {
  int watermarkRowId = 0;
  Map<Resource, int> remainderMicros = {};

  @override
  Future<TerrainYieldLedgerSnapshot> readSnapshot() async => TerrainYieldLedgerSnapshot(
        watermarkRowId: watermarkRowId,
        remainderMicros: Map.of(remainderMicros),
      );

  @override
  Future<void> applyAccrual({
    required Map<Resource, int> grantedAmounts,
    required Map<Resource, int> remainderMicros,
    required int watermarkRowId,
  }) async {
    this.watermarkRowId = watermarkRowId;
    this.remainderMicros = Map.of(remainderMicros);
  }
}

void main() {
  const target = HexId(200);
  const alreadyKnownNeighbor = HexId(201);

  /// 「target が alreadyKnownNeighbor に隣接している」パックと、
  /// `OpeningPointLedger`（実DB）を使ったポイント残高を用意して
  /// [TerrainYieldPipeline] を組み立てる。[initialPoints] を渡すと、その所持数
  /// から始まった状態を作れる。
  Future<({
    TerrainYieldPipeline pipeline,
    GameDatabase database,
    DisclosedHexSet known,
    DisclosedHexRepository disclosedHexRepository,
    TerrainHexCounter terrainHexCounter,
    List<int> revealed,
  })> buildHarness({
    required int initialPoints,
    Map<HexId, TerrainType>? terrainByHex,
    Set<HexId>? initiallyKnown,
  }) async {
    terrainByHex ??= {
      target: TerrainType.forest,
      alreadyKnownNeighbor: TerrainType.vacantLot,
    };
    initiallyKnown ??= {alreadyKnownNeighbor};

    final database = GameDatabase.forTesting();
    final disclosedHexRepository = DisclosedHexRepository(database);
    // 実DB（database）を裏付けとする本番同様のledgerを使う。
    // HexOpeningSpendService（既定のOpeningPointBalanceRepository）と
    // 同じ opening_point.points を読み書きするため（二重管理しない・
    // Issue #151「入手側と同じledgerを使う」要件をテストでも守る）。
    await OpeningPointBalanceRepository(database).write(initialPoints);
    final openingPointLedger = OpeningPointLedger(database);

    final known = DisclosedHexSet.from(initiallyKnown);
    final revealed = <int>[];
    final terrainHexCounter = TerrainHexCounter();

    final regionPack = _FakeRegionPack(
      terrainByHex: terrainByHex,
      neighborsByHex: {
        target: [alreadyKnownNeighbor],
      },
    );

    final disclosureService = DisclosureService(
      hexLocator: const RecordedHexLocator(),
      regionPack: regionPack,
      known: known,
      repository: disclosedHexRepository,
    );

    final openingPointCoordinator = OpeningPointAccrualCoordinator(ledger: openingPointLedger);
    await openingPointCoordinator.initialize();

    final accrualCoordinator = TerrainYieldAccrualCoordinator(ledger: _FakeTerrainYieldLedger());
    await accrualCoordinator.initialize();

    final pipeline = TerrainYieldPipeline(
      disclosureService: disclosureService,
      reveal: (featureId) async => revealed.add(featureId),
      accrualCoordinator: accrualCoordinator,
      openingPointCoordinator: openingPointCoordinator,
      hexOpeningSpendService: HexOpeningSpendService(database),
      terrainHexCounter: terrainHexCounter,
      disclosedHexRepository: disclosedHexRepository,
      recordedPositionUpdates: const Stream<LocationPointRecord>.empty(),
    );

    return (
      pipeline: pipeline,
      database: database,
      known: known,
      disclosedHexRepository: disclosedHexRepository,
      terrainHexCounter: terrainHexCounter,
      revealed: revealed,
    );
  }

  group('TerrainYieldPipeline.openHexWithPoints', () {
    test('隣接・残高十分なら開放でき、known・terrainHexCounter・revealのすべてが更新される', () async {
      final h = await buildHarness(initialPoints: 3);
      addTearDown(h.database.close);

      final result = await h.pipeline.openHexWithPoints(target);

      expect(result.success, isTrue);
      expect(result.disclosedHex!.hexId, target);
      expect(result.disclosedHex!.terrainType, TerrainType.forest);

      expect(h.known.contains(target), isTrue, reason: '歩いて再訪した際の二重加算を防ぐため必須');
      expect(h.terrainHexCounter.counts, {TerrainType.forest: 1});
      expect(h.revealed, [hexIdToFeatureId(target.value)]);
      expect(h.pipeline.openingPointCoordinator.points, 2);
      expect(h.pipeline.openingPointStats.value.points, 2);

      final persisted = await h.disclosedHexRepository.findById(target);
      expect(persisted, isNotNull);
    });

    test('飛び地（隣接していない）は拒否され、DB・派生状態のいずれも変化しない', () async {
      final h = await buildHarness(
        initialPoints: 5,
        initiallyKnown: const {}, // target はどのヘクスにも隣接しない
      );
      addTearDown(h.database.close);

      final result = await h.pipeline.openHexWithPoints(target);

      expect(result.success, isFalse);
      expect(result.denialReason, HexOpeningDenialReason.notAdjacentToDisclosed);
      expect(h.known.contains(target), isFalse);
      expect(h.terrainHexCounter.counts, isEmpty);
      expect(h.revealed, isEmpty);
      expect(h.pipeline.openingPointCoordinator.points, 5, reason: '拒否時はポイントを消費しない');

      final persisted = await h.disclosedHexRepository.findById(target);
      expect(persisted, isNull);
    });

    test('ポイント不足なら拒否され、HUD用キャッシュも0のまま同期される', () async {
      final h = await buildHarness(initialPoints: 0);
      addTearDown(h.database.close);

      final result = await h.pipeline.openHexWithPoints(target);

      expect(result.success, isFalse);
      expect(result.denialReason, HexOpeningDenialReason.insufficientPoints);
      expect(h.known.contains(target), isFalse);
      expect(h.pipeline.openingPointStats.value.points, 0);
    });

    test('既に開示済みなら拒否される（歩行が先着した競合を模す）', () async {
      final h = await buildHarness(initialPoints: 5);
      addTearDown(h.database.close);

      // 歩行によって先に開示済みになっていた状態を模す（DB・known の両方に反映）。
      await h.disclosedHexRepository.save(
        const DisclosedHex(
          hexId: target,
          terrainType: TerrainType.forest,
          discoveredAtVersion: PackVersion('test-v1'),
        ),
      );
      h.known.add(target);

      final result = await h.pipeline.openHexWithPoints(target);

      expect(result.success, isFalse);
      expect(result.denialReason, HexOpeningDenialReason.alreadyDisclosed);
      expect(h.pipeline.openingPointCoordinator.points, 5, reason: '開放は失敗したのにポイントだけ減ってはならない');
    });

    test('海のヘクスも開放できる（docs/opening_points.md §6）', () async {
      final h = await buildHarness(
        initialPoints: 1,
        terrainByHex: {
          target: TerrainType.sea,
          alreadyKnownNeighbor: TerrainType.vacantLot,
        },
      );
      addTearDown(h.database.close);

      final result = await h.pipeline.openHexWithPoints(target);

      expect(result.success, isTrue);
      expect(result.disclosedHex!.terrainType, TerrainType.sea);
    });
  });

  group('TerrainYieldPipeline.grantOpeningPointsForDebug', () {
    test('kDebugModeでは残高が増え、キャッシュ・HUD統計も同期される', () async {
      final h = await buildHarness(initialPoints: 0);
      addTearDown(h.database.close);

      // flutter test はデバッグビルド相当（kDebugMode == true）で実行されるため、
      // このテスト自体が「release ビルドでは何もしない」ことの直接証明にはならない
      // （kDebugModeはコンパイル時定数でありテストのビルドモードでは常にtrue）。
      // release相当の分岐（早期return）はコードレビューで確認する。
      await h.pipeline.grantOpeningPointsForDebug(10);

      expect(h.pipeline.openingPointCoordinator.points, 10);
      expect(h.pipeline.openingPointStats.value.points, 10);

      final ledgerSnapshot = await OpeningPointLedger(h.database).readSnapshot();
      expect(ledgerSnapshot.points, 10);
    });

    test('上限（cap）を超えては付与されない', () async {
      final h = await buildHarness(initialPoints: openingPointStockCap - 2);
      addTearDown(h.database.close);

      await h.pipeline.grantOpeningPointsForDebug(10);

      expect(h.pipeline.openingPointCoordinator.points, openingPointStockCap);
    });
  });
}
