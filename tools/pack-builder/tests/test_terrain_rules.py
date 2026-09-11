"""terrain_rules.py の単体テスト（Issue #118）。

判定ルールの正は `docs/terrain.md` §5。本テストは同節の優先順位表と、
Issue #70（農地・市街の除外）・Issue #71（山の判定タグ拡張、戻り値のタプル化）を
反映した現在の `terrain_rules.py` の実装が、その表のとおりに動くことを検証する。

方針:
- 優先度定数は `terrain_rules.PRIORITY_*` を経由せず、docs/terrain.md §5 の表にある
  **リテラルな整数**（海=1, 水辺=2, 山=3, 森=4, 空き地=5）で直接アサートする。
  `rules.PRIORITY_SEA` のような自己参照の定数同士を比較するだけだと、
  例えば `PRIORITY_SEA` と `PRIORITY_FOREST` の値を入れ替える変異が起きても
  テストコード側の期待値まで一緒にズレてしまい、壊れたことを検出できない
  （Issue #50 の「ガード自身が壊れていることに気づけない」と同じ穴）。
  そのため期待値は必ずリテラルの整数・タプルで書く。
- 重い入力（OSM抽出・data_cache）は一切使わない。すべてテスト内のリテラルな
  タグ辞書（合成入力）のみで完結する。
"""

from __future__ import annotations

import pytest

import terrain_rules as rules

# docs/terrain.md §5 の優先度（上が優先＝数値が小さい）。
PRIORITY_SEA = 1
PRIORITY_WATERSIDE = 2
PRIORITY_MOUNTAIN = 3
PRIORITY_FOREST = 4
PRIORITY_VACANT_LOT = 5  # フォールバック（classify_area_tags は None を返す）


# ---------------------------------------------------------------------------
# 0. 地形タイプは5種（Issue #70で農地・市街を除外）
# ---------------------------------------------------------------------------


def test_terrain_types_are_five_kinds_in_priority_order():
    """docs/terrain.md §2: 地形タイプは5種、§5: 優先度1..5の順。"""
    assert rules.TERRAIN_BY_PRIORITY == {
        1: "sea",
        2: "waterside",
        3: "mountain",
        4: "forest",
        5: "vacant_lot",
    }
    # dict の挿入順（Python 3.7+で順序保証）が優先度の昇順になっていること。
    assert rules.ALL_TERRAIN_TYPES == ("sea", "waterside", "mountain", "forest", "vacant_lot")
    assert len(rules.ALL_TERRAIN_TYPES) == 5


def test_priority_constants_match_docs_terrain_md_section5_literal_numbers():
    """優先度定数がdocs/terrain.md §5表のリテラル数値と一致すること。

    ここは意図的に `rules.PRIORITY_SEA == 1` のようにリテラル整数と比較する
    （`rules.PRIORITY_SEA == rules.PRIORITY_SEA` のような自己参照にしない）。
    """
    assert rules.PRIORITY_SEA == 1
    assert rules.PRIORITY_WATERSIDE == 2
    assert rules.PRIORITY_MOUNTAIN == 3
    assert rules.PRIORITY_FOREST == 4
    assert rules.PRIORITY_VACANT_LOT == 5


# ---------------------------------------------------------------------------
# 1. classify_area_tags: 優先度1〜4 が docs/terrain.md §5 のタグ例どおりに判定されること
# ---------------------------------------------------------------------------

