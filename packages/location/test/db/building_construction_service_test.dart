import 'package:flutter_test/flutter_test.dart';
import 'package:terra_town_core/terra_town_core.dart';
import 'package:terra_town_location/terra_town_location.dart';

/// [RegionPack.districtOf]・[RegionPack.neighborsOf] だけを設定できるフェイク
/// （`packages/core/test/opening/opening_point_test.dart` の `_FakeRegionPack` と
/// 同じ手法）。[terrainOf] は本テストでは常に null を返す——`_evaluate` は
/// 未開示ヘクスの隣接地形を [RegionPack.terrainOf] から解決するが、本テストは
/// 隣接ヘクスも `DisclosedHexRepository` で開示済みにしてスナップショットを
/// 使う方式に統一しているため、実際には呼ばれない想定。
class _FakeRegionPack implements RegionPack {
  _FakeRegionPack({
    required this.version,
    this.districtByHex = const {},
    this.neighborsByHex = const {},
  });

  @override
  final PackVersion version;

  final Map<HexId, DistrictId> districtByHex;
  final Map<HexId, List<HexId>> neighborsByHex;

  @override
  TerrainType? terrainOf(HexId hexId) => null;

  @override
  DistrictId? districtOf(HexId hexId) => districtByHex[hexId];

  @override
  List<District> get districts => const [];

  @override
  List<PointOfInterest> get pointsOfInterest => const [];

  @override
  Iterable<HexId> neighborsOf(HexId hexId) => neighborsByHex[hexId] ?? const [];

  @override
  Iterable<PointOfInterest> pointsOfInterestIn(HexId hexId) => const [];
}

/// [BuildingRepository.insert] を意図したタイミングで失敗させるフェイク
/// （`hex_opening_spend_service_test.dart` の `_ThrowingDisclosedHexRepository`
/// と同じ手法。トランザクションの原子性を検証するために使う）。
class _ThrowingBuildingRepository extends BuildingRepository {
  _ThrowingBuildingRepository(super.database);

  bool throwOnNextInsert = false;

  @override
  Future<BuildingRow> insert({
    required HexId hexId,
    required BuildingType buildingType,
    required DistrictId? districtId,
  }) async {
    if (throwOnNextInsert) {
      throwOnNextInsert = false;
      throw StateError('意図的な失敗（テスト用）');
    }
    return super.insert(
      hexId: hexId,
      buildingType: buildingType,
      districtId: districtId,
    );
  }
}

