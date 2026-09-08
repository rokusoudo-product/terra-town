#!/usr/bin/env python3
"""地形タイプごとに数ヘクスを抽出し、実地図と突き合わせるための抜き取り検証サンプルを出力する。

Issue #38 受け入れ基準:
  「docs/terrain.md §2 の地形タイプごとに、実地図と突き合わせた抜き取り検証の結果が
   specs/001-mvp/research.md に記載されている（タイプ・ヘクス・期待値・実際値・判定）」

本スクリプトは「サンプルの抽出」だけを行う（実際の目視確認は研究者が行い、
結果は research.md に手動で記録する）。
"""

from __future__ import annotations

import sqlite3
from pathlib import Path

import h3

HERE = Path(__file__).resolve().parent
DB = HERE / "out" / "pack.sqlite"
SAMPLES_PER_TYPE = 3


def main() -> None:
    conn = sqlite3.connect(str(DB))
    types = [r[0] for r in conn.execute("SELECT DISTINCT terrain_type FROM hex_terrain")]
    print(f"検出された地形タイプ: {sorted(types)}")

    # Issue #70（2026-09-08）で地形タイプから farmland・urban を除外し5種にした。
    all_types = ["sea", "waterside", "mountain", "forest", "vacant_lot"]
    for t in all_types:
        rows = conn.execute(
            "SELECT hex_id, feature_id, cell_count FROM hex_terrain WHERE terrain_type = ? "
            "ORDER BY cell_count DESC LIMIT ?",
            (t, SAMPLES_PER_TYPE),
        ).fetchall()
        print(f"\n=== {t} ({len(rows)} サンプル / 全 "
              f"{conn.execute('SELECT COUNT(*) FROM hex_terrain WHERE terrain_type=?', (t,)).fetchone()[0]} ヘクス) ===")
        if not rows:
            print("  (このエリアには該当ヘクスが存在しない)")
            continue
        for hex_id, feature_id, cell_count in rows:
            lat, lon = h3.cell_to_latlng(h3.int_to_str(hex_id))
            osm_url = f"https://www.openstreetmap.org/#map=19/{lat:.6f}/{lon:.6f}"
            print(f"  hex_id={hex_id} feature_id={feature_id} cell_count={cell_count} "
                  f"center=({lat:.6f},{lon:.6f}) {osm_url}")


if __name__ == "__main__":
    main()
