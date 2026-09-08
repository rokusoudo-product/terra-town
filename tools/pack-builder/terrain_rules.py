"""docs/terrain.md §5 の OSMタグ→地形タイプ判定ルール（優先順位付き）の実装。

判定ルールの正は `docs/terrain.md` §5。本モジュールはそれをそのままコードに落としたもの。
ルール自体に不備が見つかった場合は、**このコードより先に docs/terrain.md §5 を更新**すること
（`CLAUDE.md` の方針: ドキュメントが常に正）。

`TerrainType` の文字列コードは `packages/core/lib/src/terrain/terrain_type.dart` の
enum 値（`vacantLot, forest, mountain, waterside, sea, farmland, urban`）と
1:1で対応する snake_case 表記（`vacant_lot, forest, mountain, waterside, sea, farmland, urban`）を
採用する。将来 `location/` 側でパックを読み込む際、このスネークケース文字列から
`TerrainType.values.byName(...)`（キャメルケースに変換して）へ機械的にマップできるようにする狙い。
"""

from __future__ import annotations

from dataclasses import dataclass

# 優先度が小さいほど優先（docs/terrain.md §5 の表と同じ番号）。
PRIORITY_SEA = 1
PRIORITY_WATERSIDE = 2
PRIORITY_MOUNTAIN = 3
PRIORITY_FOREST = 4
PRIORITY_FARMLAND = 5
PRIORITY_URBAN = 6
PRIORITY_VACANT_LOT = 7  # フォールバック（どの優先タグにも該当しない）

TERRAIN_BY_PRIORITY = {
    PRIORITY_SEA: "sea",
    PRIORITY_WATERSIDE: "waterside",
    PRIORITY_MOUNTAIN: "mountain",
    PRIORITY_FOREST: "forest",
    PRIORITY_FARMLAND: "farmland",
    PRIORITY_URBAN: "urban",
    PRIORITY_VACANT_LOT: "vacant_lot",
}

ALL_TERRAIN_TYPES = tuple(TERRAIN_BY_PRIORITY.values())


@dataclass(frozen=True)
class TagRule:
    """1つの OSM タグ条件。`key` の値が `values` のいずれかに一致すれば真。

    `values=None` の場合は key の存在のみで真（値は問わない。例: building=*）。
    """

    key: str
    values: tuple[str, ...] | None = None

    def matches(self, tags: dict[str, str]) -> bool:
        if self.key not in tags:
            return False
        if self.values is None:
            return True
        return tags[self.key] in self.values


# --- 優先度1: 海 ---------------------------------------------------------
# docs/terrain.md §5: natural=coastline の海側、natural=bay、place=sea、
#                      natural=water かつ water=sea
#
# 【本プロトタイプでの既知の簡略化】
# `natural=coastline` は「線」であり、その海側だけを面として得るには
# 陸海ポリゴンの合成（OSM水域データセットの land polygons 方式や osmcoastline 等の
# 専用処理）が必要で、本スパイクのスコープ（使い捨てコードで1エリア検証）を大きく超える。
# 本プロトタイプでは coastline からの海面合成は実装せず、
# 明示的にタグ付けされたポリゴン（natural=water & water=sea、place=sea、natural=bay）
# のみを「海」として扱う。対象エリア（本Issueでは内陸の仮エリア）には
# 実際には海が存在しないため、この簡略化は今回の検証結果に影響しない。
# 本番実装（T039・Planetiler）では海岸線データセットの扱いを別途設計すること。
SEA_RULES = (
    TagRule("place", ("sea",)),
    TagRule("natural", ("bay",)),
    # natural=water かつ water=sea は classify_terrain.py 側で複合条件として判定する
    # （TagRule単体では AND 条件を表現できないため）。
)


def is_sea_water_polygon(tags: dict[str, str]) -> bool:
    return tags.get("natural") == "water" and tags.get("water") == "sea"


# --- 優先度2: 水辺（川・湖） -----------------------------------------------
# natural=water（water=sea を除く）、waterway=river/stream/canal、natural=wetland
WATERSIDE_AREA_RULES = (
    TagRule("natural", ("wetland",)),
    # natural=water は water=sea 以外の場合にここで扱う（classify_terrain.py で除外判定）。
)
WATERSIDE_LINE_RULES = (
    TagRule("waterway", ("river", "stream", "canal")),
)

# 【既知の簡略化】OSMの waterway=river/stream/canal は中心線（線分）のみで、
# 実際の川幅はタグに含まれないことが多い。本プロトタイプでは固定バッファ幅で
# 面として近似する。実際の川幅は場所によって大きく異なる（本プロトタイプは
# 「地形タイプ判定ロジックの検証」が目的であり、川幅の正確な再現は目的外）。
WATERWAY_LINE_BUFFER_M = 5.0


