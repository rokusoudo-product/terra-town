#!/usr/bin/env python3
"""tools/pack-builder/export_hex_geojson.py — T043 の受け入れ基準
（「各ヘクス Feature の直下に整数 `id` を持つ」）を検証・可視化するための
リファレンス実装（Issue #85）。

## 位置づけ（重要）

**本スクリプトの出力（GeoJSON ファイル）はパック本体の一部ではない。**
plan.md §8 のとおり、fog of war 用の GeoJSON FeatureCollection は
`location/`（`packages/location/lib/src/map/`・tasks.md T056）が実行時に
`hex_terrain`（SQLite）から組み立てる。本スクリプトはその実装が満たすべき
「Feature 直下に整数 `id`（= `feature_id`）を持たせる」という形をオフラインで
再現・検証するための開発補助ツールであり、`app/assets/` に同梱するものではない
（同梱するのは `hex_terrain` を含む SQLite 本体。`bundle_region_pack.sh` 参照）。

## 何を検証しているか

- 各 Feature の **直下（`properties` の中ではない）** に整数 `id` を持つこと
  （`promoteId` は Android で機能しないため、これが必須 — plan.md §8・research.md §6.3）。
- `id` が `hex_terrain.feature_id` 列と一致すること。
- `id` に重複がないこと（`classify_terrain.py` の UNIQUE INDEX と整合）。
- `hex_id`（H3 index）は 2^53-1 を超えうるため、`properties` に含める場合は
  **文字列として**格納すること（JSON safe integer の範囲外。docs/terrain.md §4.4）。
  本スクリプトはその指針をそのまま実装している。

使い方:
    ./.venv/bin/python export_hex_geojson.py [--input out/pack.sqlite] [--out out/hex_features.geojson] [--limit N]
"""

from __future__ import annotations

import argparse
import json
import sqlite3
import sys
from pathlib import Path

import h3

HERE = Path(__file__).resolve().parent


def log(msg: str) -> None:
    print(f"[export_hex_geojson] {msg}", file=sys.stderr, flush=True)


def hex_boundary_geojson_coords(hex_id_int: int) -> list[list[float]]:
    """H3 セルの境界を GeoJSON Polygon 用の [lon, lat] 座標配列（閉環）にする。"""
    h3_str = h3.int_to_str(hex_id_int)
    boundary = h3.cell_to_boundary(h3_str)  # [(lat, lon), ...]
    ring = [[lon, lat] for lat, lon in boundary]
    ring.append(ring[0])  # GeoJSON Polygon は閉環（始点=終点）である必要がある
    return ring


def build_feature_collection(rows: list[tuple[int, str, int, int]]) -> dict:
    features = []
    seen_ids: set[int] = set()

    for hex_id, terrain_type, feature_id, cell_count in rows:
        if not isinstance(feature_id, int):
            raise TypeError(f"feature_id は int である必要があります: {feature_id!r}")
        if feature_id in seen_ids:
            raise ValueError(f"feature_id の重複を検出しました: {feature_id}")
        seen_ids.add(feature_id)

        features.append(
            {
                "type": "Feature",
                # ⚠️ ここが T043 の核心: Feature 直下（properties の外）に整数 id を持たせる。
                # promoteId（properties からの昇格）は Web 専用で Android では機能しない。
                "id": feature_id,
                "geometry": {
                    "type": "Polygon",
                    "coordinates": [hex_boundary_geojson_coords(hex_id)],
                },
                "properties": {
                    "terrain_type": terrain_type,
                    "cell_count": cell_count,
                    # hex_id（H3 index）は最大 2^63 未満で JSON safe integer(2^53-1)の
                    # 範囲を超えうるため、properties に含める場合は文字列で持たせる
                    # （docs/terrain.md §4.4）。feature_id への復元は
                    # hex_bridge.feature_id_to_h3() を使う（本スクリプトでは検証しない）。
                    "hex_id_str": str(hex_id),
                },
            }
        )

    return {"type": "FeatureCollection", "features": features}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", default=str(HERE / "out" / "pack.sqlite"))
    parser.add_argument("--out", default=str(HERE / "out" / "hex_features.geojson"))
    parser.add_argument(
        "--limit",
        type=int,
        default=0,
        help="出力するFeature数の上限（0=全件。動作確認用に少数だけ出したい場合に指定）",
    )
    args = parser.parse_args()

    input_path = Path(args.input)
    out_path = Path(args.out)

    if not input_path.exists():
        log(f"input not found: {input_path}. 先に classify_terrain.py を実行してください。")
        sys.exit(1)

    conn = sqlite3.connect(str(input_path))
    try:
        query = "SELECT hex_id, terrain_type, feature_id, cell_count FROM hex_terrain ORDER BY hex_id"
        if args.limit > 0:
            query += f" LIMIT {int(args.limit)}"
        rows = conn.execute(query).fetchall()
    finally:
        conn.close()

    if not rows:
        log("hex_terrain に行がありません。")
        sys.exit(1)

    log(f"{len(rows)} 件のヘクスを GeoJSON Feature に変換します ...")
    fc = build_feature_collection(rows)

    ids = [f["id"] for f in fc["features"]]
    assert all(isinstance(i, int) for i in ids), "すべての id は int であること（検証済みのはず）"
    assert len(ids) == len(set(ids)), "id に重複がないこと（検証済みのはず）"
    log(f"検証OK: 全{len(ids)}件で Feature 直下に整数 id（重複なし）を確認しました。")
    log(f"id の最大値: {max(ids)}（2^53-1 = 9007199254740991 未満であること: {max(ids) < 2**53 - 1}）")

    out_path.parent.mkdir(parents=True, exist_ok=True)
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(fc, f, ensure_ascii=False)

    log(f"書き出し完了: {out_path} ({out_path.stat().st_size} bytes)")


if __name__ == "__main__":
    main()
