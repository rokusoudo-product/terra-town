#!/usr/bin/env python3
"""tools/pack-builder/slim_pack_for_bundle.py — 同梱用に軽量化したSQLiteを作る（Issue #85・T044）。

`classify_terrain.py` の出力（`out/pack.sqlite`）は `cell_terrain`（生成過程の中間データ。
細分グリッドセル単位、5m四方で約100万行）を含むため約63MB になる。しかし `app/assets/`
に同梱する必要があるのは `hex_terrain`（H3ヘクス単位に集約済みの最終結果。
`boundary_geojson` 列＝ fog of war 用のヘクス境界を含む・Issue #105）と `pack_meta`
だけであり、`cell_terrain` を落とすと大幅に縮む
（実測: `specs/001-mvp/research.md` §8.1・§8.10「`hex_terrain` テーブルだけを残した場合の
サイズ」。§8.10 は `boundary_geojson` 追加後の実測値）。

`cell_terrain` は抜き取り検証（`spot_check_samples.py`）や将来のデバッグに使うため
`classify_terrain.py` 側では引き続きデフォルトで出力する。本スクリプトは
「検証用のフルサイズ出力」と「同梱用の軽量出力」を分離するための後段ステップ。

使い方:
    ./.venv/bin/python slim_pack_for_bundle.py [--input out/pack.sqlite] [--out out/region_pack.sqlite]
"""

from __future__ import annotations

import argparse
import sqlite3
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent


def log(msg: str) -> None:
    print(f"[slim_pack_for_bundle] {msg}", file=sys.stderr, flush=True)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", default=str(HERE / "out" / "pack.sqlite"))
    parser.add_argument("--out", default=str(HERE / "out" / "region_pack.sqlite"))
    args = parser.parse_args()

    input_path = Path(args.input)
    out_path = Path(args.out)

    if not input_path.exists():
        log(f"input not found: {input_path}. 先に classify_terrain.py を実行してください。")
        sys.exit(1)

    out_path.parent.mkdir(parents=True, exist_ok=True)
    if out_path.exists():
        out_path.unlink()

    src = sqlite3.connect(str(input_path))
    dst = sqlite3.connect(str(out_path))
    try:
        # ATTACH して hex_terrain / pack_meta だけを新しいDBにコピーする。
        # cell_terrain（生成過程の中間データ）は同梱対象外（本ファイル docstring 参照）。
        dst.execute("ATTACH DATABASE ? AS src", (str(input_path),))
        # boundary_geojson（Issue #105・案A）: fog of war 用のヘクス境界。
        # 同梱パックにも含める（`location/` が実行時に読むため。cell_terrain と異なり
        # 生成過程の中間データではなく、fog of war の描画に必須のデータのため落とさない）。
        dst.execute(
            """
            CREATE TABLE hex_terrain (
                hex_id INTEGER PRIMARY KEY,
                terrain_type TEXT NOT NULL,
                feature_id INTEGER NOT NULL,
                cell_count INTEGER NOT NULL,
                boundary_geojson TEXT NOT NULL
            )
            """
        )
        dst.execute("CREATE UNIQUE INDEX idx_hex_terrain_feature_id ON hex_terrain(feature_id)")
        dst.execute("CREATE TABLE pack_meta (key TEXT PRIMARY KEY, value TEXT)")
        dst.execute("INSERT INTO hex_terrain SELECT * FROM src.hex_terrain")
        dst.execute("INSERT INTO pack_meta SELECT * FROM src.pack_meta")
        dst.execute("INSERT OR REPLACE INTO pack_meta (key, value) VALUES ('bundle_kind', 'region_pack_slim')")
        dst.execute(
            "INSERT OR REPLACE INTO pack_meta (key, value) VALUES ('bundle_note', ?)",
            ("cell_terrain を除いた同梱用サブセット（tools/pack-builder/slim_pack_for_bundle.py）",),
        )
        dst.commit()
        dst.execute("DETACH DATABASE src")
        dst.execute("VACUUM")
    finally:
        src.close()
        dst.close()

    hex_count = sqlite3.connect(str(out_path)).execute("SELECT COUNT(*) FROM hex_terrain").fetchone()[0]
    out_size = out_path.stat().st_size
    in_size = input_path.stat().st_size
    log(
        f"DONE. {input_path} ({in_size} bytes) -> {out_path} ({out_size} bytes, "
        f"{out_size / in_size * 100:.1f}%). hex_terrain rows={hex_count}"
    )


if __name__ == "__main__":
    main()
