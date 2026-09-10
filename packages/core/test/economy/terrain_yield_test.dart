import 'package:terra_town_core/terra_town_core.dart';
import 'package:test/test.dart';

void main() {
  group('terrainYieldOf', () {
    // docs/terrain.md §2「地形タイプ一覧」の産出資材列と一致させること
    // （Issue #82 受け入れ基準）。
    final expectedYieldByTerrain = <TerrainType, Set<Resource>>{
      TerrainType.vacantLot: <Resource>{},
      TerrainType.forest: {Resource.wood},
      TerrainType.mountain: {Resource.stone, Resource.iron},
      TerrainType.waterside: {Resource.water},
      TerrainType.sea: {Resource.salt},
    };

    for (final entry in expectedYieldByTerrain.entries) {
      test(
        '${entry.key} → ${entry.value.isEmpty ? "産出なし" : entry.value}（docs/terrain.md §2）',
        () {
          expect(terrainYieldOf(entry.key), entry.value);
        },
      );
    }

    test('5種の地形すべてを網羅する（docs/terrain.md §2 と過不足なく一致）', () {
      expect(expectedYieldByTerrain.keys.toSet(), TerrainType.values.toSet());
    });

    test('空き地は産出なし（terrain.md §2）', () {
      expect(terrainYieldOf(TerrainType.vacantLot), isEmpty);
    });

    test('野菜・フルーツ・肉はどの地形からも産出されない（建物産出専用・docs/buildings.md §6.1）', () {
      const buildingOnlyResources = {
        Resource.vegetable,
        Resource.fruit,
        Resource.meat,
      };

      for (final terrainType in TerrainType.values) {
        expect(
          terrainYieldOf(terrainType).intersection(buildingOnlyResources),
          isEmpty,
          reason: '$terrainType の産出に建物産出専用の資材が含まれてはならない',
        );
      }
    });

    test('山の産出は石・鉄の地形産出（受動）のみを表し、採石場（建物・能動、Issue #72・T082〜T086）'
        'の産出量・倍率はここに含まれない', () {
      expect(terrainYieldOf(TerrainType.mountain), {
        Resource.stone,
        Resource.iron,
      });
    });
  });
}
