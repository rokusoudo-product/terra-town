import 'package:flutter_test/flutter_test.dart';
import 'package:terra_town_core/terra_town_core.dart';
import 'package:terra_town_location/terra_town_location.dart';

void main() {
  late GameDatabase database;
  late BuildingRepository repository;

  setUp(() {
    database = GameDatabase.forTesting();
    repository = BuildingRepository(database);
  });

  tearDown(() async => database.close());

  group('BuildingRepository', () {
    test('findAll は建物が無ければ空リスト', () async {
      expect(await repository.findAll(), isEmpty);
    });

    test('findByHexId は建物が無ければ null', () async {
      expect(await repository.findByHexId(const HexId(1)), isNull);
    });

    test('insert すると findByHexId・findAll の両方に反映される', () async {
      final inserted = await repository.insert(
        hexId: const HexId(42),
        buildingType: BuildingType.house,
        districtId: const DistrictId('city-1'),
      );

      expect(inserted.hexId, 42);
      expect(inserted.buildingType, BuildingType.house);
      expect(inserted.level, 1, reason: '初期建築は常にLv.1');
      expect(inserted.constructionState, BuildingConstructionState.built);
      expect(inserted.districtId, 'city-1');

      final found = await repository.findByHexId(const HexId(42));
      expect(found, isNotNull);
      expect(found!.buildingType, BuildingType.house);

      final all = await repository.findAll();
      expect(all, hasLength(1));
    });

    test('districtId が null（パック範囲外）でも保存できる', () async {
      final inserted = await repository.insert(
        hexId: const HexId(7),
        buildingType: BuildingType.cropField,
        districtId: null,
      );
      expect(inserted.districtId, isNull);
    });

    test('同じヘクスへの2回目の insert は一意制約違反で例外（1マス1建物）', () async {
      await repository.insert(
        hexId: const HexId(1),
        buildingType: BuildingType.house,
        districtId: null,
      );

      await expectLater(
        repository.insert(
          hexId: const HexId(1),
          buildingType: BuildingType.cropField,
          districtId: null,
        ),
        throwsA(anything),
      );
    });
  });
}
