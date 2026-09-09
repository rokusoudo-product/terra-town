/// 行政区画（市区町村相当）の識別子（T024）。
///
/// 出典: `specs/001-mvp/plan.md` §3.2「行政区域ポリゴン | SQLite（トポロジ保持簡略化）
/// | 国土数値情報 N03」。パック生成パイプライン（`tools/pack-builder/`）が
/// 国土数値情報 N03 から払い出す区画コード等をそのまま保持する不透明な識別子として扱う
/// （`core` 側では形式を解釈しない）。
class DistrictId {
  /// 区画を一意に表す文字列。
  final String value;

  const DistrictId(this.value) : assert(value != '', 'DistrictId は空文字を許容しない');

  @override
  bool operator ==(Object other) => other is DistrictId && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'DistrictId($value)';
}

/// 行政区画（市区町村相当）1件のメタデータ（T024）。
///
/// plan.md §7 の区画制覇率・発展度の集計対象。区画ポリゴンの形状（トポロジ）そのものは
/// 表示・空間帰属判定用のデータであり、事前計算（ヘクス重心が区画内かの判定、
/// plan.md §8）を経て `location/` または `tools/pack-builder/` 側が保持する。
/// `core` はヘクス→区画の帰属結果（[RegionPack.districtOf]）と、区画の名称等の
/// メタデータのみを扱う。
class District {
  /// この区画の識別子。
  final DistrictId id;

  /// 区画の名称（例: 市区町村名）。
  final String name;

  const District({required this.id, required this.name});

  @override
  bool operator ==(Object other) =>
      other is District && other.id == id && other.name == name;

  @override
  int get hashCode => Object.hash(id, name);

  @override
  String toString() => 'District(id: $id, name: $name)';
}