def is_waterside_water_polygon(tags: dict[str, str]) -> bool:
    return tags.get("natural") == "water" and tags.get("water") != "sea"


# --- 優先度3: 山 ----------------------------------------------------------
# natural=peak、natural=mountain_range、natural=bare_rock、natural=scree、landuse=quarry
#
# 【既知の簡略化】natural=peak は OSM 上は通常「点」（山頂ノード）で面積を持たない。
# 本プロトタイプでは点データに一定半径のバッファ（MOUNTAIN_PEAK_BUFFER_M）を掛けて
# 面として扱う簡易近似とする。natural=mountain_range は実運用でほぼ使われていない
# タグ（OSM wiki上も「使用が承認されていない」）ため、本プロトタイプでは
# タグ一致条件としては残すが、実データでのヒットは想定していない。
MOUNTAIN_AREA_RULES = (
    TagRule("natural", ("bare_rock", "scree", "mountain_range")),
    TagRule("landuse", ("quarry",)),
)
MOUNTAIN_POINT_RULES = (
    TagRule("natural", ("peak",)),
)
MOUNTAIN_PEAK_BUFFER_M = 30.0


# --- 優先度4: 森 ----------------------------------------------------------
FOREST_AREA_RULES = (
    TagRule("landuse", ("forest",)),
    TagRule("natural", ("wood",)),
)

# --- 優先度5: 農地 ---------------------------------------------------------
FARMLAND_AREA_RULES = (
    TagRule("landuse", ("farmland", "orchard", "vineyard", "meadow")),
)

# --- 優先度6: 市街 ---------------------------------------------------------
# docs/terrain.md §5（本Issueでの改訂後）: landuse=residential/commercial/industrial/retail、
#                      building=* が一定密度以上
#
# 【本プロトタイプで判明した判定ルールの不備・2026-09-08 修正】
# 当初の docs/terrain.md §5 は landuse=residential/commercial/industrial のみを
# 市街判定タグとしていたが、本プロトタイプの実データ検証（狭山湖周辺、本ファイル冒頭）で
# `landuse=retail`（コストコ入間倉庫店・三井アウトレットパーク入間など、実在する
# 大型小売店舗の敷地）が該当し、かつ既存ルールでは市街のいずれにも一致せず
# フォールバックの「空き地」に誤分類されることが判明した。
# 小売店舗の敷地は実態として市街地の一部であり、産出資材の観点でも空き地
# （建築の土台）として扱う理由がないため、`landuse=retail` を優先度6に追加した。
# この修正は docs/terrain.md §5 にも反映済み（同じPRに含む）。
#
# 【既知の簡略化】「building=* が一定密度以上」の密度しきい値は docs/terrain.md にも
# 具体的な数値が定義されておらず、本プロトタイプでは実装していない
# （landuse=residential/commercial/industrial/retail のみで判定）。密度ベースの補完は
# plan/tasks 工程での精緻化事項として残す。
URBAN_AREA_RULES = (
    TagRule("landuse", ("residential", "commercial", "industrial", "retail")),
)

# 優先度7（空き地）はフォールバックのため専用ルールを持たない。


def classify_area_tags(tags: dict[str, str]) -> int | None:
    """閉領域（Area: 閉じたway or マルチポリゴンrelation）のタグから優先度を決める。

    docs/terrain.md §5 の優先順位どおり、優先度が小さい方から順に判定して最初に
    一致したものを採用する（複数タグが同一セルに重なる場合の確定ルール）。
    どれにも一致しなければ None（呼び出し側でフォールバック=空き地として扱う）。
    """
    if is_sea_water_polygon(tags) or any(r.matches(tags) for r in SEA_RULES):
        return PRIORITY_SEA
    if is_waterside_water_polygon(tags) or any(r.matches(tags) for r in WATERSIDE_AREA_RULES):
        return PRIORITY_WATERSIDE
    if any(r.matches(tags) for r in MOUNTAIN_AREA_RULES):
        return PRIORITY_MOUNTAIN
    if any(r.matches(tags) for r in FOREST_AREA_RULES):
        return PRIORITY_FOREST
    if any(r.matches(tags) for r in FARMLAND_AREA_RULES):
        return PRIORITY_FARMLAND
    if any(r.matches(tags) for r in URBAN_AREA_RULES):
        return PRIORITY_URBAN
    return None


def classify_way_tags(tags: dict[str, str]) -> int | None:
    """開いたway（線: waterway=river/stream/canal 等）のタグから優先度を決める。"""
    if any(r.matches(tags) for r in WATERSIDE_LINE_RULES):
        return PRIORITY_WATERSIDE
    return None


def classify_point_tags(tags: dict[str, str]) -> int | None:
    """ノード（点: natural=peak 等）のタグから優先度を決める。"""
    if any(r.matches(tags) for r in MOUNTAIN_POINT_RULES):
        return PRIORITY_MOUNTAIN
    return None
