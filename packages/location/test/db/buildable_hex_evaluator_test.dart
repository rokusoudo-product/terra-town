import 'package:flutter_test/flutter_test.dart';
import 'package:terra_town_core/terra_town_core.dart';
import 'package:terra_town_location/terra_town_location.dart';

/// [RegionPack.neighborsOf] のみを設定できるフェイク
/// （`building_construction_service_test.dart` の `_FakeRegionPack` と同じ手法）。
class _FakeRegionPack implements RegionPack {
  _FakeRegionPack({required this.version});

  @override
  final PackVersion version;

  @override
  TerrainType? terrainOf(HexId hexId) => null;

  @override
  DistrictId? districtOf(HexId hexId) => null;

  @override
  List<District> get districts => const [];

  @override
  List<PointOfInterest> get pointsOfInterest => const [];

  // 本テストは house/cropField（隣接条件を持たない建物）のみを扱うため、
  // 隣接ヘクスは常に空でよい（隣接条件の判定は
  // `building_construction_service_test.dart` が担当する）。
  @override
  Iterable<HexId> neighborsOf(HexId hexId) => const [];

  @override
  Iterable<PointOfInterest> pointsOfInterestIn(HexId hexId) => const [];
}

void main() {
  const version = PackVersion('test-pack');
  const vacantHex = HexId(1);
  const forestHex = HexId(2);

  late GameDatabase database;
  late DisclosedHexRepository disclosedHexRepository;
  late InventoryRepository inventoryRepository;
  late BuildingRepository buildingRepository;

  setUp(() async {
    database = GameDatabase.forTesting();
    disclosedHexRepository = DisclosedHexRepository(database);
    inventoryRepository = InventoryRepository(database);
    buildingRepository = BuildingRepository(database);

    await disclosedHexRepository.save(
      const DisclosedHex(
        hexId: vacantHex,
        terrainType: TerrainType.vacantLot,
        discoveredAtVersion: version,
      ),
    );
    await disclosedHexRepository.save(
      const DisclosedHex(
        hexId: forestHex,
        terrainType: TerrainType.forest,
        discoveredAtVersion: version,
      ),
    );
  });

  tearDown(() async => database.close());

  group('BuildableHexEvaluator.evaluateAll', () {
    test('開示済みヘクスのみを対象に、空き地だけが canBuild になりうる', () async {
      await inventoryRepository.add(Resource.wood, 20);
      await inventoryRepository.add(Resource.stone, 10);

      final evaluator = BuildableHexEvaluator(
        database,
        regionPack: _FakeRegionPack(version: version),
      );

      final result = await evaluator.evaluateAll(
        buildingType: BuildingType.house,
      );

      expect(result.keys, containsAll([vacantHex, forestHex]));
      expect(result[vacantHex]!.canBuild, isTrue);
      expect(result[forestHex]!.canBuild, isFalse);
      expect(result[forestHex]!.denialReason, BuildDenialReason.notVacantLot);
    });

    test('資材が不足している場合は空き地でも canBuild にならない', () async {
      // 資材を一切加算しない。

      final evaluator = BuildableHexEvaluator(
        database,
        regionPack: _FakeRegionPack(version: version),
      );

      final result = await evaluator.evaluateAll(
        buildingType: BuildingType.house,
      );

      expect(result[vacantHex]!.canBuild, isFalse);
      expect(
        result[vacantHex]!.denialReason,
        BuildDenialReason.insufficientResources,
      );
    });

    test('既に建物がある空き地は canBuild にならない', () async {
      await inventoryRepository.add(Resource.wood, 20);
      await inventoryRepository.add(Resource.stone, 10);
      await buildingRepository.insert(
        hexId: vacantHex,
        buildingType: BuildingType.cropField,
        districtId: null,
      );

      final evaluator = BuildableHexEvaluator(
        database,
        regionPack: _FakeRegionPack(version: version),
      );

      final result = await evaluator.evaluateAll(
        buildingType: BuildingType.house,
      );

      expect(result[vacantHex]!.canBuild, isFalse);
      expect(result[vacantHex]!.denialReason, BuildDenialReason.alreadyBuilt);
    });

    test('未開示ヘクスは結果に含まれない', () async {
      final evaluator = BuildableHexEvaluator(
        database,
        regionPack: _FakeRegionPack(version: version),
      );

      final result = await evaluator.evaluateAll(
        buildingType: BuildingType.house,
      );

      expect(result.containsKey(const HexId(999)), isFalse);
    });
  });

  group('BuildableHexEvaluator.evaluateOne', () {
    test('未開示ヘクスは notDisclosed を返す', () async {
      final evaluator = BuildableHexEvaluator(
        database,
        regionPack: _FakeRegionPack(version: version),
      );

      final evaluation = await evaluator.evaluateOne(
        hexId: const HexId(999),
        buildingType: BuildingType.house,
      );

      expect(evaluation.canBuild, isFalse);
      expect(evaluation.denialReason, BuildDenialReason.notDisclosed);
    });

    test('開示済みの空き地・資材ありなら canBuild', () async {
      await inventoryRepository.add(Resource.wood, 10); // cropField は木10のみ

      final evaluator = BuildableHexEvaluator(
        database,
        regionPack: _FakeRegionPack(version: version),
      );

      final evaluation = await evaluator.evaluateOne(
        hexId: vacantHex,
        buildingType: BuildingType.cropField,
      );

      expect(evaluation.canBuild, isTrue);
    });
  });
}
