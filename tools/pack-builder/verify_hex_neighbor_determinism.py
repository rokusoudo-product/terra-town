#!/usr/bin/env python3
"""compute_hex_neighbors.py を2回実行し、決定論を検証する（Issue #152 受け入れ基準）。

`verify_determinism.py`（地形属性・Issue #38）・`verify_districts_determinism.py`
（行政区域・Issue #86）と同じ考え方: 同一入力から `hex_neighbor` を2回生成し、
内容が完全一致することを確認する。

使い方:
    python verify_hex_neighbor_determinism.py
"""

from __future__ import annotations

import sqlite3
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
PY = str(HERE / ".venv" / "bin" / "python")
COMPUTE = str(HERE / "compute_hex_neighbors.py")
PACK_SQLITE = str(HERE / "out" / "pack.sqlite")


def run_once(out_name: str) -> Path:
    out_path = HERE / "out" / out_name
    subprocess.run(
        [PY, COMPUTE, "--pack-sqlite", PACK_SQLITE, "--out", str(out_path)],
        check=True,
        cwd=str(HERE),
    )
    return out_path


def neighbor_rows(path: Path) -> set[tuple]:
    conn = sqlite3.connect(str(path))
    try:
        return set(
            conn.execute("SELECT hex_id, neighbor_count, neighbor_hex_ids FROM hex_neighbor").fetchall()
        )
    finally:
        conn.close()


def main() -> None:
    if not Path(PACK_SQLITE).exists():
        print(
            f"[verify_hex_neighbor_determinism] {PACK_SQLITE} not found. "
            "先に classify_terrain.py を実行してください。",
            file=sys.stderr,
        )
        sys.exit(1)

    print("[verify_hex_neighbor_determinism] run 1 ...")
    p1 = run_once("hex_neighbor_determinism_run1.sqlite")
    print("[verify_hex_neighbor_determinism] run 2 ...")
    p2 = run_once("hex_neighbor_determinism_run2.sqlite")

    rows1, rows2 = neighbor_rows(p1), neighbor_rows(p2)
    diff = rows1.symmetric_difference(rows2)

    print(f"[verify_hex_neighbor_determinism] run1 rows: {len(rows1)}")
    print(f"[verify_hex_neighbor_determinism] run2 rows: {len(rows2)}")
    print(f"[verify_hex_neighbor_determinism] symmetric diff: {len(diff)}")

    if diff:
        print("[verify_hex_neighbor_determinism] FAIL: hex_neighbor の内容が2回の実行で一致しませんでした。")
        for row in list(diff)[:20]:
            print("  ", row)
        sys.exit(1)

    print("[verify_hex_neighbor_determinism] PASS: 2回の生成で hex_neighbor の内容が完全に一致しました。")


if __name__ == "__main__":
    main()
