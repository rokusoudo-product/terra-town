import 'package:terra_town_core/terra_town_core.dart';
import 'package:test/test.dart';

void main() {
  test('TerrainType は docs/terrain.md §2 の5種と過不足なく一致する（Issue #70で農地・市街を除外）', () {
    expect(TerrainType.values, hasLength(5));
    expect(
      TerrainType.values.toSet(),
      {
        TerrainType.vacantLot, // 空き地
        TerrainType.forest, // 森
        TerrainType.mountain, // 山
        TerrainType.waterside, // 水辺（川・湖）
        TerrainType.sea, // 海
      },
    );
  });
}
