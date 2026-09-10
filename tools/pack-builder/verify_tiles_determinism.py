#!/usr/bin/env python3
"""同じ入力から build_vector_tiles.sh（Planetiler）を2回実行し、生成される
MBTiles の tiles テーブルの内容が完全一致することを確認する（Issue #85・T045）。

`verify_determinism.py`（`classify_terrain.py` の決定論検証）と同じ考え方を、
ベクタタイル生成（Planetiler）側にも適用したもの。

比較方法（バイト単位のファイル比較ではなく内容比較にしている理由）:
    MBTilesはSQLiteファイルであり、同じ内容でも書き込み順序やSQLiteの内部ページ
    レイアウトの違いでバイト列が変わりうる。そのため
    `(zoom_level, tile_column, tile_row, sha256(tile_data))` の集合として比較する。
    `metadata` テーブルは `planetiler:buildtime`（Planetilerのビルド日時。Planetiler
    本体のビルド時刻でありエリア生成時刻ではないため通常は不変だが、Planetilerの
    バージョンを上げた場合は変わりうる）以外のキーで比較する。

使い方:
    ./.venv/bin/python verify_tiles_determinism.py
"""

from __future__ import annotations

import hashlib
import sqlite3
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent

# metadata の比較から除外するキー（Planetiler本体のビルド時刻等、エリア生成のたびに
# 変わることが想定されていない値だが、念のため実行環境依存の値として除外する）。
METADATA_KEYS_TO_IGNORE = {"planetiler:buildtime", "planetiler:githash"}


def run_once(out_name: str) -> Path:
    out_path = HERE / "out" / out_name
    subprocess.run(
        ["bash", "build_vector_tiles.sh", str(out_path)],
        check=True,
        cwd=str(HERE),
    )
    return out_path


def tile_rows(path: Path) -> set[tuple[int, int, int, str]]:
    conn = sqlite3.connect(str(path))
    try:
        rows = conn.execute("SELECT zoom_level, tile_column, tile_row, tile_data FROM tiles").fetchall()
        return {
            (z, x, y, hashlib.sha256(data).hexdigest())
            for z, x, y, data in rows
        }
    finally:
        conn.close()


def metadata_dict(path: Path) -> dict[str, str]:
    conn = sqlite3.connect(str(path))
    try:
        rows = conn.execute("SELECT name, value FROM metadata").fetchall()
        return {k: v for k, v in rows if k not in METADATA_KEYS_TO_IGNORE}
    finally:
        conn.close()


def main() -> None:
    print("[verify_tiles_determinism] run 1 ...")
    p1 = run_once("tiles_determinism_run1.mbtiles")
    print("[verify_tiles_determinism] run 2 ...")
    p2 = run_once("tiles_determinism_run2.mbtiles")

    rows1 = tile_rows(p1)
    rows2 = tile_rows(p2)
    diff = rows1.symmetric_difference(rows2)

    print(f"[verify_tiles_determinism] run1 tiles: {len(rows1)}")
    print(f"[verify_tiles_determinism] run2 tiles: {len(rows2)}")
    print(f"[verify_tiles_determinism] tile symmetric diff: {len(diff)}")

    meta1 = metadata_dict(p1)
    meta2 = metadata_dict(p2)
    meta_diff_keys = {
        k
        for k in set(meta1) | set(meta2)
        if meta1.get(k) != meta2.get(k)
    }
    print(f"[verify_tiles_determinism] metadata diff keys (除外キー以外): {meta_diff_keys or 'なし'}")

    if diff or meta_diff_keys:
        print("[verify_tiles_determinism] FAIL: 2回の生成で内容が一致しませんでした。")
        for row in list(diff)[:20]:
            print("  tile diff:", row)
        for k in meta_diff_keys:
            print(f"  metadata diff: {k!r}: {meta1.get(k)!r} != {meta2.get(k)!r}")
        sys.exit(1)

    print("[verify_tiles_determinism] PASS: 2回の生成でMBTilesの内容が完全に一致しました。")


if __name__ == "__main__":
    main()
