import 'package:flutter_test/flutter_test.dart';
import 'package:terra_town_core/terra_town_core.dart';
import 'package:terra_town_location/terra_town_location.dart';

/// [DisclosedHexRepository]（`core` の `Repository<DisclosedHex, HexId>` の
/// Drift 実装・tasks.md T060・Issue #96・Issue #137）のテスト。
void main() {
  group('DisclosedHexRepository（インメモリDB）', () {
    late GameDatabase database;
    late DisclosedHexRepository repository;

    setUp(() {
      database = GameDatabase.forTesting();
      repository = DisclosedHexRepository(database);
    });

    tearDown(() async {
      await database.close();
    });

    DisclosedHex sample({
      int hexId = 1,
      TerrainType terrainType = TerrainType.forest,
      String packVersion = 'v1',
    }) =>
        DisclosedHex(
          hexId: HexId(hexId),
          terrainType: terrainType,
          discoveredAtVersion: PackVersion(packVersion),
        );

    test('存在しないヘクスは findById が null', () async {
      expect(await repository.findById(const HexId(1)), isNull);
    });

    test('save したヘクスを findById で読み戻せる', () async {
      final disclosed = sample();
      await repository.save(disclosed);

      final found = await repository.findById(const HexId(1));
      expect(found, disclosed);
    });

    test('findAll は保存済みの全ヘクスを返す', () async {
      await repository.save(sample(hexId: 1, terrainType: TerrainType.forest));
      await repository.save(sample(hexId: 2, terrainType: TerrainType.sea));

      final all = await repository.findAll();
      expect(all, hasLength(2));
      expect(all.map((e) => e.hexId), containsAll([const HexId(1), const HexId(2)]));
    });

    test(
      '同一hexIdへの2回目のsaveは既存行を上書きしない（スナップショット不変性・Issue #96）',
      () async {
        await repository.save(
          sample(hexId: 1, terrainType: TerrainType.forest, packVersion: 'v1'),
        );
        // 2回目: 異なる地形・バージョンで保存を試みても、1回目の値が残ること。
        await repository.save(
          sample(hexId: 1, terrainType: TerrainType.sea, packVersion: 'v2'),
        );

        final found = await repository.findById(const HexId(1));
        expect(found!.terrainType, TerrainType.forest);
        expect(found.discoveredAtVersion, const PackVersion('v1'));
      },
    );

    test('delete したヘクスは findById で見つからなくなる', () async {
      await repository.save(sample());
      await repository.delete(const HexId(1));

      expect(await repository.findById(const HexId(1)), isNull);
    });

    test('全5種類のTerrainTypeを保存・復元できる', () async {
      for (final terrainType in TerrainType.values) {
        await repository.save(
          sample(hexId: terrainType.index + 1, terrainType: terrainType),
        );
      }

      final all = await repository.findAll();
      expect(
        all.map((e) => e.terrainType).toSet(),
        TerrainType.values.toSet(),
      );
    });
  });
}
