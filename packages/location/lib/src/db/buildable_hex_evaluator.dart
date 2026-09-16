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

/// [BuildableHexEvaluator.evaluateAll]/[evaluateOne] が使う、開示済み全ヘクスの
/// 地形タイプ・既存建物のスナップショット（Issue #192）。
///
/// [BuildableHexEvaluator] の2つのメソッド（全件評価・単体評価）で同じ
/// 「地形タイプは `disclosed_hex` のスナップショットから読み、隣接ヘクスの
/// 地形タイプは開示済みならスナップショット・未開示なら `RegionPack.terrainOf`
/// から読む」というルールを重複させないための内部ヘルパー。
class _HexSnapshots {
  _HexSnapshots({
    required this.terrainTypeByHex,
    required this.buildingTypeByHex,
  });

  final Map<HexId, TerrainType> terrainTypeByHex;
  final Map<HexId, BuildingType> buildingTypeByHex;

  /// [hexId] の地形タイプ。開示済み（[terrainTypeByHex] にある）ならその
  /// スナップショットを、そうでなければ [regionPack.terrainOf] を使う。
  ///
  /// 【`RegionPack.terrainOf` を未開示ヘクスに呼ぶことについて】
  /// `region_pack.dart` の `terrainOf` ドキュメント「呼んでよいタイミング」は
  /// 「既に開示済みのヘクスの地形分類を再解決するために呼んではならない」と
  /// 定めているが、これは disclosed_hex のスナップショットが不変性の正となる
  /// **開示済み**ヘクスに対する制約である。**未開示**ヘクスにはそもそも
  /// スナップショットが存在せず、`evaluateHexOpening`（`opening_point_service.dart`）
  /// も同様に未開示ヘクスの地形判定に `RegionPack.terrainOf` を使っており、
  /// 本メソッドはその前例に倣う。
  TerrainType? terrainTypeOf(HexId hexId, RegionPack regionPack) {
    return terrainTypeByHex[hexId] ?? regionPack.terrainOf(hexId);
  }
}

/// 建設先の候補ヘクスを判定する（Issue #192・T089）。
///
/// `core` の `evaluateBuild`（純粋関数）に、`location` が持つ状態
/// （開示済みヘクス・既存の建物・所持資材・地域パック）を解決して渡す
/// 「呼び出し側が値を解決し、`core` は判定のみ行う」という役割分担
/// （`evaluateBuild` クラスdoc「本関数は地域パック・HexIdを直接受け取らない理由」
/// 参照）。[HexOpeningSpendService] が `evaluateHexOpening` に対して担うのと
/// 同じ立ち位置。
///
/// ## 2つの用途（Issue #192 本文）
/// - [evaluateAll]: 建設タブで建物を選んだ直後、地図上で「建てられるマス」を
///   ハイライトするために、開示済み全ヘクスをまとめて評価する。
/// - [evaluateOne]: 地図をタップした1マスについて、確認シート表示・拒否理由の
///   提示のために評価する（未開示ヘクスも含めて呼べる。[evaluateAll] は
///   開示済みヘクスしか含まないため、未開示ヘクスのタップは
///   [BuildDenialReason.notDisclosed] を返す必要があり、[evaluateAll] の結果
///   マップには含まれない。呼び出し側は [evaluateOne] で個別に判定すること）。
///
/// ## DBアクセスの回数を絞る（性能）
/// [evaluateAll] は開示済みヘクス数に対して1回ずつ `evaluateBuild`（純粋関数・
/// 高速）を呼ぶが、DBへの問い合わせは「開示済みヘクス全件」「建物全件」
/// 「所持資材全件」の3回にまとめている。隣接ヘクスごとの個別クエリは行わない
/// （`_HexSnapshots`・[buildingTypeByHex] はメモリ上のマップとして1回だけ構築する）。
class BuildableHexEvaluator {
  BuildableHexEvaluator(
    GameDatabase database, {
    DisclosedHexRepository? disclosedHexRepository,
    BuildingRepository? buildingRepository,
    InventoryRepository? inventoryRepository,
    required RegionPack regionPack,
  }) : _disclosedHexRepository =
           disclosedHexRepository ?? DisclosedHexRepository(database),
       _buildingRepository = buildingRepository ?? BuildingRepository(database),
       _inventoryRepository =
           inventoryRepository ?? InventoryRepository(database),
       _regionPack = regionPack;

