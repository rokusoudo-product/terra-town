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

【2026-09-08 Issue #71】山の判定タグを拡張した（代表決定に基づく案A）。
`natural=hill`（点）・`natural=ridge`（線）・`natural=cliff`（点/線/面）・
`natural=rock`（点/面）を追加。実データでの効果測定・`natural=peak`バッファ半径の
判断根拠・DEM要否の結論は `specs/001-mvp/research.md` §8.9 参照。
点・線タグはこれまでの「単一バッファ定数」から「タグの種類ごとに異なるバッファ」を
扱えるよう `classify_point_tags`・`classify_way_tags` の戻り値を
`(優先度, バッファ半径m)` のタプルに変更した（呼び出し側 `classify_terrain.py` も
合わせて更新済み）。
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
# 【2026-09-08 Issue #71】タグを拡張した。追加したタグ・根拠・実データでの効果測定は
# `specs/001-mvp/research.md` §8.9 を参照（結論: この検証エリアには追加タグの
# 該当データが1件も存在せず、実測上の効果はゼロだった。地物としては正しい拡張のため
# コードは残すが、「タグを広げれば増える」という前提自体が別エリアでは成り立たない
# 可能性がある点に注意）。
#
# 【既知の簡略化】natural=peak・natural=hill は OSM 上は通常「点」（山頂ノード）で
# 面積を持たない。本プロトタイプでは点データに一定半径のバッファ
# （MOUNTAIN_PEAK_BUFFER_M）を掛けて面として扱う簡易近似とする。natural=mountain_range
# は実運用でほぼ使われていないタグ（OSM wiki上も「使用が承認されていない」）ため、
# 本プロトタイプではタグ一致条件としては残すが、実データでのヒットは想定していない。
#
# natural=cliff・natural=rock は OSM wiki上、点・線・面のいずれでも使われる
# （`natural=ridge` は線のみ）。面で閉じている場合はそのままMOUNTAIN_AREA_RULESで、
# 点・線の場合は下記のバッファ付き点・線ルールで扱う。
MOUNTAIN_AREA_RULES = (
    TagRule("natural", ("bare_rock", "scree", "mountain_range", "cliff", "rock")),
    TagRule("landuse", ("quarry",)),
)

# 山頂・丘頂上（点）。summit扱いで、既存の30mバッファをそのまま適用する。
MOUNTAIN_SUMMIT_POINT_RULES = (
    TagRule("natural", ("peak", "hill")),
)
MOUNTAIN_PEAK_BUFFER_M = 30.0
# 【2026-09-08 Issue #71・根拠つきで「変更しない」と判断】
# `natural=peak`にはOSM上、山体の大きさ・裾野の広さを示す情報が一切付随しない
# （標高`ele`はあっても水平方向の広がりは不明）。DEM等の傾斜データなしにこの半径を
# 拡大する行為は「実データに基づく判断」ではなく推測に等しいため、本Issueでは行わない
# （代表決定: DEMは投機的に導入しない）。
# 感度分析（`tools/pack-builder/peak_radius_sensitivity.py`）として
# 30/50/75/100/150/200mで再生成した結果は research.md §8.9.3 に記録した。
# 200m（現行の6.7倍）まで拡大しても山は0.02%→0.98%にしか増えず、その代償として
# 森113ヘクス（森全体の約2.7%）を侵食する。「タグ拡張で到達できる水準」を測るという
# 本Issueの目的（代表決定2026-09-08）に対し、根拠のない半径拡大で数値を作ることは
# 目的に反するため、30m据え置きを結論とする。

# 崖・露岩などの局所的な地物（点）。summitより小さい地物であるため、
# summit用バッファ(30m)をそのまま流用せず、より小さい専用バッファを設ける。
MOUNTAIN_FEATURE_POINT_RULES = (
    TagRule("natural", ("cliff", "rock")),
)
# 根拠: 露岩(rock)・崖(点表記のcliff)は、山頂のような広い裾野を持つ地物ではなく、
# 単体の岩・短い崖面という局所的な広がりの地物である。既存のwaterway線バッファ(5m)より
# 大きく、summitバッファ(30m)よりは明確に小さい値として10mを採用する
# （具体的な実測値ではなく、地物の性質から見た相対的な大小関係に基づくオーダー感の判断。
# 本検証エリアには該当データが存在しないため実測での裏付けはできていない）。
MOUNTAIN_SMALL_FEATURE_BUFFER_M = 10.0

# 稜線(ridge)・崖線(cliffの線表記)。線状の岩場・急斜面の縁を表す。
MOUNTAIN_LINE_RULES = (
    TagRule("natural", ("ridge", "cliff")),
)
# 根拠は MOUNTAIN_SMALL_FEATURE_BUFFER_M と同じ考え方のため同じ値を採用する
# （線の両側に均等にバッファすることで帯状の地形として近似する）。
MOUNTAIN_LINE_BUFFER_M = MOUNTAIN_SMALL_FEATURE_BUFFER_M


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


def classify_way_tags(tags: dict[str, str]) -> tuple[int, float] | None:
    """開いたway（線: waterway=river/stream/canal・natural=ridge/cliff 等）の
    タグから (優先度, バッファ半径m) を決める。

    【2026-09-08 Issue #71】山の線状タグ（natural=ridge・natural=cliff）を
    追加したのに伴い、線ごとにバッファ幅が異なるため戻り値をタプルに変更した
    （旧: 優先度のみを返し、呼び出し側が WATERWAY_LINE_BUFFER_M 固定で使っていた）。
    """
    if any(r.matches(tags) for r in WATERSIDE_LINE_RULES):
        return PRIORITY_WATERSIDE, WATERWAY_LINE_BUFFER_M
    if any(r.matches(tags) for r in MOUNTAIN_LINE_RULES):
        return PRIORITY_MOUNTAIN, MOUNTAIN_LINE_BUFFER_M
    return None


def classify_point_tags(tags: dict[str, str]) -> tuple[int, float] | None:
    """ノード（点: natural=peak/hill/cliff/rock 等）から (優先度, バッファ半径m) を決める。

    【2026-09-08 Issue #71】classify_way_tags と同じ理由でタプルを返すよう変更した。
    summit系（peak・hill）とfeature系（cliff・rock）でバッファ幅が異なるため、
    どちらに一致したかで採用するバッファ半径を切り替える。
    """
    if any(r.matches(tags) for r in MOUNTAIN_SUMMIT_POINT_RULES):
        return PRIORITY_MOUNTAIN, MOUNTAIN_PEAK_BUFFER_M
    if any(r.matches(tags) for r in MOUNTAIN_FEATURE_POINT_RULES):
        return PRIORITY_MOUNTAIN, MOUNTAIN_SMALL_FEATURE_BUFFER_M
    return None
