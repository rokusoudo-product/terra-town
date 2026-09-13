"""OSM タグ → 名所POI 抽出ルール（Issue #86・T042。Tier 2 は Issue #158）。

出典: `docs/landmark_objects.md` §2.1「一般オブジェクト（MVPの主力・大量配置の担い手）」。

- Tier 1（主要層）: 「名所らしさ」が明確な地物。全エリアで無条件に採用する。
- Tier 2（補完層）: §2.1 は「地域内の主要層密度が§3の目標密度を下回る場合のみ採用」と
  条件付きで定義しているが、目標密度自体が仮値（§3.1「目標値・仮」）であり、
  自動密度判定は Issue #158（2026-09-13代表決定）でも実装しないと決まった。
  代わりに `config.POI_INCLUDE_TIER2` の設定値で一律に有効/無効を切り替える
  （本Issueで生成するパックでは有効。tools/pack-builder/README.md
  「既知の簡略化・未解決事項」に記録）。
- 1つの地物が Tier 1・Tier 2 の両方に該当する場合は **Tier 1 の kind を採用する**
  （`matched_tag` が Tier 1 を先に判定するため自然に満たされる。Issue #158代表決定）。
- ボーナスオブジェクト（`is_bonus`・allowlist照合。§2.2）は引き続き未実装
  （allowlistの整備自体がplan/tasks工程の宿題として明記されている。§7）。

`kind` は `docs/landmark_objects.md` §5 の `collection.kind`（「OSM タグ由来。例:
`tourism=attraction` 等」）に合わせ、マッチしたタグの `key=value` 文字列とする。
"""

from __future__ import annotations

# (key, value) のタプル集合。Area判定・Node判定で共通に使う。
TIER1_TAGS: frozenset[tuple[str, str]] = frozenset(
    {
        ("tourism", "attraction"),
        ("tourism", "viewpoint"),
        ("tourism", "artwork"),
        ("tourism", "museum"),
        ("tourism", "gallery"),
        ("tourism", "zoo"),
        ("tourism", "theme_park"),
        ("historic", "monument"),
        ("historic", "memorial"),
        ("historic", "castle"),
        ("historic", "ruins"),
        ("historic", "archaeological_site"),
        # leisure=park のみ「一定面積以上」の条件付き（config.POI_PARK_MIN_AREA_M2）。
        ("leisure", "park"),
    }
)

# 面積条件が付くタグ（config.POI_PARK_MIN_AREA_M2 未満は採用しない）。
# Tier 2 には docs/landmark_objects.md §2.1 上、面積条件付きのタグは無い。
AREA_THRESHOLD_TAGS: frozenset[tuple[str, str]] = frozenset({("leisure", "park")})

# docs/landmark_objects.md §2.1 補完層（Tier 2）のタグ。
# `natural=tree` のみ「`denotation=natural_monument` 等の名木指定のみ」という
# 追加条件付き（`TIER2_COMPOUND_REQUIREMENTS` 参照）。
TIER2_TAGS: frozenset[tuple[str, str]] = frozenset(
    {
        ("amenity", "place_of_worship"),
        ("historic", "wayside_cross"),
        ("historic", "milestone"),
        ("man_made", "tower"),
        ("man_made", "lighthouse"),
        ("natural", "tree"),
        ("tourism", "picnic_site"),
        ("tourism", "information"),
    }
)

# `natural=tree` は「名木指定のみ」（§2.1）という追加のAND条件を持つ。
# OSMの名木指定タグは複数の慣習的な表現がありうるが（例: `denotation=natural_monument`
# 以外に地域独自タグも存在しうる）、§2.1本文が明示するのは`denotation=natural_monument`
# のみであり、それ以外を推測で追加すると「実在の地物に限定」（§2.1）という制約に対して
# 過剰抽出のリスクがある。本Issueでは`denotation=natural_monument`のみを対象とする
# 判断とした（tools/pack-builder/README.md「既知の簡略化・未解決事項」に記録）。
TIER2_COMPOUND_REQUIREMENTS: dict[tuple[str, str], tuple[str, str]] = {
    ("natural", "tree"): ("denotation", "natural_monument"),
}


def matched_tag(
    tags: dict[str, str], include_tier2: bool = False
) -> tuple[tuple[str, str], int] | None:
    """`tags` が Tier 1/Tier 2 のいずれかに該当すれば `((key, value), tier)` を返す。

    - Tier 1 を必ず先に判定する。複数該当時は `_ORDERED_TIER1_TAGS` の定義順
      （tourism→historic→leisure）で最初に見つかったものを採用する（決定論的な
      優先順位。docs/terrain.md §5 の優先順位付き判定と同じ考え方）。
    - Tier 1 に該当せず `include_tier2=True` の場合のみ、`_ORDERED_TIER2_TAGS` を
      同様の優先順位で判定する。これにより「Tier 1・Tier 2 の両方に該当する地物は
      Tier 1 の kind を採用する」（Issue #158代表決定）が自然に満たされる。
    - `natural=tree` は `TIER2_COMPOUND_REQUIREMENTS` の追加条件（`denotation`）を
      満たさない限りマッチしない。
    """
    for key, value in _ORDERED_TIER1_TAGS:
        if tags.get(key) == value:
            return (key, value), 1

    if not include_tier2:
        return None

    for key, value in _ORDERED_TIER2_TAGS:
        if tags.get(key) != value:
            continue
        requirement = TIER2_COMPOUND_REQUIREMENTS.get((key, value))
        if requirement is not None:
            req_key, req_value = requirement
            if tags.get(req_key) != req_value:
                continue
        return (key, value), 2

    return None


# frozenset はイテレーション順が不定（ハッシュ順）なため、決定論的な優先順位を
# 別途固定の tuple として保持する。
_ORDERED_TIER1_TAGS: tuple[tuple[str, str], ...] = (
    ("tourism", "attraction"),
    ("tourism", "viewpoint"),
    ("tourism", "artwork"),
    ("tourism", "museum"),
    ("tourism", "gallery"),
    ("tourism", "zoo"),
    ("tourism", "theme_park"),
    ("historic", "monument"),
    ("historic", "memorial"),
    ("historic", "castle"),
    ("historic", "ruins"),
    ("historic", "archaeological_site"),
    ("leisure", "park"),
)

assert set(_ORDERED_TIER1_TAGS) == TIER1_TAGS, (
    "TIER1_TAGS と _ORDERED_TIER1_TAGS の内容が一致していません"
)

# docs/landmark_objects.md §2.1 に列挙された順（amenity→historic→man_made→natural→tourism）。
_ORDERED_TIER2_TAGS: tuple[tuple[str, str], ...] = (
    ("amenity", "place_of_worship"),
    ("historic", "wayside_cross"),
    ("historic", "milestone"),
    ("man_made", "tower"),
    ("man_made", "lighthouse"),
    ("natural", "tree"),
    ("tourism", "picnic_site"),
    ("tourism", "information"),
)

assert set(_ORDERED_TIER2_TAGS) == TIER2_TAGS, (
    "TIER2_TAGS と _ORDERED_TIER2_TAGS の内容が一致していません"
)
