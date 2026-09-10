/// `building` テーブル（T033）が保持する建物種別。
///
/// 出典: `docs/buildings.md` §2「建物種別（MVP・3系統8種）」。
/// **7種ではなく8種**であることに注意（採石場は Issue #72・2026-09-09 代表決定で追加）。
/// この列挙は同ドキュメントの3系統・掲載順にそのまま対応させている。
///
/// 【`core` の将来の `Resource`/建物種別との関係について】
/// `packages/core` 側に建物種別・資材の enum を置く計画（tasks.md T026〜、Issue #82・
/// PR #89）が並行して進んでいるが、本 Issue（#83）時点では未マージであり、
/// `location` 側の永続化スキーマがそれに依存すると PR 間の結合が生まれてしまう
/// （Issue #83 本文の注意書きに基づく判断）。そのため本 enum は `location` 内で
/// スキーマ専用に定義し、`core` 側の型とは独立させている。将来 `core` 側の型が
/// 確定した際に、変換（`core` の型 <-> 本 enum）を担うマッピング層を
/// 別途整備すること（本 Issue のスコープ外）。
///
/// DB 上は列名の変更・並べ替えに強い `textEnum`（`.name` を文字列として保存）で
/// 永続化する（`GameDatabase` の `Building` テーブル定義を参照）。
enum BuildingType {
  /// 住宅系: 住宅（人口上限 少なめ。buildings.md §5.1）。
  house,

  /// 住宅系: マンション（人口上限 多め。buildings.md §5.1）。
  apartment,

  /// 生産系: 畑（野菜・フルーツを生産。buildings.md §2）。
  cropField,

  /// 生産系: 農場（肉を生産。★新資材・buildings.md §6.1）。
  livestockFarm,

  /// 生産系: 工場（生産率向上・街全体の産出に効く。buildings.md §2）。
  factoryBuilding,

  /// 生産系: 採石場（★新設・Issue #72・2026-09-09 代表決定。石・鉄を産出。
  /// buildings.md §6.3）。
  quarry,

  /// 娯楽系: リゾート（海に隣接する空き地に建築。buildings.md §2）。
  resort,

  /// 娯楽系: ミュージアム（プレイヤーが建設した住宅系建物に隣接する空き地に建築。
  /// buildings.md §2・Issue #70 で配置制約を再定義）。
  museum,
}
