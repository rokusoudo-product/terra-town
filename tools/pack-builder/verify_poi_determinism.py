#!/usr/bin/env python3
"""extract_poi.py を2回実行し、決定論を検証する（Issue #86・T042受け入れ基準）。

`verify_determinism.py`（地形属性・Issue #38）と同じ考え方: 同一入力（同一
`area.osm.pbf`・同一設定）から `poi` テーブルを2回生成し、内容が完全一致する
ことを確認する。

使い方:
    python verify_poi_determinism.py
"""

from __future__ import annotations

import sqlite3
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
PY = str(HERE / ".venv" / "bin" / "python")
EXTRACT = str(HERE / "extract_poi.py")


def run_once(out_name: str) -> Path:
    out_path = HERE / "out" / out_name
    subprocess.run([PY, EXTRACT, "--out", str(out_path)], check=True, cwd=str(HERE))
    return out_path


def poi_rows(path: Path) -> set[tuple]:
    conn = sqlite3.connect(str(path))
    try:
        return set(conn.execute("SELECT id, lat, lon, kind, name FROM poi").fetchall())
    finally:
        conn.close()


def main() -> None:
    print("[verify_poi_determinism] run 1 ...")
    p1 = run_once("poi_determinism_run1.sqlite")
    print("[verify_poi_determinism] run 2 ...")
    p2 = run_once("poi_determinism_run2.sqlite")

    rows1 = poi_rows(p1)
    rows2 = poi_rows(p2)
    diff = rows1.symmetric_difference(rows2)

    print(f"[verify_poi_determinism] run1 poi rows: {len(rows1)}")
    print(f"[verify_poi_determinism] run2 poi rows: {len(rows2)}")
    print(f"[verify_poi_determinism] symmetric diff: {len(diff)}")

    if diff:
        print("[verify_poi_determinism] FAIL: poi の内容が2回の実行で一致しませんでした。")
        for row in list(diff)[:20]:
            print("  ", row)
        sys.exit(1)

    print("[verify_poi_determinism] PASS: 2回の生成で poi の内容が完全に一致しました。")


if __name__ == "__main__":
    main()
