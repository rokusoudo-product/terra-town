"""H3 index <-> 地図 Feature の整数 `id` の橋渡し（Issue #38・2026-09-08 代表決定）。

## 背景

H3 のセルインデックスは 64bit 整数（値としては概ね 10^18 台）であり、
JSON の安全整数の上限（2^53 - 1 ≒ 9.007e15）を超える。
fog of war は全ヘクスを GeoJSON ソースとして地図に渡す方式（plan.md §8）で、
Android では `promoteId` が使えず Feature 直下の整数 `id` が必須（2026-08-13 Issue #38 コメント）
なので、H3 index をそのまま Feature の `id` に使うと JSON 数値としての精度が落ちる。

## 採用方式: 「下位ビットマスク」

同一パック（＝同一エリア）内では **H3 の解像度を固定** しているため、
H3 index の上位 12bit（reserved 1bit + mode 4bit + mode予約 3bit + resolution 4bit）は
**そのパック内の全セルで同一の定数** になる。したがって、この定数ヘッダ部分を切り捨てて
下位 52bit だけを取り出しても、同一パック内でのセルの一意性は失われない
（下位52bit = base cell 7bit + 各解像度の方向桁 最大45bit）。

- `feature_id = h3_index & FEATURE_ID_MASK`（`FEATURE_ID_MASK = (1 << 52) - 1`）
- 52bit の最大値 < 2**53 なので JSON safe integer の範囲内（実測: 本 Issue の対象エリアで
  最大 8.33e14 程度。research.md §8.4 参照）。
- **`disclosed_hex` の不変性（plan.md §3.3）を壊さない**: `feature_id` は
  `h3_index` と解像度という **座標のみから決まる純関数** であり、パック生成のたびに
  ヘクスの列挙順や生成時刻に依存する要素（採番カウンタ等）を一切含まない。
  そのため、同じ場所の H3 セルは、パックを何度作り直しても常に同じ `feature_id` になる。
  「パック単位で採番し直す」方式（例: 1,2,3... の連番）はこれを満たせないため不採用
  （後述）。
- **一意性はパック内（＝1ソース内）で十分**: fog of war の feature-state はソース単位
  （＝1エリア＝1パック）で完結するため、他パックとの間で `feature_id` が衝突しても問題ない
  （plan.md §3.2 の「1エリア=1パック」設計と整合）。

## 退けた案とその理由

1. **パック単位の連番（1, 2, 3, ...）採番**
   - 不採用理由: パック更新のたびに OSM データが変わり、ヘクスの列挙順（bbox内の走査順や
     中間データの並び）が変わりうる。連番は「その回の生成での位置」に依存するため、
     再生成後に同じ緯度経度でも別の feature_id になりうる。`disclosed_hex` は
     `(pack_version, hex_id)` 等で当時の開示を記録する設計（plan.md §3.3）だが、
     `hex_id` 自体の意味が生成のたびにズレると、たとえ `pack_version` を見ても
     「過去に開示したヘクス」を正しく指し示せなくなる恐れがあり、代表決定コメントで
     名指しで「検証してから選ぶこと」と警告されているリスクを踏まえ、
     本 Issue では採用しない。
2. **H3 index を文字列（16進表記）のまま Feature の `properties` に入れ、`promoteId` で昇格**
   - 不採用理由: `promoteId` は Web 専用で Android では機能しない
     （2026-08-13 Issue #38 コメント・plan.md §8）。
3. **H3 index を64bit のまま2つの32bit整数に分割し、2フィールドで持つ**
   - 不採用理由: MapLibre の Feature `id` は単一のスカラー値である必要があり、
     `setFeatureState(sourceId, featureId, ...)` のシグネチャも単一値を要求する。
     複合キーにすると feature-state API との相性が悪く、実装が複雑化するだけで
     52bit マスク方式に対する利点がない。
4. **H3 index を SHA256 等でハッシュして下位53bitを使う**
   - 不採用理由: ハッシュは非可逆であり、`feature_id` から `h3_index` を復元できなくなる。
     52bit マスク方式は可逆（後述の `feature_id_to_h3` 参照）であり、
     デバッグ・逆引きが必要な場面（例: タップされた feature_id からヘクスの地形属性を
     引く）でそのまま使える。ハッシュ方式にする実利がない。

## パック内での可逆性

同一パック内では resolution が1つに固定されているため、
`h3_index = (HEADER << 52) | feature_id` で復元できる
（`HEADER = h3_index >> 52` はパック内で共通の定数。パックメタに記録してもよいが、
実務上は `hex_terrain.hex_id`（H3 index の正）をそのまま SQLite に保持しているため、
`location/` 側は基本的に SQLite の `hex_id` を正として扱い、`feature_id` は
GeoJSON 境界のためだけに導出すればよい）。
"""

from __future__ import annotations

# H3 index の下位52bitだけを取り出すマスク。
# 52bit = base cell(7bit) + 15段の方向桁(3bit x 15 = 45bit)。
# 同一解像度のセルであれば、これより上位のビット（reserved/mode/resolution）は
# 全セルで共通の定数になるため、下位52bitだけで同一パック内の一意性が保たれる。
# 52bit の最大値 (2**52 - 1 = 4,503,599,627,370,495) は
# JSON の安全整数上限 2**53 - 1 = 9,007,199,254,740,991 の範囲内。
FEATURE_ID_BITS = 52
FEATURE_ID_MASK = (1 << FEATURE_ID_BITS) - 1


def h3_to_feature_id(h3_index_int: int) -> int:
    """H3 index（64bit整数）から地図 Feature の整数 `id` を導出する。

    同一パック（同一解像度のセル群）内では単射（衝突しない）。
    パックをまたいだ一意性は保証しない（保証する必要もない。上記モジュール docstring 参照）。
    """
    return h3_index_int & FEATURE_ID_MASK


def feature_id_to_h3(feature_id: int, header_bits: int) -> int:
    """`h3_to_feature_id` の逆変換（同一パック内でのみ有効）。

    `header_bits` は当該パックの `h3_index >> 52`（パック内で共通の定数）。
    """
    return (header_bits << FEATURE_ID_BITS) | feature_id


def header_bits_of(h3_index_int: int) -> int:
    """H3 index の上位ヘッダビット（reserved+mode+resolution）を取り出す。

    同一パック内の全セルでこの値が一致することを `verify_determinism.py` /
    `classify_terrain.py` の実行時アサーションで確認している。
    """
    return h3_index_int >> FEATURE_ID_BITS
