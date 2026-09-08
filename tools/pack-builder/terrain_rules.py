"""docs/terrain.md §5 の OSMタグ→地形タイプ判定ルール（優先順位付き）の実装。

判定ルールの正は `docs/terrain.md` §5。本モジュールはそれをそのままコードに落としたもの。
ルール自体に不備が見つかった場合は、**このコードより先に docs/terrain.md §5 を更新**すること
（`CLAUDE.md` の方針: ドキュメントが常に正）。

`TerrainType` の文字列コードは `packages/core/lib/src/terrain/terrain_type.dart` の
enum 値（`vacantLot, forest, mountain, waterside, sea`）と
1:1で対応する snake_case 表記（`vacant_lot, forest, mountain, waterside, sea`）を
採用する。将来 `location/` 側でパックを読み込む際、このスネークケース文字列から
`TerrainType.values.byName(...)`（キャメルケースに変換して）へ機械的にマップできるようにする狙い。

【2026-09-08 Issue #70】地形タイプから農地・市街を除外し5種にした（代表決定）。
文明（畑・農場・工場・住宅等）はプレイヤーが空き地に建設する対象として `docs/buildings.md`
側に移し、地形タイプとしては固定配置しない設計に整理した。旧・優先度5（農地）
`landuse=farmland/orchard/vineyard/meadow`、旧・優先度6（市街）
`landuse=residential/commercial/industrial/retail` は、いずれも本モジュールから
削除し、判定ルールに一致しないタグとしてフォールバックの空き地（`vacant_lot`）に
合流させる（`classify_area_tags` がこれらのタグに対して None を返し、呼び出し側の
フォールバック処理で空き地になる。挙動としては対応する `if` 分岐を削除しただけ）。
"""

from __future__ import annotations

from dataclasses import dataclass

# 優先度が小さいほど優先（docs/terrain.md §5 の表と同じ番号）。
PRIORITY_SEA = 1
PRIORITY_WATERSIDE = 2
PRIORITY_MOUNTAIN = 3
PRIORITY_FOREST = 4
PRIORITY_VACANT_LOT = 5  # フォールバック（どの優先タグにも該当しない。Issue #70で5に繰り上げ）

TERRAIN_BY_PRIORITY = {
    PRIORITY_SEA: "sea",
    PRIORITY_WATERSIDE: "waterside",
    PRIORITY_MOUNTAIN: "mountain",
    PRIORITY_FOREST: "forest",
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

# --- 旧・優先度5(農地)/優先度6(市街) は Issue #70 で廃止 ------------------
# 廃止前の判定タグ（記録として残す。§5.1参照）:
#   農地: landuse=farmland/orchard/vineyard/meadow
#   市街: landuse=residential/commercial/industrial/retail（2026-09-08 に retail を追加した経緯は
#         docs/terrain.md §5.1・本モジュールのgit履歴を参照）
# いずれも本Issueでフォールバックの空き地に統合したため、対応する TagRule・
# classify_area_tags 内の分岐を削除した。詳細な経緯は docs/terrain.md §5.1・
# specs/001-mvp/research.md §8.8（5種化後の再生成結果。旧7種当時の記録は§8.5）参照。

# 優先度5（空き地）はフォールバックのため専用ルールを持たない。


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
