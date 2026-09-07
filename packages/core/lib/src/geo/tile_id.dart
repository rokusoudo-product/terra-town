/// 内部判定用の矩形細分グリッドセルの決定論的な識別子。
///
/// docs/terrain.md §4「内部の開示判定・資材判定は、緯度経度ベースの矩形グリッド
/// （例: 数m四方の細分セル）に対して行う」・plan.md §3.2（`cell_terrain` →
/// `hex_terrain` への集約）・plan.md §5「内部判定 = 緯度経度ベースの矩形細分
/// グリッド（数m四方）」に対応する値オブジェクト。
///
/// [HexId] が表示単位（ヘクス）の識別子であるのに対し、[TileId] は
/// OSMタグとの交差判定を行う内部判定単位（矩形グリッドセル）の識別子であり、
/// 複数の [TileId] が多数決集約（terrain.md §4・§6）で1つの [HexId] にまとめられる。
///
/// Issue #33 の「❓細分グリッドセルを表す型（`CellId` 相当）の要否」については、
/// tasks.md T021 が元々 [TileId] を [HexId] と並べて定義していたこと
/// （plan.md §5「`core/` は事前計算済みの `HexId`／`TileId`（決定論的な
/// 緯度経度→ID変換の結果）と地形属性のみを受け取る」）を踏まえ、
/// **[TileId] を矩形細分グリッドセルの識別子として実装することで対応する**。
/// 別名で新規の型（`CellId`）を追加する必要はないと判断した（詳細は PR 本文）。
///
/// [HexId] と同様、緯度経度→[TileId] の変換ロジック自体は `core` に置かず、
/// `location/` または表示レイヤー（実運用では `tools/pack-builder` の
/// 事前計算パイプライン）の責務とする。
class TileId {
  /// グリッドセルを一意に表す非負整数値。
  final int value;

  const TileId(this.value) : assert(value >= 0, 'TileId は非負の整数のみを表す');

  @override
  bool operator ==(Object other) => other is TileId && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'TileId($value)';
}
