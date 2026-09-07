import 'package:terra_town_core/terra_town_core.dart';
import 'package:test/test.dart';

void main() {
  test('TerrainType は docs/terrain.md §2 の7種と過不足なく一致する', () {
    expect(TerrainType.values, hasLength(7));
    expect(
      TerrainType.values.toSet(),
      {
        TerrainType.vacantLot, // 空き地
        TerrainType.forest, // 森
        TerrainType.mountain, // 山
        TerrainType.waterside, // 水辺（川・湖）
        TerrainType.sea, // 海
        TerrainType.farmland, // 農地
        TerrainType.urban, // 市街
      },
    );
  });
}