AREA_CASES: list[tuple[dict[str, str], int | None]] = [
    # --- 優先度1: 海 ---
    ({"place": "sea"}, PRIORITY_SEA),
    ({"natural": "bay"}, PRIORITY_SEA),
    ({"natural": "water", "water": "sea"}, PRIORITY_SEA),
    # --- 優先度2: 水辺（川・湖） ---
    ({"natural": "water", "water": "lake"}, PRIORITY_WATERSIDE),
    ({"natural": "water"}, PRIORITY_WATERSIDE),  # water=* 未指定でも sea でなければ水辺
    ({"natural": "wetland"}, PRIORITY_WATERSIDE),
    # --- 優先度3: 山（Issue #71でhill/cliff/rockを追加。面判定分） ---
    ({"natural": "bare_rock"}, PRIORITY_MOUNTAIN),
    ({"natural": "scree"}, PRIORITY_MOUNTAIN),
    ({"natural": "mountain_range"}, PRIORITY_MOUNTAIN),
    ({"natural": "cliff"}, PRIORITY_MOUNTAIN),
    ({"natural": "rock"}, PRIORITY_MOUNTAIN),
    ({"landuse": "quarry"}, PRIORITY_MOUNTAIN),
    # --- 優先度4: 森 ---
    ({"landuse": "forest"}, PRIORITY_FOREST),
    ({"natural": "wood"}, PRIORITY_FOREST),
    # --- 優先度5（フォールバック）: 該当なし ---
    ({}, None),
    ({"highway": "residential"}, None),
    ({"landuse": "grass"}, None),
    ({"landuse": "greenfield"}, None),
    ({"landuse": "brownfield"}, None),
    # natural=peak/hill は「点」専用タグ（面としては判定しない。classify_point_tags参照）。
    ({"natural": "peak"}, None),
    ({"natural": "hill"}, None),
    # natural=ridge は「線」専用タグ（面としては判定しない。classify_way_tags参照）。
    ({"natural": "ridge"}, None),
]


@pytest.mark.parametrize("tags, expected_priority", AREA_CASES)
def test_classify_area_tags(tags: dict[str, str], expected_priority: int | None):
    assert rules.classify_area_tags(tags) == expected_priority


# ---------------------------------------------------------------------------
# 2. Issue #70: 旧・農地／市街タグはすべてフォールバック（空き地）へ合流する
# ---------------------------------------------------------------------------

EXCLUDED_FARMLAND_AND_URBAN_TAGS: list[dict[str, str]] = [
    # 旧・農地（Issue #70で除外）
    {"landuse": "farmland"},
    {"landuse": "orchard"},
    {"landuse": "vineyard"},
    {"landuse": "meadow"},
    # 旧・市街（Issue #70で除外。retail は Issue #38時点で後から追加された経緯あり）
    {"landuse": "residential"},
    {"landuse": "commercial"},
    {"landuse": "industrial"},
    {"landuse": "retail"},
]


@pytest.mark.parametrize("tags", EXCLUDED_FARMLAND_AND_URBAN_TAGS)
def test_farmland_and_urban_tags_fall_back_to_vacant_lot(tags: dict[str, str]):
    """Issue #70: 農地・市街相当のタグは独立した地形タイプを持たず、
    classify_area_tags が None を返す（=呼び出し側で空き地にフォールバックする）こと。
    """
    assert rules.classify_area_tags(tags) is None


# ---------------------------------------------------------------------------
# 3. 優先順位のタイブレーク（同一セルに複数タグが重なる場合、上位が勝つこと）
# ---------------------------------------------------------------------------

TIEBREAK_CASES: list[tuple[dict[str, str], int]] = [
    # 海(place=sea) vs 水辺(natural=wetland) → 海が勝つ
    ({"place": "sea", "natural": "wetland"}, PRIORITY_SEA),
    # 水辺(natural=wetland) vs 山(landuse=quarry) → 水辺が勝つ
    ({"natural": "wetland", "landuse": "quarry"}, PRIORITY_WATERSIDE),
    # 山(landuse=quarry) vs 森(natural=wood) → 山が勝つ
    ({"landuse": "quarry", "natural": "wood"}, PRIORITY_MOUNTAIN),
    # 海(natural=water&water=sea) vs 山(landuse=quarry) → 海が勝つ
    ({"natural": "water", "water": "sea", "landuse": "quarry"}, PRIORITY_SEA),
]


@pytest.mark.parametrize("tags, expected_priority", TIEBREAK_CASES)
def test_priority_tiebreak_when_multiple_categories_match(
    tags: dict[str, str], expected_priority: int
):
    assert rules.classify_area_tags(tags) == expected_priority


# ---------------------------------------------------------------------------
# 4. classify_way_tags（開いたway=線）: (優先度, バッファ半径m) のタプルを返すこと
# ---------------------------------------------------------------------------

