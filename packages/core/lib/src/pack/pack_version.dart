/// 地域パック（配布物）のバージョンを表す不透明な識別子（T024）。
///
/// 出典: `specs/001-mvp/plan.md` §3.2「パックメタ | `pack_version` 等」。
///
/// バージョニング規約（plan.md §3.3）:
/// 「OSM データは変わる。一度開示したヘクスの資材分類は、パック更新後も
/// 過去分は不変とする（獲得履歴は当時の `pack_version` で確定）」。
/// この不変性ルールそのものの実装は別 Issue（#84・tasks.md T035〜T037）が担当する。
/// 本クラスは「どの時点のパックか」を記録・比較するための値オブジェクトとして
/// 本 Issue（#81・T024）で定義する。
///
/// [PackVersion] の文字列がどのような形式（連番・日付・ハッシュ等）を取るかは
/// パック生成パイプライン（`tools/pack-builder/`・tasks.md T043）側の決定であり、
/// 本クラスは値の**等価性**のみを保証する。順序比較（新旧判定）が必要になった場合の
/// 具体的な規約は未確定のため、`Comparable` は現時点では実装しない
/// （必要になった時点で規約を確定のうえ追加すること）。
class PackVersion {
  /// パックのバージョンを表す文字列。
  final String value;

  const PackVersion(this.value) : assert(value != '', 'PackVersion は空文字を許容しない');

  @override
  bool operator ==(Object other) => other is PackVersion && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'PackVersion($value)';
}
