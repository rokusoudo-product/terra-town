import '../economy/inventory.dart';
import '../economy/resource.dart';
import 'building_type.dart';

/// 建物の建設・アップグレードコスト（木・石・鉄。docs/buildings.md §4）。
///
/// 全建物、建設系資材（木・石・鉄）のみを消費する（生活系資材は使わない。
/// buildings.md §4.1）。
class BuildingCost {
  const BuildingCost({
    required this.wood,
    required this.stone,
    required this.iron,
  });

  final int wood;
  final int stone;
  final int iron;

  /// [Resource.wood]・[Resource.stone]・[Resource.iron] へのマッピング。
  /// 値が0の資材もキーを含める（[missingResourcesFor] 等の走査を単純にする
  /// ため。0個の消費は [Inventory.consume] にとって無害な no-op）。
  Map<Resource, int> toResourceMap() => {
    Resource.wood: wood,
    Resource.stone: stone,
    Resource.iron: iron,
  };

  @override
  bool operator ==(Object other) =>
      other is BuildingCost &&
      other.wood == wood &&
      other.stone == stone &&
      other.iron == iron;

  @override
  int get hashCode => Object.hash(wood, stone, iron);

  @override
  String toString() => 'BuildingCost(wood: $wood, stone: $stone, iron: $iron)';
}

/// 建物ごとの初期建設コスト（Lv.1・木/石/鉄。T084）。
///
/// 出典・正本: `specs/001-mvp/balance.yaml`（`buildings.construction_cost`）。
/// 照合テスト（`packages/core/test/balance/balance_yaml_test.dart`）で
/// balance.yaml の値との一致を確認している。
///
/// **採石場（[BuildingType.quarry]）の石0・鉄0は仮値ではなく設計要件**
/// （2026-09-09代表決定・Issue #72。`docs/buildings.md` §4.1・§6.3）。
/// 採石場は石・鉄の主供給源であり、建設コストに石・鉄を含めると
/// 「石・鉄を手に入れるために石・鉄が要る」という鶏卵問題が再発するため。
/// 木の量（20）のみが balance 調整の対象で、石0・鉄0という構成自体は
/// balance 調整の対象外。
const Map<BuildingType, BuildingCost> buildingConstructionCostLv1 = {
  BuildingType.house: BuildingCost(wood: 20, stone: 10, iron: 0),
  BuildingType.apartment: BuildingCost(wood: 40, stone: 30, iron: 20),
  BuildingType.cropField: BuildingCost(wood: 10, stone: 0, iron: 0),
  BuildingType.livestockFarm: BuildingCost(wood: 20, stone: 10, iron: 0),
  BuildingType.factoryBuilding: BuildingCost(wood: 20, stone: 30, iron: 30),
  BuildingType.quarry: BuildingCost(wood: 20, stone: 0, iron: 0),
  BuildingType.resort: BuildingCost(wood: 30, stone: 20, iron: 10),
  BuildingType.museum: BuildingCost(wood: 30, stone: 30, iron: 20),
};

/// Lv.2アップグレードのコスト倍率（Lv.1建設コストに対する倍率。
/// docs/buildings.md §4.2）。
///
/// 正本は `specs/001-mvp/balance.yaml`（`buildings.upgrade.cost_multiplier.lv2`）。
const double buildingUpgradeCostMultiplierLv2 = 1.5;

/// Lv.3アップグレードのコスト倍率。
///
/// 正本は `specs/001-mvp/balance.yaml`（`buildings.upgrade.cost_multiplier.lv3`）。
const double buildingUpgradeCostMultiplierLv3 = 2.0;

/// アップグレード後のレベル（2・3）から段階倍率を引くマップ。
/// Lv.1はそもそも倍率を掛けない（[buildingConstructionCostLv1] がそのまま
/// Lv.1のコスト）ため、このマップにレベル1は含めない。
const Map<int, double> buildingUpgradeCostMultiplier = {
  2: buildingUpgradeCostMultiplierLv2,
  3: buildingUpgradeCostMultiplierLv3,
};

