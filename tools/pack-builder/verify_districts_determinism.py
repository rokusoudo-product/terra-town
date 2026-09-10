#!/usr/bin/env python3
"""extract_districts.py を2回実行し、決定論を検証する（Issue #86・T041受け入れ基準）。

`verify_determinism.py`（地形属性・Issue #38）と同じ考え方: 同一入力から
`district`（区画ポリゴン）・`hex_district`（帰属判定）を2回生成し、内容が
完全一致することを確認する。

`extract_districts.py` 自身も実行のたびに `verify_topology`（隣接ポリゴン間の
隙間・重なりチェック）を行っているため、本スクリプトはそれに加えて
「2回の生成結果が一致するか」という決定論の観点のみを追加で検証する。

使い方:
    python verify_districts_determinism.py
"""

from __future__ import annotations

import sqlite3
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
PY = str(HERE / ".venv" / "bin" / "python")
EXTRACT = str(HERE / "extract_districts.py")
PACK_SQLITE = str(HERE / "out" / "pack.sqlite")


def run_once(out_name: str) -> Path:
    out_path = HERE / "out" / out_name
    subprocess.run(
        [PY, EXTRACT, "--pack-sqlite", PACK_SQLITE, "--out", str(out_path)],
        check=True,
        cwd=str(HERE),
    )
    return out_path


def district_rows(path: Path) -> set[tuple]:
    conn = sqlite3.connect(str(path))
    try:
        return set(
            conn.execute(
                "SELECT district_id, name, prefecture_name, county_name, geometry_geojson FROM district"
            ).fetchall()
        )
    finally:
        conn.close()


def hex_district_rows(path: Path) -> set[tuple]:
    conn = sqlite3.connect(str(path))
    try:
        return set(conn.execute("SELECT hex_id, district_id FROM hex_district").fetchall())
    finally:
        conn.close()


def main() -> None:
    if not Path(PACK_SQLITE).exists():
        print(
            f"[verify_districts_determinism] {PACK_SQLITE} not found. "
            "先に classify_terrain.py を実行してください。",
            file=sys.stderr,
        )
        sys.exit(1)

    print("[verify_districts_determinism] run 1 ...")
    p1 = run_once("districts_determinism_run1.sqlite")
    print("[verify_districts_determinism] run 2 ...")
    p2 = run_once("districts_determinism_run2.sqlite")

    d1, d2 = district_rows(p1), district_rows(p2)
    hd1, hd2 = hex_district_rows(p1), hex_district_rows(p2)

    d_diff = d1.symmetric_difference(d2)
    hd_diff = hd1.symmetric_difference(hd2)

    print(f"[verify_districts_determinism] district rows: run1={len(d1)} run2={len(d2)} diff={len(d_diff)}")
    print(
        f"[verify_districts_determinism] hex_district rows: run1={len(hd1)} run2={len(hd2)} diff={len(hd_diff)}"
    )

    if d_diff or hd_diff:
        print("[verify_districts_determinism] FAIL: 2回の生成結果が一致しませんでした。")
        for row in list(d_diff)[:5]:
            print("  district diff:", row[:4], "...")
        for row in list(hd_diff)[:20]:
            print("  hex_district diff:", row)
        sys.exit(1)

    print("[verify_districts_determinism] PASS: district / hex_district とも2回の生成で完全一致しました。")


if __name__ == "__main__":
    main()
