import 'package:terra_town_core/terra_town_core.dart';
import 'package:test/test.dart';

void main() {
  test('Resource は建設系3種・生活系5種の計8種と過不足なく一致する（spec.md §6）', () {
    expect(Resource.values, hasLength(8));

    final construction = Resource.values
        .where((r) => r.category == ResourceCategory.construction)
        .toSet();
    final living = Resource.values
        .where((r) => r.category == ResourceCategory.living)
        .toSet();

    expect(construction, {Resource.wood, Resource.stone, Resource.iron});
    expect(living, {
      Resource.salt,
      Resource.water,
      Resource.vegetable,
      Resource.fruit,
      Resource.meat, // Issue #5 で追加
    });
  });
}