/// [cost] の各資材量に [multiplier] を掛け、端数を**切り上げ**（`ceil`）た
/// [BuildingCost] を返す（T084）。
///
/// ## 端数の扱いについて（2026-09-16・本Issue #191で決定）
/// `docs/buildings.md` §4.2・`specs/001-mvp/balance.yaml`（`buildings.upgrade`）
/// のいずれにも、倍率を掛けた結果が整数にならない場合の端数の扱いは明記されて
/// いなかった。実装にあたり**切り上げ**を採用し、本関数のテスト
/// （`packages/core/test/building/build_cost_test.dart`）で固定する。
/// 「アップグレードに必要な資材が足りているのに切り捨てにより1個過剰に安く
/// なる」事故を避けるため、プレイヤーに不利にならない側（切り捨て）ではなく
/// 供給側に有利な側＝切り上げを選んだ（他の丸め方針を否定するものではなく、
/// 明記が無かったため実装時に決定した値である。balance調整で明示的な方針が
/// 決まった場合は本関数とこのコメントを更新すること）。
/// 木・石・鉄はそれぞれ独立に切り上げる（合計してから切り上げるのではない）。
///
/// 現在の `balance.yaml` の実際の値（[buildingConstructionCostLv1] は全て10の
/// 倍数、倍率は1.5倍・2倍）では端数は発生しない（`10 * 1.5 = 15` のように
/// 常に整数になる）ため、切り上げの効果は将来 balance 調整で端数が出る値に
/// 変更された場合に初めて現れる。そのためテストは本関数を balance.yaml の
/// 実際の値から独立させ、端数が出る合成値で直接検証する。
BuildingCost scaleBuildingCost(BuildingCost cost, double multiplier) {
  return BuildingCost(
    wood: (cost.wood * multiplier).ceil(),
    stone: (cost.stone * multiplier).ceil(),
    iron: (cost.iron * multiplier).ceil(),
  );
}

/// [buildingType] の [level]（1〜3）時点の建設・アップグレードコストを返す
/// （T084）。
///
/// Lv.1は [buildingConstructionCostLv1] をそのまま返す。Lv.2・Lv.3は
/// Lv.1のコストに [buildingUpgradeCostMultiplier] を [scaleBuildingCost] で
/// 適用した値（端数は切り上げ）を返す。
///
/// [level] が1〜3以外の場合は [ArgumentError]。
///
/// **本関数はコストの計算のみを行う。** アップグレードの画面・保存は
/// 本Issue（#191）のスコープ外（次の建設画面Issueで扱う）。
BuildingCost buildingCostForLevel(BuildingType buildingType, int level) {
  final lv1 = buildingConstructionCostLv1[buildingType];
  if (lv1 == null) {
    throw ArgumentError.value(
      buildingType,
      'buildingType',
      '建設コストが定義されていない建物種別',
    );
  }
  if (level == 1) {
    return lv1;
  }
  final multiplier = buildingUpgradeCostMultiplier[level];
  if (multiplier == null) {
    throw ArgumentError.value(level, 'level', 'アップグレード段階は1〜3のみ対応');
  }
  return scaleBuildingCost(lv1, multiplier);
}

/// [cost] に対して [heldResources] が不足している資材と不足量（`cost - held`）
/// を返す（T083・T084共用）。不足がなければ空のマップ。
///
/// 「ちょうど足りる」場合（所持数 == コスト）は不足扱いにしない
/// （`held < amount` のときのみ不足として計上する）。
Map<Resource, int> missingResourcesFor(
  BuildingCost cost,
  Inventory heldResources,
) {
  final missing = <Resource, int>{};
  cost.toResourceMap().forEach((resource, amount) {
    if (amount <= 0) {
      return;
    }
    final held = heldResources.amountOf(resource);
    if (held < amount) {
      missing[resource] = amount - held;
    }
  });
  return missing;
}

/// [deductBuildingCost] の結果。
class BuildResourceDeduction {
  const BuildResourceDeduction._({
    required this.success,
    required this.missingResources,
  });

  /// 差し引きに成功したか。
  final bool success;

  /// [success] が false のときのみ、不足している資材と不足量
  /// （[missingResourcesFor] と同じ形式）を保持する。[success] が true の
  /// ときは空。
  final Map<Resource, int> missingResources;

  @override
  String toString() =>
      'BuildResourceDeduction(success: $success, missingResources: $missingResources)';
}

/// [cost] を [heldResources] から一括で差し引く（T084）。
///
/// **全資材が足りている場合のみ差し引き、1種でも不足していれば何も
/// 差し引かない**（部分的な消費は行わない）。[Inventory.consume] を資材
/// ごとに素朴に呼ぶと、先に消費した資材だけ引かれた状態で後続の資材の
/// 不足が判明する事故が起きうるため、本関数はまず [missingResourcesFor] で
/// 全資材の充足を確認してから差し引く。
BuildResourceDeduction deductBuildingCost(
  BuildingCost cost,
  Inventory heldResources,
) {
  final missing = missingResourcesFor(cost, heldResources);
  if (missing.isNotEmpty) {
    return BuildResourceDeduction._(success: false, missingResources: missing);
  }
  cost.toResourceMap().forEach((resource, amount) {
    if (amount > 0) {
      heldResources.consume(resource, amount);
    }
  });
  return const BuildResourceDeduction._(success: true, missingResources: {});
}
