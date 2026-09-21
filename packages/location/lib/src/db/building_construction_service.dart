// ignore_for_file: prefer_initializing_formals
// 公開の名前付き引数（regionPack）をプライベートフィールド（_regionPack）へ
// そのまま代入する箇所があり、initializing formal（this._regionPack）にすると
// 外部呼び出し側の引数名がプライベート名になってしまうため使えない
// （`hex_opening_spend_service.dart`・`region_pack_repository.dart` と同じ判断）。

import 'package:terra_town_core/terra_town_core.dart';

import 'building_repository.dart';
import 'disclosed_hex_repository.dart';
import 'game_database.dart';
import 'inventory_repository.dart';

/// [BuildingConstructionService.build] の結果種別（Issue #192・T089）。
enum BuildOutcome {
  /// 建築に成功した（資材の消費・`building` への追加の両方がコミット済み）。
  built,

  /// トランザクション内で再確認した時点で建築できなかった（開示状態・地形・
  /// 既存の建物・隣接条件・所持資材のいずれかが原因。[BuildResult.denialReason]
  /// を参照）。呼び出し直前の判定（画面表示用のプレビュー）から確定までの間に、
  /// 別の経路（歩行・別の建設操作）で状況が変わった競合を含む。
  denied,
}

/// [BuildingConstructionService.build] の戻り値。
class BuildResult {
  const BuildResult._({
    required this.outcome,
    this.denialReason,
    this.missingResources = const {},
  });

  final BuildOutcome outcome;

  /// [outcome] が [BuildOutcome.denied] の場合のみ非null。
  final BuildDenialReason? denialReason;

  /// [denialReason] が [BuildDenialReason.insufficientResources] の場合のみ
  /// 非空。[evaluateBuild] の `missingResources` をそのまま返す。
  final Map<Resource, int> missingResources;
}

/// 資材を消費して建物を建てる、DBトランザクションを伴う実処理（Issue #192・T089）。
///
/// 出典: Issue #192 本文「建設を1トランザクションで行うサービス（例:
/// `BuildingConstructionService`）」。[HexOpeningSpendService]
/// （`hex_opening_spend_service.dart`）と同じ考え方——「画面を開いてから
/// 状況が変わっても不正に建たない」ことを保証するため、
/// [build] は呼び出し直前の判定（プレビュー用の `evaluateBuild`）に頼らず、
/// **トランザクションの中で改めて `evaluateBuild` を実行する**。
///
/// ## 資材の消費と `building` への追加は同一トランザクション（Issue #192 受け入れ基準）
/// [build] は [InventoryRepository.subtract]（資材の消費）と
/// [BuildingRepository.insert]（`building` への追加）を
/// [GameDatabase.transaction] 内で行う。どちらか一方だけが反映される状態は
/// 起こらない（`HexOpeningSpendService`・`TerrainYieldLedger` と同じ方針）。
class BuildingConstructionService {
  BuildingConstructionService(
    this._database, {
    DisclosedHexRepository? disclosedHexRepository,
    BuildingRepository? buildingRepository,
    InventoryRepository? inventoryRepository,
    required RegionPack regionPack,
  }) : _disclosedHexRepository =
           disclosedHexRepository ?? DisclosedHexRepository(_database),
       _buildingRepository =
           buildingRepository ?? BuildingRepository(_database),
       _inventoryRepository =
           inventoryRepository ?? InventoryRepository(_database),
       _regionPack = regionPack;

  final GameDatabase _database;
  final DisclosedHexRepository _disclosedHexRepository;
  final BuildingRepository _buildingRepository;
  final InventoryRepository _inventoryRepository;
  final RegionPack _regionPack;

  /// [hexId] に [buildingType] を建てる。
  ///
  /// 呼び出し側は事前に [BuildableHexEvaluator]（`buildable_hex_evaluator.dart`）
  /// で `canBuild: true` を確認していること。ここで渡す値はプレビューでしかなく、
  /// 実際の可否判定はトランザクション内で改めて行う（クラスdoc参照）。
  Future<BuildResult> build({
    required HexId hexId,
    required BuildingType buildingType,
  }) async {
    var outcome = BuildOutcome.denied;
    BuildDenialReason? denialReason;
    var missingResources = const <Resource, int>{};

    await _database.transaction(() async {
      // --- トランザクション内での再確認（Issue #192 受け入れ基準「判定は
      // トランザクション内で再確認される」）。プレビュー時点の値は一切使わず、
      // ここで改めて全て読み直す。---
      final disclosedHex = await _disclosedHexRepository.findById(hexId);
      final existingBuilding = await _buildingRepository.findByHexId(hexId);

      final neighborIds = _regionPack
          .neighborsOf(hexId)
          .toList(growable: false);
      final neighborTerrainTypes = <TerrainType>[];
      final neighborBuildingTypeByHex = <HexId, BuildingType>{};
      for (final neighborId in neighborIds) {
        // 隣接ヘクスの地形タイプ: 開示済みならスナップショット
        // （`disclosed_hex.terrainType`）、未開示なら `RegionPack.terrainOf`
        // （`buildable_hex_evaluator.dart` の `_HexSnapshots.terrainTypeOf` と
        // 同じルール。理由もそちらのコメント参照）。
        final neighborDisclosed = await _disclosedHexRepository.findById(
          neighborId,
        );
        final terrain =
            neighborDisclosed?.terrainType ?? _regionPack.terrainOf(neighborId);
        if (terrain != null) neighborTerrainTypes.add(terrain);

        final neighborBuilding = await _buildingRepository.findByHexId(
          neighborId,
        );
        if (neighborBuilding != null) {
          neighborBuildingTypeByHex[neighborId] = neighborBuilding.buildingType;
        }
      }

      final heldMap = await _inventoryRepository.readAll();
      final heldResources = Inventory();
      for (final entry in heldMap.entries) {
        heldResources.add(entry.key, entry.value);
      }

      final evaluation = evaluateBuild(
        buildingType: buildingType,
        isDisclosed: disclosedHex != null,
        // 未開示の場合は evaluateBuild が isDisclosed で最初に弾くため、値は
        // 判定結果に影響しない（`buildable_hex_evaluator.dart` と同じ
        // プレースホルダの考え方）。
        terrainType: disclosedHex?.terrainType ?? TerrainType.vacantLot,
        existingBuilding: existingBuilding?.buildingType,
        neighborTerrainTypes: neighborTerrainTypes,
        neighborBuildingTypes: neighborBuildingTypeByHex.values,
        heldResources: heldResources,
      );

      if (!evaluation.canBuild) {
        outcome = BuildOutcome.denied;
        denialReason = evaluation.denialReason;
        missingResources = evaluation.missingResources;
        return;
      }

      // --- 資材の消費と building への追加（同一トランザクション）。---
      final cost = buildingConstructionCostLv1[buildingType]!;
      for (final entry in cost.toResourceMap().entries) {
        if (entry.value > 0) {
          await _inventoryRepository.subtract(entry.key, entry.value);
        }
      }
      await _buildingRepository.insert(
        hexId: hexId,
        buildingType: buildingType,
        districtId: _regionPack.districtOf(hexId),
      );

      outcome = BuildOutcome.built;
    });

    return BuildResult._(
      outcome: outcome,
      denialReason: denialReason,
      missingResources: missingResources,
    );
  }
}
