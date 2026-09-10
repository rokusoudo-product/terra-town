/// 地域パック（配布物）のバージョンを表す不透明な識別子（T024）。
///
/// 出典: `specs/001-mvp/plan.md` §3.2「パックメタ | `pack_version` 等」。
///
/// バージョニング規約（plan.md §3.3）:
/// 「OSM データは変わる。一度開示したヘクスの資材分類は、パック更新後も
/// 過去分は不変とする（獲得履歴は当時の `pack_version` で確定）」。
/// 本クラスは「どの時点のパックか」を記録・比較するための値オブジェクトとして
/// 本 Issue（#81・T024）で定義する。
///
/// 【不変性ルールの実現方法（2026-09-10・Issue #96・代表決定）】
/// 「当時の `pack_version` に対応する `RegionPack` を引き直す」方式（Issue #84・
/// PR #95）は、パックがアプリ同梱の MVP では旧パックが端末から消えるため成立しない。
/// 実際の不変性は「開示時点の地形タイプを `DisclosedHex` にスナップショットとして
/// 保存する」ことで実現しており、本クラスの値は資材分類の解決には使われない。
/// 保持し続けるのは「いつ開示したか」の監査記録、および将来のパック形式・
/// データ移行の判断材料としての用途のみ（`DisclosedHex.discoveredAtVersion` 参照）。
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
