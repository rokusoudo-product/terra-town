import 'package:terra_town_core/terra_town_core.dart';
import 'package:test/test.dart';

/// 建設コスト・アップグレードコスト・資材差し引きのテスト（T079・Issue #191）。
void main() {
  group('buildingConstructionCostLv1（docs/buildings.md §4.1）', () {
    test('8種すべてに定義がある', () {
      expect(buildingConstructionCostLv1.length, BuildingType.values.length);
      for (final type in BuildingType.values) {
        expect(
          buildingConstructionCostLv1.containsKey(type),
          isTrue,
          reason: '$type の建設コストが定義されていない',
        );
      }
    });

    test('採石場は木のみを消費し、石・鉄は0（設計要件・Issue #72）', () {
      final cost = buildingConstructionCostLv1[BuildingType.quarry]!;
      expect(cost.wood, greaterThan(0));
      expect(cost.stone, 0);
      expect(cost.iron, 0);
    });
  });

  group('scaleBuildingCost（端数の扱い＝切り上げ）', () {
    test('割り切れる場合はそのまま倍率をかけた値になる', () {
      const cost = BuildingCost(wood: 20, stone: 10, iron: 0);
      final scaled = scaleBuildingCost(cost, 1.5);
      expect(scaled, const BuildingCost(wood: 30, stone: 15, iron: 0));
    });

    test('端数が出る場合は切り上げる（本Issueで決定した仕様）', () {
      // 11 * 1.5 = 16.5 -> 17、3 * 1.5 = 4.5 -> 5、1 * 1.5 = 1.5 -> 2。
      // balance.yaml の実際のLv.1建設コストは全て10の倍数で割り切れて
      // しまうため、丸め方針そのものは実際の建設コストから独立した
      // 合成値で検証する（build_cost_service.dart のコメント参照）。
      const cost = BuildingCost(wood: 11, stone: 3, iron: 1);
      final scaled = scaleBuildingCost(cost, 1.5);
      expect(scaled, const BuildingCost(wood: 17, stone: 5, iron: 2));
    });

    test('倍率2倍は常に整数のまま（切り上げの影響が出ない）', () {
      const cost = BuildingCost(wood: 11, stone: 3, iron: 1);
      final scaled = scaleBuildingCost(cost, 2);
      expect(scaled, const BuildingCost(wood: 22, stone: 6, iron: 2));
    });
  });

  group('buildingCostForLevel', () {
    test('Lv.1はbuildingConstructionCostLv1をそのまま返す', () {
      final cost = buildingCostForLevel(BuildingType.house, 1);
      expect(cost, buildingConstructionCostLv1[BuildingType.house]);
    });

    test('Lv.2は1.5倍（buildingUpgradeCostMultiplierLv2）', () {
      final cost = buildingCostForLevel(BuildingType.house, 2);
      // house Lv.1: wood20・stone10・iron0
      expect(cost, const BuildingCost(wood: 30, stone: 15, iron: 0));
    });

    test('Lv.3は2倍（buildingUpgradeCostMultiplierLv3）', () {
      final cost = buildingCostForLevel(BuildingType.house, 3);
      expect(cost, const BuildingCost(wood: 40, stone: 20, iron: 0));
    });

    test('1〜3以外のレベルは ArgumentError', () {
      expect(
        () => buildingCostForLevel(BuildingType.house, 4),
        throwsArgumentError,
      );
      expect(
        () => buildingCostForLevel(BuildingType.house, 0),
        throwsArgumentError,
      );
    });
  });

  group('missingResourcesFor', () {
    test('資材が足りていれば空のマップを返す', () {
      final inventory = _inventoryWith({Resource.wood: 20, Resource.stone: 10});
      final missing = missingResourcesFor(
        buildingConstructionCostLv1[BuildingType.house]!,
        inventory,
      );
      expect(missing, isEmpty);
    });

    test('ちょうど足りる場合も不足として扱わない', () {
      final inventory = _inventoryWith({
        Resource.wood: 40,
        Resource.stone: 30,
        Resource.iron: 20,
      });
      final missing = missingResourcesFor(
        buildingConstructionCostLv1[BuildingType.apartment]!,
        inventory,
      );
      expect(missing, isEmpty);
    });

    test('不足している資材とその不足量を返す', () {
      final inventory = _inventoryWith({
        Resource.wood: 40,
        Resource.stone: 25,
        Resource.iron: 0,
      });
      final missing = missingResourcesFor(
        buildingConstructionCostLv1[BuildingType.apartment]!,
        inventory,
      );
      expect(missing, {Resource.stone: 5, Resource.iron: 20});
    });

    test('コストが0の資材（採石場の石・鉄）は不足に含めない', () {
      final missing = missingResourcesFor(
        buildingConstructionCostLv1[BuildingType.quarry]!,
        Inventory(),
      );
      expect(missing, {Resource.wood: 20});
    });
  });

  group('deductBuildingCost', () {
    test('資材が足りていれば差し引いて成功する', () {
      final inventory = _inventoryWith({Resource.wood: 20, Resource.stone: 10});
      final result = deductBuildingCost(
        buildingConstructionCostLv1[BuildingType.house]!,
        inventory,
      );

      expect(result.success, isTrue);
      expect(result.missingResources, isEmpty);
      expect(inventory.amountOf(Resource.wood), 0);
      expect(inventory.amountOf(Resource.stone), 0);
    });

    test('差し引いた後も余りは残る', () {
      final inventory = _inventoryWith({Resource.wood: 25, Resource.stone: 12});
      deductBuildingCost(
        buildingConstructionCostLv1[BuildingType.house]!,
        inventory,
      );

      expect(inventory.amountOf(Resource.wood), 5);
      expect(inventory.amountOf(Resource.stone), 2);
    });

    test('1種でも不足していれば何も差し引かない（全部か無しか）', () {
      final inventory = _inventoryWith({
        Resource.wood: 40,
        Resource.stone: 30,
        Resource.iron: 5, // apartment は iron20 必要 -> 15不足
      });
      final result = deductBuildingCost(
        buildingConstructionCostLv1[BuildingType.apartment]!,
        inventory,
      );

      expect(result.success, isFalse);
      expect(result.missingResources, {Resource.iron: 15});
      // wood・stone は足りていたが、iron が不足しているため一切消費されない。
      expect(inventory.amountOf(Resource.wood), 40);
      expect(inventory.amountOf(Resource.stone), 30);
      expect(inventory.amountOf(Resource.iron), 5);
    });
  });
}

Inventory _inventoryWith(Map<Resource, int> amounts) {
  final inventory = Inventory();
  amounts.forEach(inventory.add);
  return inventory;
}
