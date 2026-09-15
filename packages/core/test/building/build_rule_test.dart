import 'package:terra_town_core/terra_town_core.dart';
import 'package:test/test.dart';

/// [evaluateBuild] のテスト（T079・Issue #191）。
///
/// 出典: `docs/buildings.md` §2〜§3。Issue #191本文「テスト（T079）」の
/// 一覧（空き地のみ・未開示は不可・1マス1建物・リゾートの海隣接・
/// ミュージアムの住宅系隣接〔地形ではなく建物を見る〕・採石場は山が無くても可・
/// 資材不足の理由と不足量・ちょうど足りる場合）に対応する。
void main() {
  group('evaluateBuild - 基本の配置ルール', () {
    test('開示済み・空き地・資材十分なら建築できる', () {
      final result = evaluateBuild(
        buildingType: BuildingType.house,
        isDisclosed: true,
        terrainType: TerrainType.vacantLot,
        existingBuilding: null,
        neighborTerrainTypes: const [],
        neighborBuildingTypes: const [],
        heldResources: _inventoryWith({Resource.wood: 20, Resource.stone: 10}),
      );

      expect(result.canBuild, isTrue);
      expect(result.denialReason, isNull);
      expect(result.missingResources, isEmpty);
    });

    test('未開示のマスには建築できない（notDisclosed）', () {
      final result = evaluateBuild(
        buildingType: BuildingType.house,
        isDisclosed: false,
        terrainType: TerrainType.vacantLot,
        existingBuilding: null,
        neighborTerrainTypes: const [],
        neighborBuildingTypes: const [],
        heldResources: _richInventory(),
      );

      expect(result.canBuild, isFalse);
      expect(result.denialReason, BuildDenialReason.notDisclosed);
    });

    test('空き地以外の地形には建築できない（notVacantLot）', () {
      final result = evaluateBuild(
        buildingType: BuildingType.house,
        isDisclosed: true,
        terrainType: TerrainType.forest,
        existingBuilding: null,
        neighborTerrainTypes: const [],
        neighborBuildingTypes: const [],
        heldResources: _richInventory(),
      );

      expect(result.canBuild, isFalse);
      expect(result.denialReason, BuildDenialReason.notVacantLot);
    });

    test('既に建物があるマスには重ねて建築できない（1マス1建物・alreadyBuilt）', () {
      final result = evaluateBuild(
        buildingType: BuildingType.house,
        isDisclosed: true,
        terrainType: TerrainType.vacantLot,
        existingBuilding: BuildingType.cropField,
        neighborTerrainTypes: const [],
        neighborBuildingTypes: const [],
        heldResources: _richInventory(),
      );

      expect(result.canBuild, isFalse);
      expect(result.denialReason, BuildDenialReason.alreadyBuilt);
    });

    test('判定順序: 未開示は空き地でなくても notDisclosed を優先する', () {
      final result = evaluateBuild(
        buildingType: BuildingType.house,
        isDisclosed: false,
        terrainType: TerrainType.forest,
        existingBuilding: BuildingType.cropField,
        neighborTerrainTypes: const [],
        neighborBuildingTypes: const [],
        heldResources: _richInventory(),
      );

      expect(result.denialReason, BuildDenialReason.notDisclosed);
    });
  });

  group('evaluateBuild - リゾート（海隣接）', () {
    test('隣接6マスのいずれかが海なら建築できる', () {
      final result = evaluateBuild(
        buildingType: BuildingType.resort,
        isDisclosed: true,
        terrainType: TerrainType.vacantLot,
        existingBuilding: null,
        neighborTerrainTypes: const [
          TerrainType.forest,
          TerrainType.sea,
          TerrainType.mountain,
        ],
        neighborBuildingTypes: const [],
        heldResources: _richInventory(),
      );

      expect(result.canBuild, isTrue);
    });

    test('隣接に海が無ければ建築できない（notAdjacentToSea）', () {
      final result = evaluateBuild(
        buildingType: BuildingType.resort,
        isDisclosed: true,
        terrainType: TerrainType.vacantLot,
        existingBuilding: null,
        neighborTerrainTypes: const [TerrainType.forest, TerrainType.waterside],
        neighborBuildingTypes: const [],
        heldResources: _richInventory(),
      );

      expect(result.canBuild, isFalse);
      expect(result.denialReason, BuildDenialReason.notAdjacentToSea);
    });

    test('隣接マスが1つも無い（パック範囲の縁）場合も notAdjacentToSea', () {
      final result = evaluateBuild(
        buildingType: BuildingType.resort,
        isDisclosed: true,
        terrainType: TerrainType.vacantLot,
        existingBuilding: null,
        neighborTerrainTypes: const [],
        neighborBuildingTypes: const [],
        heldResources: _richInventory(),
      );

      expect(result.denialReason, BuildDenialReason.notAdjacentToSea);
    });
  });

  group('evaluateBuild - ミュージアム（住宅系建物への隣接・地形は見ない）', () {
    test('隣接6マスのいずれかに住宅があれば建築できる', () {
      final result = evaluateBuild(
        buildingType: BuildingType.museum,
        isDisclosed: true,
        terrainType: TerrainType.vacantLot,
        existingBuilding: null,
        // 地形は海（本来リゾート向け）だが、ミュージアムの判定には無関係。
        neighborTerrainTypes: const [TerrainType.sea],
        neighborBuildingTypes: const [BuildingType.house],
        heldResources: _richInventory(),
      );

      expect(result.canBuild, isTrue);
    });

    test('隣接6マスのいずれかにマンションがあれば建築できる', () {
      final result = evaluateBuild(
        buildingType: BuildingType.museum,
        isDisclosed: true,
        terrainType: TerrainType.vacantLot,
        existingBuilding: null,
        neighborTerrainTypes: const [],
        neighborBuildingTypes: const [BuildingType.apartment],
        heldResources: _richInventory(),
      );

      expect(result.canBuild, isTrue);
    });

    test('隣接に住宅系建物が無ければ建築できない（notAdjacentToResidential）', () {
      final result = evaluateBuild(
        buildingType: BuildingType.museum,
        isDisclosed: true,
        terrainType: TerrainType.vacantLot,
        existingBuilding: null,
        neighborTerrainTypes: const [],
        neighborBuildingTypes: const [],
        heldResources: _richInventory(),
      );

      expect(result.canBuild, isFalse);
      expect(result.denialReason, BuildDenialReason.notAdjacentToResidential);
    });

    test('隣接に住宅系以外の建物（畑）しかない場合は建築できない', () {
      final result = evaluateBuild(
        buildingType: BuildingType.museum,
        isDisclosed: true,
        terrainType: TerrainType.vacantLot,
        existingBuilding: null,
        neighborTerrainTypes: const [],
        neighborBuildingTypes: const [BuildingType.cropField],
        heldResources: _richInventory(),
      );

      expect(result.canBuild, isFalse);
      expect(result.denialReason, BuildDenialReason.notAdjacentToResidential);
    });

    test('隣接マスの地形が住宅系「っぽく」ても（判定対象外）、建物が無ければ建築できない', () {
      // ミュージアムは「地形」ではなく「隣接マスの建物」を見る、という
      // Issue #191本文の要求を裏返しで確認する。
      final result = evaluateBuild(
        buildingType: BuildingType.museum,
        isDisclosed: true,
        terrainType: TerrainType.vacantLot,
        existingBuilding: null,
        neighborTerrainTypes: const [TerrainType.vacantLot],
        neighborBuildingTypes: const [],
        heldResources: _richInventory(),
      );

      expect(result.denialReason, BuildDenialReason.notAdjacentToResidential);
    });
  });

  group('evaluateBuild - 採石場（山への隣接は不要）', () {
    test('隣接に山が無くても、空き地であれば建築できる', () {
      final result = evaluateBuild(
        buildingType: BuildingType.quarry,
        isDisclosed: true,
        terrainType: TerrainType.vacantLot,
        existingBuilding: null,
        neighborTerrainTypes: const [TerrainType.forest, TerrainType.sea],
        neighborBuildingTypes: const [],
        heldResources: _inventoryWith({Resource.wood: 20}),
      );

      expect(result.canBuild, isTrue);
    });

    test('隣接に山があっても可否には影響しない（産出倍率のみ・T086の範囲）', () {
      final result = evaluateBuild(
        buildingType: BuildingType.quarry,
        isDisclosed: true,
        terrainType: TerrainType.vacantLot,
        existingBuilding: null,
        neighborTerrainTypes: const [TerrainType.mountain],
        neighborBuildingTypes: const [],
        heldResources: _inventoryWith({Resource.wood: 20}),
      );

      expect(result.canBuild, isTrue);
    });
  });

  group('evaluateBuild - 資材不足（insufficientResources）', () {
    test('資材が1種でも不足していれば insufficientResources を理由とする', () {
      final result = evaluateBuild(
        buildingType: BuildingType.house,
        isDisclosed: true,
        terrainType: TerrainType.vacantLot,
        existingBuilding: null,
        neighborTerrainTypes: const [],
        neighborBuildingTypes: const [],
        // house は wood20・stone10・iron0。木を12個だけ所持（8個不足）。
        heldResources: _inventoryWith({Resource.wood: 12, Resource.stone: 10}),
      );

      expect(result.canBuild, isFalse);
      expect(result.denialReason, BuildDenialReason.insufficientResources);
      expect(result.missingResources, {Resource.wood: 8});
    });

    test('複数資材が不足している場合、それぞれの不足量を返す', () {
      final result = evaluateBuild(
        buildingType: BuildingType.apartment,
        isDisclosed: true,
        terrainType: TerrainType.vacantLot,
        existingBuilding: null,
        neighborTerrainTypes: const [],
        neighborBuildingTypes: const [],
        // apartment は wood40・stone30・iron20。何も所持していない。
        heldResources: _inventoryWith(const {}),
      );

      expect(result.canBuild, isFalse);
      expect(result.denialReason, BuildDenialReason.insufficientResources);
      expect(result.missingResources, {
        Resource.wood: 40,
        Resource.stone: 30,
        Resource.iron: 20,
      });
    });

    test('ちょうど足りる場合は資材不足として扱わず建築できる', () {
      final result = evaluateBuild(
        buildingType: BuildingType.house,
        isDisclosed: true,
        terrainType: TerrainType.vacantLot,
        existingBuilding: null,
        neighborTerrainTypes: const [],
        neighborBuildingTypes: const [],
        // house の必要量ちょうど（wood20・stone10・iron0）。
        heldResources: _inventoryWith({Resource.wood: 20, Resource.stone: 10}),
      );

      expect(result.canBuild, isTrue);
      expect(result.missingResources, isEmpty);
    });
  });
}

Inventory _inventoryWith(Map<Resource, int> amounts) {
  final inventory = Inventory();
  amounts.forEach(inventory.add);
  return inventory;
}

/// 資材不足を理由にしたくないテストのための、潤沢な所持資材。
Inventory _richInventory() => _inventoryWith({
  Resource.wood: 9999,
  Resource.stone: 9999,
  Resource.iron: 9999,
});
