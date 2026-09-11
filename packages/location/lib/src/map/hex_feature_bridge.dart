/// [HexId]（core・H3 index）↔ 地図 Feature の整数 `id` の変換（Issue #137）。
///
/// 出典: `docs/terrain.md` §4.4「H3 index → 地図 Feature の `id` の橋渡し」。
/// **採用方式: 下位52bitマスク**。`feature_id = h3_index & ((1 << 52) - 1)`。
/// 52bit の最大値（4,503,599,627,370,495）は 2^53-1 未満であり、JSON の安全整数の
/// 範囲に収まる。この変換は `h3_index` だけから決まる**純関数**であり、パックの
/// 生成回数・列挙順に依存しない（同じ場所のヘクスは常に同じ `feature_id` になる）。
///
/// `tools/pack-builder/hex_bridge.py`（生成側の参照実装）と同じマスク値を用いる。
/// `hex_terrain.feature_id` 列はこの計算結果を**事前計算済み**として保持しているため
/// （`fog_hex_source.dart` 参照）、fog of war の描画（既存ヘクスの `feature_id`）は
/// その列をそのまま読むだけでよい。
///
/// 本関数が必要になるのは、**開示判定（`DisclosureService`）が返す `HexId` を、
/// 地域パックへ再度問い合わせずに `FogOfWarController.revealHex` の `featureId` へ
/// 変換したい場合**（Issue #137・composition root の配線）である。純関数のため
/// DB 往復なしでその場で計算でき、開示のたびに `hex_terrain` を引き直す必要がない。
///
/// `location/` の責務であり `core` には置かない（`HexId` は「地図 Feature の
/// 整数 `id` への変換は `location/` の責務」と明記している。`hex_id.dart` 参照）。
///
/// 【`HexId.toInt()` との違い】[HexId.toInt] は `value`（H3 index そのもの）を
/// そのまま返すだけで、52bitマスクは適用しない。マスク前の値をそのまま地図
/// Feature の `id` に使うと 2^53-1 を超え JSON safe integer の範囲外になりうるため、
/// 地図に渡す `id` には必ず本関数を通した値を使うこと。
int hexIdToFeatureId(int hexIndex) {
  const mask = (1 << 52) - 1;
  return hexIndex & mask;
}
