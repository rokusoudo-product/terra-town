#!/usr/bin/env python3
"""同じ入力から classify_terrain.py を2回実行し、hex_terrain の内容が完全一致することを
確認する（plan.md §4 の前提「資材分類の決定論」の検証。Issue #38 受け入れ基準）。

使い方:
    python verify_determinism.py

`classify_terrain.py` を2回（別々の出力ファイルへ）実行し、
両方の hex_terrain テーブルの (hex_id, terrain_type, feature_id, cell_count) の集合を
比較する。完全一致すれば exit code 0、差分があれば内容を表示して exit code 1。
"""

from __future__ import annotations

import sqlite3
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
PY = str(HERE / ".venv" / "bin" / "python")
CLASSIFY = str(HERE / "classify_terrain.py")


def run_once(out_name: str) -> Path:
    out_path = HERE / "out" / out_name
    subprocess.run([PY, CLASSIFY, "--out", str(out_path)], check=True, cwd=str(HERE))
    return out_path


def hex_rows(path: Path) -> set[tuple]:
    conn = sqlite3.connect(str(path))
    try:
        # boundary_geojson（Issue #105）も比較対象に含める。境界計算
        # （hex_geometry.hex_boundary_lonlat）も決定論的であるべきことを検証するため。
        return set(
            conn.execute(
                "SELECT hex_id, terrain_type, feature_id, cell_count, boundary_geojson "
                "FROM hex_terrain"
            ).fetchall()
        )
    finally:
        conn.close()


def main() -> None:
    print("[verify_determinism] run 1 ...")
    p1 = run_once("determinism_run1.sqlite")
    print("[verify_determinism] run 2 ...")
    p2 = run_once("determinism_run2.sqlite")

    rows1 = hex_rows(p1)
    rows2 = hex_rows(p2)

    diff = rows1.symmetric_difference(rows2)
    print(f"[verify_determinism] run1 hex rows: {len(rows1)}")
    print(f"[verify_determinism] run2 hex rows: {len(rows2)}")
    print(f"[verify_determinism] symmetric diff: {len(diff)}")

    if diff:
        print("[verify_determinism] FAIL: hex_terrain の内容が2回の実行で一致しませんでした。")
        for row in list(diff)[:20]:
            print("  ", row)
        sys.exit(1)

    print("[verify_determinism] PASS: 2回の生成で hex_terrain の内容が完全に一致しました。")


if __name__ == "__main__":
    main()
