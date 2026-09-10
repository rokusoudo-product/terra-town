"""OSM タグ → 名所POI 抽出ルール（Issue #86・T042）。

出典: `docs/landmark_objects.md` §2.1「一般オブジェクト（MVPの主力・大量配置の担い手）」。
本Issueで実装するのは **Tier 1（主要層）のみ**。

- Tier 1: 「名所らしさ」が明確な地物。全エリアで無条件に採用する。
- Tier 2（補完層）: 「地域内の主要層密度が§3の目標密度を下回る場合のみ採用」という
  条件付き仕様だが、目標密度自体が仮値（docs/landmark_objects.md §3.1「目標値・仮」）
  であり密度判定の実装は本Issueのスコープ外と判断した。**本Issueでは実装しない**
  （tools/pack-builder/README.md「既知の簡略化・未解決事項」に記録）。
- ボーナスオブジェクト（`is_bonus`・allowlist照合。§2.2）も同様に未実装
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
AREA_THRESHOLD_TAGS: frozenset[tuple[str, str]] = frozenset({("leisure", "park")})


def matched_tag(tags: dict[str, str]) -> tuple[str, str] | None:
    """`tags` が Tier 1 のいずれかに該当すれば (key, value) を返す。複数該当時は
    TIER1_TAGS の定義順（tourism→historic→leisure）で最初に見つかったものを採用する
    （決定論的な優先順位。docs/terrain.md §5 の優先順位付き判定と同じ考え方）。
    """
    for key, value in _ORDERED_TAGS:
        if tags.get(key) == value:
            return key, value
    return None


# frozenset はイテレーション順が不定（ハッシュ順）なため、決定論的な優先順位を
# 別途固定の tuple として保持する。
_ORDERED_TAGS: tuple[tuple[str, str], ...] = (
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

assert set(_ORDERED_TAGS) == TIER1_TAGS, "TIER1_TAGS と _ORDERED_TAGS の内容が一致していません"
