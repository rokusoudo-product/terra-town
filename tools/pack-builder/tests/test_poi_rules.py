"""poi_rules.py の単体テスト（Issue #86・T042。Tier 2 は Issue #158）。

`poi_rules.matched_tag` は純粋関数（h3・osmium いずれも呼ばない）であり、
`test_hex_neighbors.py`・`test_terrain_rules.py` と同じ方針で軽量な
`requirements-dev.txt`（pytestのみ）環境で完結するテストにする（Issue #118）。
"""

from __future__ import annotations

import poi_rules


def test_tier1_tag_matches_without_include_tier2():
    result = poi_rules.matched_tag({"tourism": "viewpoint"})
    assert result == (("tourism", "viewpoint"), 1)


def test_tier1_tag_matches_even_with_include_tier2_true():
    result = poi_rules.matched_tag({"tourism": "viewpoint"}, include_tier2=True)
    assert result == (("tourism", "viewpoint"), 1)


def test_unmatched_tags_return_none():
    assert poi_rules.matched_tag({"shop": "convenience"}) is None
    assert poi_rules.matched_tag({"shop": "convenience"}, include_tier2=True) is None


def test_tier2_tag_ignored_when_include_tier2_false():
    assert poi_rules.matched_tag({"amenity": "place_of_worship"}) is None


def test_tier2_tag_matches_when_include_tier2_true():
    result = poi_rules.matched_tag({"amenity": "place_of_worship"}, include_tier2=True)
    assert result == (("amenity", "place_of_worship"), 2)


def test_tier1_takes_priority_over_tier2_when_both_match():
    """1つの地物がTier1・Tier2の両方に該当する場合はTier1のkindを採用する
    （Issue #158代表決定）。ここでは合成タグ辞書で両方に該当させて確認する。"""
    tags = {"tourism": "viewpoint", "amenity": "place_of_worship"}
    result = poi_rules.matched_tag(tags, include_tier2=True)
    assert result == (("tourism", "viewpoint"), 1)


def test_natural_tree_requires_denotation_natural_monument():
    """`natural=tree`は「名木指定のみ」（denotation=natural_monument）が条件（§2.1）。"""
    assert (
        poi_rules.matched_tag({"natural": "tree"}, include_tier2=True) is None
    )
    assert (
        poi_rules.matched_tag(
            {"natural": "tree", "denotation": "natural_monument"}, include_tier2=True
        )
        == (("natural", "tree"), 2)
    )
    assert (
        poi_rules.matched_tag(
            {"natural": "tree", "denotation": "urban"}, include_tier2=True
        )
        is None
    )


def test_all_tier2_tags_match_individually_when_included():
    for key, value in poi_rules.TIER2_TAGS:
        tags = {key: value}
        if (key, value) in poi_rules.TIER2_COMPOUND_REQUIREMENTS:
            req_key, req_value = poi_rules.TIER2_COMPOUND_REQUIREMENTS[(key, value)]
            tags[req_key] = req_value
        assert poi_rules.matched_tag(tags, include_tier2=True) == ((key, value), 2)


def test_tier1_and_tier2_tag_sets_are_disjoint():
    assert poi_rules.TIER1_TAGS.isdisjoint(poi_rules.TIER2_TAGS)