WAY_CASES: list[tuple[dict[str, str], tuple[int, float] | None]] = [
    ({"waterway": "river"}, (PRIORITY_WATERSIDE, 5.0)),
    ({"waterway": "stream"}, (PRIORITY_WATERSIDE, 5.0)),
    ({"waterway": "canal"}, (PRIORITY_WATERSIDE, 5.0)),
    # Issue #71 で追加された山の線状タグ。
    ({"natural": "ridge"}, (PRIORITY_MOUNTAIN, 10.0)),
    ({"natural": "cliff"}, (PRIORITY_MOUNTAIN, 10.0)),
    # 該当なし
    ({}, None),
    ({"waterway": "drain"}, None),
    ({"natural": "tree_row"}, None),
    # 面専用タグ(landuse=quarry)は線としては判定しない。
    ({"landuse": "quarry"}, None),
]


@pytest.mark.parametrize("tags, expected", WAY_CASES)
def test_classify_way_tags(tags: dict[str, str], expected: tuple[int, float] | None):
    assert rules.classify_way_tags(tags) == expected


def test_classify_way_tags_tiebreak_waterside_over_mountain():
    """水辺(waterway=river)と山(natural=ridge)が同一タグ集合に混在する場合、
    優先度の高い水辺が勝つこと。
    """
    tags = {"waterway": "river", "natural": "ridge"}
    assert rules.classify_way_tags(tags) == (PRIORITY_WATERSIDE, 5.0)


# ---------------------------------------------------------------------------
# 5. classify_point_tags（ノード=点）: summit系(30m)とfeature系(10m)のバッファ分岐
# ---------------------------------------------------------------------------

POINT_CASES: list[tuple[dict[str, str], tuple[int, float] | None]] = [
    # summit系（山頂・丘頂上）は既存の30mバッファをそのまま使う。
    ({"natural": "peak"}, (PRIORITY_MOUNTAIN, 30.0)),
    ({"natural": "hill"}, (PRIORITY_MOUNTAIN, 30.0)),
    # feature系（崖・露岩）はsummitより小さい10mバッファ。
    ({"natural": "cliff"}, (PRIORITY_MOUNTAIN, 10.0)),
    ({"natural": "rock"}, (PRIORITY_MOUNTAIN, 10.0)),
    # 該当なし
    ({}, None),
    ({"natural": "tree"}, None),
    # 面専用タグ(landuse=quarry)・線専用タグ(natural=ridge)は点としては判定しない。
    ({"landuse": "quarry"}, None),
    ({"natural": "ridge"}, None),
]


@pytest.mark.parametrize("tags, expected", POINT_CASES)
def test_classify_point_tags(tags: dict[str, str], expected: tuple[int, float] | None):
    assert rules.classify_point_tags(tags) == expected


def test_classify_point_tags_summit_buffer_is_larger_than_feature_buffer():
    """summit系(30m)がfeature系(10m)より広いバッファであること（§5.1の設計意図）。"""
    _, summit_buffer = rules.classify_point_tags({"natural": "peak"})
    _, feature_buffer = rules.classify_point_tags({"natural": "cliff"})
    assert summit_buffer > feature_buffer


# ---------------------------------------------------------------------------
# 6. TagRule データクラス自体の単体テスト
# ---------------------------------------------------------------------------


def test_tagrule_matches_by_key_and_value():
    rule = rules.TagRule("natural", ("wood",))
    assert rule.matches({"natural": "wood"}) is True
    assert rule.matches({"natural": "water"}) is False
    assert rule.matches({}) is False


def test_tagrule_with_values_none_matches_key_existence_only():
    """`values=None` の場合、キーの存在のみで真になること（例: building=*）。"""
    rule = rules.TagRule("building")
    assert rule.matches({"building": "yes"}) is True
    assert rule.matches({"building": "house"}) is True
    assert rule.matches({"other": "x"}) is False


# ---------------------------------------------------------------------------
# 7. 補助関数 is_sea_water_polygon / is_waterside_water_polygon
# ---------------------------------------------------------------------------


def test_is_sea_water_polygon():
    assert rules.is_sea_water_polygon({"natural": "water", "water": "sea"}) is True
    assert rules.is_sea_water_polygon({"natural": "water", "water": "lake"}) is False
    assert rules.is_sea_water_polygon({"natural": "water"}) is False
    assert rules.is_sea_water_polygon({}) is False


def test_is_waterside_water_polygon():
    assert rules.is_waterside_water_polygon({"natural": "water", "water": "lake"}) is True
    assert rules.is_waterside_water_polygon({"natural": "water"}) is True
    assert rules.is_waterside_water_polygon({"natural": "water", "water": "sea"}) is False
    assert rules.is_waterside_water_polygon({}) is False
