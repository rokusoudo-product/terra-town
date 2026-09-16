import '../economy/inventory.dart';
import '../economy/resource.dart';
import '../terrain/terrain_type.dart';
import 'build_cost_service.dart';
import 'building_type.dart';

/// 住宅系建物（人口を持つ建物。buildings.md §2・§5.1）。
///
/// ミュージアムの隣接判定「プレイヤーが建設した住宅系建物（住宅・マンション）
/// に隣接する空き地」（buildings.md §2・Issue #70）で使う。
const Set<BuildingType> residentialBuildingTypes = {
  BuildingType.house,
  BuildingType.apartment,
};

/// [evaluateBuild] が建築を拒否した理由（T083）。
///
/// 出典: `docs/buildings.md` §2・§3。UI表示で使えるよう、拒否理由ごとに
/// 列挙値を分けている。
enum BuildDenialReason {
  /// 対象マスが未開示（buildings.md §3「開示済み...のマスのみ」）。
  notDisclosed,

  /// 対象マスの地形タイプが空き地ではない（buildings.md §3）。
  notVacantLot,

  /// 対象マスに既に建物がある（1マス1建物の原則。buildings.md §3）。
  alreadyBuilt,

  /// [BuildingType.resort] 限定: 隣接6マスのいずれの地形タイプも
  /// [TerrainType.sea] ではない（buildings.md §2）。
  notAdjacentToSea,

  /// [BuildingType.museum] 限定: 隣接6マスのいずれにも
  /// [residentialBuildingTypes]（住宅・マンション）が建っていない
  /// （buildings.md §2・Issue #70。地形タイプではなく隣接マスの建物を見る）。
  notAdjacentToResidential,

  /// Lv.1建設コスト（[buildingConstructionCostLv1]）に対して所持資材
  /// （[Inventory]）が不足している。
  insufficientResources,
}

/// [evaluateBuild] の戻り値。
///
/// `canBuild` と `denialReason` は排他的（`evaluateHexOpening` の
/// `HexOpeningEvaluation` と同じ設計）。`missingResources` は
/// [BuildDenialReason.insufficientResources] のときのみ非空になる。
class BuildEvaluation {
  BuildEvaluation._({
    required this.canBuild,
    this.denialReason,
    this.missingResources = const {},
  }) : assert(
         (canBuild && denialReason == null) ||
             (!canBuild && denialReason != null),
         'canBuild と denialReason は排他的であること',
       ),
       assert(
         (denialReason == BuildDenialReason.insufficientResources) ==
             missingResources.isNotEmpty,
         'missingResources は insufficientResources のときのみ非空であること',
       );

  /// このマスにいま建築できるか。
  final bool canBuild;

  /// 建築できない場合の理由（[canBuild] が true の場合は null）。
  final BuildDenialReason? denialReason;

  /// [denialReason] が [BuildDenialReason.insufficientResources] の場合のみ、
  /// 不足している資材とその不足量（コスト - 所持数）を保持する。それ以外は
  /// 空のマップ。
  final Map<Resource, int> missingResources;

  factory BuildEvaluation.allowed() => BuildEvaluation._(canBuild: true);

  factory BuildEvaluation.denied(
    BuildDenialReason reason, {
    Map<Resource, int> missingResources = const {},
  }) => BuildEvaluation._(
    canBuild: false,
    denialReason: reason,
    missingResources: missingResources,
  );

  @override
  String toString() =>
      'BuildEvaluation(canBuild: $canBuild, denialReason: $denialReason, '
      'missingResources: $missingResources)';
}

/// [buildingType] を対象マスに建築できるかを判定する決定論的な純粋関数
/// （T083）。
///
/// 出典: `docs/buildings.md` §2〜§3。
///
/// ## 入力について（`RegionPack`/`HexId` を直接受け取らない理由）
/// 本関数は地域パック（`RegionPack`）やヘクスID（`HexId`）を直接受け取らず、
/// 呼び出し側（`location/` 側。建設画面 T089 で実装予定）が対象マスと隣接
/// 6マスについてあらかじめ解決した値（開示済みか・地形タイプ・既存の建物・
/// 隣接マスの地形タイプ・隣接マスの建物種別・所持資材）を渡す設計にした
/// （Issue #191 本文の設計方針）。これにより `core` は地域パック・DBアクセス
/// の抽象を一切知らなくてよく、`evaluateHexOpening`（`opening_point_service.dart`）
/// と同じ「呼び出し側が値を解決し、本関数は判定のみ行う」分担になる。
///
/// [neighborTerrainTypes] は隣接ヘクス（0〜6件。パック範囲の縁では6件未満に
/// なりうる）の地形タイプ。[neighborBuildingTypes] は隣接ヘクスのうち
/// 建物が建っているものだけの建物種別（建物が無い隣接マスは含めない）。
///
/// ## 判定順序（複数の理由が同時に成り立つ場合、最初に検出したものを返す）
/// 1. [BuildDenialReason.notDisclosed]
/// 2. [BuildDenialReason.notVacantLot]
/// 3. [BuildDenialReason.alreadyBuilt]
/// 4. [BuildingType.resort] のみ: [BuildDenialReason.notAdjacentToSea]
/// 5. [BuildingType.museum] のみ: [BuildDenialReason.notAdjacentToResidential]
/// 6. [BuildDenialReason.insufficientResources]
///
/// この順序は `evaluateHexOpening` と同じ考え方で、UI表示のためだけの
/// 決め事であり、拒否理由が単一である限り結果に影響しない。
///
/// ## 採石場（[BuildingType.quarry]）に隣接制約は無い
/// 採石場は空き地であれば山の有無にかかわらず建築できる（`docs/buildings.md`
/// §2・§6.3・2026-09-09代表決定・Issue #72）。山への隣接は将来実装される
/// 産出倍率（T086）にのみ影響し、本関数の可否判定には一切影響しない
/// （本関数は建築可否のみを扱い、産出は対象外）。
BuildEvaluation evaluateBuild({
  required BuildingType buildingType,
  required bool isDisclosed,
  required TerrainType terrainType,
  required BuildingType? existingBuilding,
  required Iterable<TerrainType> neighborTerrainTypes,
  required Iterable<BuildingType> neighborBuildingTypes,
  required Inventory heldResources,
}) {
  if (!isDisclosed) {
    return BuildEvaluation.denied(BuildDenialReason.notDisclosed);
  }

  if (terrainType != TerrainType.vacantLot) {
    return BuildEvaluation.denied(BuildDenialReason.notVacantLot);
  }

  if (existingBuilding != null) {
    return BuildEvaluation.denied(BuildDenialReason.alreadyBuilt);
  }

  if (buildingType == BuildingType.resort &&
      !neighborTerrainTypes.contains(TerrainType.sea)) {
    return BuildEvaluation.denied(BuildDenialReason.notAdjacentToSea);
  }

  if (buildingType == BuildingType.museum &&
      !neighborBuildingTypes.any(residentialBuildingTypes.contains)) {
    return BuildEvaluation.denied(BuildDenialReason.notAdjacentToResidential);
  }

  final cost = buildingConstructionCostLv1[buildingType]!;
  final missing = missingResourcesFor(cost, heldResources);
  if (missing.isNotEmpty) {
    return BuildEvaluation.denied(
      BuildDenialReason.insufficientResources,
      missingResources: missing,
    );
  }

  return BuildEvaluation.allowed();
}