  final DisclosedHexRepository _disclosedHexRepository;
  final BuildingRepository _buildingRepository;
  final InventoryRepository _inventoryRepository;
  final RegionPack _regionPack;

  /// 開示済み全ヘクスについて、[buildingType] を建てられるかを判定する。
  ///
  /// 戻り値は開示済みヘクスの [HexId] → [BuildEvaluation] の全件（開示済み
  /// ヘクスのみ。未開示ヘクスは含まない。クラスdoc参照）。呼び出し側
  /// （`app`）は `canBuild == true` のものだけを地図のハイライト対象にする。
  Future<Map<HexId, BuildEvaluation>> evaluateAll({
    required BuildingType buildingType,
  }) async {
    final snapshots = await _loadSnapshots();
    final heldResources = await _loadInventory();

    final result = <HexId, BuildEvaluation>{};
    for (final hexId in snapshots.terrainTypeByHex.keys) {
      result[hexId] = _evaluate(
        hexId: hexId,
        buildingType: buildingType,
        isDisclosed: true,
        snapshots: snapshots,
        heldResources: heldResources,
      );
    }
    return result;
  }

  /// [hexId] 1マスについて、[buildingType] を建てられるかを判定する
  /// （地図タップ時のプレビュー用。クラスdoc参照）。
  Future<BuildEvaluation> evaluateOne({
    required HexId hexId,
    required BuildingType buildingType,
  }) async {
    final snapshots = await _loadSnapshots();
    final heldResources = await _loadInventory();
    final isDisclosed = snapshots.terrainTypeByHex.containsKey(hexId);

    return _evaluate(
      hexId: hexId,
      buildingType: buildingType,
      isDisclosed: isDisclosed,
      snapshots: snapshots,
      heldResources: heldResources,
    );
  }

  BuildEvaluation _evaluate({
    required HexId hexId,
    required BuildingType buildingType,
    required bool isDisclosed,
    required _HexSnapshots snapshots,
    required Inventory heldResources,
  }) {
    // 未開示ヘクスは `evaluateBuild` が isDisclosed で最初に弾くため、
    // terrainType の値そのものは判定結果に影響しない（プレースホルダとして
    // vacantLot を渡す。`region_pack.dart` の「呼んでよいタイミング」制約に
    // 触れないよう、未開示ヘクスに対して `RegionPack.terrainOf` を判定目的で
    // 呼ぶことを避けるための意図的な選択）。
    final terrainType = isDisclosed
        ? snapshots.terrainTypeByHex[hexId]!
        : TerrainType.vacantLot;

    final neighborIds = _regionPack.neighborsOf(hexId);
    final neighborTerrainTypes = <TerrainType>[];
    final neighborBuildingTypes = <BuildingType>[];
    for (final neighborId in neighborIds) {
      final terrain = snapshots.terrainTypeOf(neighborId, _regionPack);
      if (terrain != null) neighborTerrainTypes.add(terrain);
      final building = snapshots.buildingTypeByHex[neighborId];
      if (building != null) neighborBuildingTypes.add(building);
    }

    return evaluateBuild(
      buildingType: buildingType,
      isDisclosed: isDisclosed,
      terrainType: terrainType,
      existingBuilding: snapshots.buildingTypeByHex[hexId],
      neighborTerrainTypes: neighborTerrainTypes,
      neighborBuildingTypes: neighborBuildingTypes,
      heldResources: heldResources,
    );
  }

  Future<_HexSnapshots> _loadSnapshots() async {
    final disclosedHexes = await _disclosedHexRepository.findAll();
    final buildings = await _buildingRepository.findAll();
    return _HexSnapshots(
      terrainTypeByHex: {
        for (final hex in disclosedHexes) hex.hexId: hex.terrainType,
      },
      buildingTypeByHex: {
        for (final building in buildings)
          HexId(building.hexId): building.buildingType,
      },
    );
  }

  Future<Inventory> _loadInventory() async {
    final heldMap = await _inventoryRepository.readAll();
    final inventory = Inventory();
    for (final entry in heldMap.entries) {
      inventory.add(entry.key, entry.value);
    }
    return inventory;
  }
}