void main() {
  const hex = HexId(42);
  const version = PackVersion('test-pack');

  group('BuildingConstructionService（基本動作）', () {
    late GameDatabase database;
    late InventoryRepository inventoryRepository;
    late DisclosedHexRepository disclosedHexRepository;
    late BuildingRepository buildingRepository;

    setUp(() {
      database = GameDatabase.forTesting();
      inventoryRepository = InventoryRepository(database);
      disclosedHexRepository = DisclosedHexRepository(database);
      buildingRepository = BuildingRepository(database);
    });

    tearDown(() async => database.close());

    Future<void> discloseVacantLot(HexId hexId) => disclosedHexRepository.save(
      DisclosedHex(
        hexId: hexId,
        terrainType: TerrainType.vacantLot,
        discoveredAtVersion: version,
      ),
    );

    test('資材が足りていれば建てられ、資材が減り building 行が増える', () async {
      await discloseVacantLot(hex);
      await inventoryRepository.add(Resource.wood, 20);
      await inventoryRepository.add(Resource.stone, 10);

      final service = BuildingConstructionService(
        database,
        regionPack: _FakeRegionPack(
          version: version,
          districtByHex: {hex: const DistrictId('city-1')},
        ),
      );

      final result = await service.build(
        hexId: hex,
        buildingType: BuildingType.house,
      );

      expect(result.outcome, BuildOutcome.built);
      expect(await inventoryRepository.amountOf(Resource.wood), 0);
      expect(await inventoryRepository.amountOf(Resource.stone), 0);

      final building = await buildingRepository.findByHexId(hex);
      expect(building, isNotNull);
      expect(building!.buildingType, BuildingType.house);
      expect(building.level, 1);
      expect(building.districtId, 'city-1');
    });

    test('資材不足なら建てられず、資材・building のどちらも変化しない', () async {
      await discloseVacantLot(hex);
      await inventoryRepository.add(Resource.wood, 5); // house は木20必要

      final service = BuildingConstructionService(
        database,
        regionPack: _FakeRegionPack(version: version),
      );

      final result = await service.build(
        hexId: hex,
        buildingType: BuildingType.house,
      );

      expect(result.outcome, BuildOutcome.denied);
      expect(result.denialReason, BuildDenialReason.insufficientResources);
      expect(result.missingResources[Resource.wood], 15);
      expect(result.missingResources[Resource.stone], 10);

      expect(await inventoryRepository.amountOf(Resource.wood), 5);
      expect(await buildingRepository.findByHexId(hex), isNull);
    });

    test('既に建物がある場合は建てられない（1マス1建物）', () async {
      await discloseVacantLot(hex);
      await buildingRepository.insert(
        hexId: hex,
        buildingType: BuildingType.cropField,
        districtId: null,
      );
      await inventoryRepository.add(Resource.wood, 20);
      await inventoryRepository.add(Resource.stone, 10);

      final service = BuildingConstructionService(
        database,
        regionPack: _FakeRegionPack(version: version),
      );

      final result = await service.build(
        hexId: hex,
        buildingType: BuildingType.house,
      );

      expect(result.outcome, BuildOutcome.denied);
      expect(result.denialReason, BuildDenialReason.alreadyBuilt);
      // 元の建物のまま（上書きされない）。
      final building = await buildingRepository.findByHexId(hex);
      expect(building!.buildingType, BuildingType.cropField);
    });

    test('未開示のヘクスには建てられない', () async {
      // discloseVacantLot を呼ばない = 未開示のまま。
      await inventoryRepository.add(Resource.wood, 20);
      await inventoryRepository.add(Resource.stone, 10);

      final service = BuildingConstructionService(
        database,
        regionPack: _FakeRegionPack(version: version),
      );

      final result = await service.build(
        hexId: hex,
        buildingType: BuildingType.house,
      );

      expect(result.outcome, BuildOutcome.denied);
      expect(result.denialReason, BuildDenialReason.notDisclosed);
      expect(await buildingRepository.findByHexId(hex), isNull);
    });

    test('空き地ではない地形には建てられない', () async {
      await disclosedHexRepository.save(
        DisclosedHex(
          hexId: hex,
          terrainType: TerrainType.forest,
          discoveredAtVersion: version,
        ),
      );
      await inventoryRepository.add(Resource.wood, 20);
      await inventoryRepository.add(Resource.stone, 10);

      final service = BuildingConstructionService(
        database,
        regionPack: _FakeRegionPack(version: version),
      );

      final result = await service.build(
        hexId: hex,
        buildingType: BuildingType.house,
      );

      expect(result.outcome, BuildOutcome.denied);
      expect(result.denialReason, BuildDenialReason.notVacantLot);
    });

    test('リゾートは海に隣接していないと建てられない', () async {
      await discloseVacantLot(hex);
      await inventoryRepository.add(Resource.wood, 30);
      await inventoryRepository.add(Resource.stone, 20);
      await inventoryRepository.add(Resource.iron, 10);

      final service = BuildingConstructionService(
        database,
        regionPack: _FakeRegionPack(version: version),
      );

      final result = await service.build(
        hexId: hex,
        buildingType: BuildingType.resort,
      );

      expect(result.outcome, BuildOutcome.denied);
      expect(result.denialReason, BuildDenialReason.notAdjacentToSea);
    });

    test('リゾートは海に隣接する空き地になら建てられる', () async {
      const seaNeighbor = HexId(43);
      await discloseVacantLot(hex);
      await disclosedHexRepository.save(
        DisclosedHex(
          hexId: seaNeighbor,
          terrainType: TerrainType.sea,
          discoveredAtVersion: version,
        ),
      );
      await inventoryRepository.add(Resource.wood, 30);
      await inventoryRepository.add(Resource.stone, 20);
      await inventoryRepository.add(Resource.iron, 10);

      final service = BuildingConstructionService(
        database,
        regionPack: _FakeRegionPack(
          version: version,
          neighborsByHex: {
            hex: const [seaNeighbor],
          },
        ),
      );

      final result = await service.build(
        hexId: hex,
        buildingType: BuildingType.resort,
      );

      expect(result.outcome, BuildOutcome.built);
    });

    test('ミュージアムは住宅系建物に隣接する空き地になら建てられる', () async {
      const houseNeighbor = HexId(44);
      await discloseVacantLot(hex);
      await discloseVacantLot(houseNeighbor);
      await buildingRepository.insert(
        hexId: houseNeighbor,
        buildingType: BuildingType.house,
        districtId: null,
      );
      await inventoryRepository.add(Resource.wood, 30);
      await inventoryRepository.add(Resource.stone, 30);
      await inventoryRepository.add(Resource.iron, 20);

      final service = BuildingConstructionService(
        database,
        regionPack: _FakeRegionPack(
          version: version,
          neighborsByHex: {
            hex: const [houseNeighbor],
          },
        ),
      );

      final result = await service.build(
        hexId: hex,
        buildingType: BuildingType.museum,
      );

      expect(result.outcome, BuildOutcome.built);
    });

    test('採石場は隣接条件なしで空き地ならどこでも建てられる', () async {
      await discloseVacantLot(hex);
      await inventoryRepository.add(Resource.wood, 20);

      final service = BuildingConstructionService(
        database,
        regionPack: _FakeRegionPack(version: version),
      );

      final result = await service.build(
        hexId: hex,
        buildingType: BuildingType.quarry,
      );

      expect(result.outcome, BuildOutcome.built);
    });
  });

  group('BuildingConstructionService（トランザクションの原子性）', () {
    test('building への保存に失敗したら、資材の消費もロールバックされる', () async {
      final database = GameDatabase.forTesting();
      addTearDown(database.close);

      final disclosedHexRepository = DisclosedHexRepository(database);
      final inventoryRepository = InventoryRepository(database);
      await disclosedHexRepository.save(
        DisclosedHex(
          hexId: hex,
          terrainType: TerrainType.vacantLot,
          discoveredAtVersion: version,
        ),
      );
      await inventoryRepository.add(Resource.wood, 20);
      await inventoryRepository.add(Resource.stone, 10);

      final throwingBuildingRepository = _ThrowingBuildingRepository(database)
        ..throwOnNextInsert = true;
      final throwingService = BuildingConstructionService(
        database,
        buildingRepository: throwingBuildingRepository,
        regionPack: _FakeRegionPack(version: version),
      );

      await expectLater(
        throwingService.build(hexId: hex, buildingType: BuildingType.house),
        throwsA(isA<StateError>()),
      );

      expect(
        await inventoryRepository.amountOf(Resource.wood),
        20,
        reason: 'building への保存が失敗した以上、資材の消費も反映されていてはならない',
      );
      expect(await inventoryRepository.amountOf(Resource.stone), 10);
      expect(await BuildingRepository(database).findByHexId(hex), isNull);

      // 通常のサービス（失敗しない）でやり直せば成功することを確認し、
      // 上記の失敗がロールバック起因であって恒久的な破損ではないことを示す。
      final normalService = BuildingConstructionService(
        database,
        regionPack: _FakeRegionPack(version: version),
      );
      final result = await normalService.build(
        hexId: hex,
        buildingType: BuildingType.house,
      );
      expect(result.outcome, BuildOutcome.built);
    });
  });
}
