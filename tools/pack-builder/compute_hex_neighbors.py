#!/usr/bin/env python3
"""tools/pack-builder/compute_hex_neighbors.py — ヘクス隣接関係の事前計算（Issue #152）。

入力: `classify_terrain.py` の出力（`out/pack.sqlite` の `hex_terrain`。パックに
      含まれるヘクス集合の正。`extract_districts.py` と同じ入力を再利用する）
出力: `<out>/hex_neighbor.sqlite`（テーブル: hex_neighbor, pack_meta）

処理の流れ（`docs/opening_points.md` §5.2・2026-09-13代表決定〔Issue #151/#152〕）:
  1. `hex_terrain` の全ヘクスについて、H3（`h3.grid_ring(h, 1)`・距離1の隣接候補）を
     計算する。
  2. 候補のうち、パックに含まれないヘクス（パック範囲外）を除外し、昇順に並べる
     （`hex_neighbors.filter_and_sort_intra_pack_neighbors`）。
  3. 全ヘクス（隣接が0件になったヘクスがあっても）について `hex_neighbor` に
     1行を書き込む。これにより `set(hex_neighbor.hex_id) == set(hex_terrain.hex_id)`
     が常に成立し、`slim_pack_for_bundle.py`（Issue #94/#152の統合先）が
     この等価性を前提に整合性チェックできる。

決定論: H3の隣接計算はセル座標のみに依存する純関数であり、実行順・乱数に依存しない。
`verify_hex_neighbor_determinism.py` で実際に2回生成して確認する。

対称性: パック範囲内に制限した隣接関係は構造的に対称になる
（AがBを隣接に持てば、BもAを隣接に持つ。H3のグリッドが平面的〔隣接関係が
対称なグラフ〕であるため）。本スクリプトは実データに対してこれを実行時に検証し、
崩れていれば失敗する（`hex_neighbors.py`のロジック不備の早期検出のため）。
"""

from __future__ import annotations

import argparse
import json
import sqlite3
import sys
import time
from pathlib import Path

import hex_neighbors as hn

import config

HERE = Path(__file__).resolve().parent


def log(msg: str) -> None:
    print(f"[compute_hex_neighbors] {msg}", file=sys.stderr, flush=True)


def read_hex_ids(pack_sqlite_path: Path) -> list[int]:
    conn = sqlite3.connect(str(pack_sqlite_path))
    try:
        return [row[0] for row in conn.execute("SELECT hex_id FROM hex_terrain ORDER BY hex_id")]
    finally:
        conn.close()


def compute_all_neighbors(hex_ids: list[int]) -> dict[int, list[int]]:
    hex_id_set = set(hex_ids)
    result: dict[int, list[int]] = {}
    for hex_id in hex_ids:
        candidates = hn.h3_ring_neighbors(hex_id)
        result[hex_id] = hn.filter_and_sort_intra_pack_neighbors(hex_id, candidates, hex_id_set)
    return result


def verify_symmetry(neighbors: dict[int, list[int]]) -> None:
    """パック範囲内に制限した隣接関係が対称であることを検証する（本ファイルdocstring参照）。"""
    broken: list[tuple[int, int]] = []
    for hex_id, neighbor_ids in neighbors.items():
        for neighbor_id in neighbor_ids:
            if hex_id not in neighbors.get(neighbor_id, ()):
                broken.append((hex_id, neighbor_id))
    if broken:
        raise AssertionError(
            f"隣接関係が対称ではありません（{len(broken)}件）。最初の5件: {broken[:5]}。"
            "hex_neighbors.py のロジックを確認してください。"
        )


def write_sqlite(out_path: Path, neighbors: dict[int, list[int]], meta: dict[str, str]) -> None:
    out_path.parent.mkdir(parents=True, exist_ok=True)
    if out_path.exists():
        out_path.unlink()

    conn = sqlite3.connect(str(out_path))
    try:
        conn.execute(
            """
            CREATE TABLE hex_neighbor (
                hex_id INTEGER PRIMARY KEY,
                neighbor_count INTEGER NOT NULL,
                neighbor_hex_ids TEXT NOT NULL
            )
            """
        )
        conn.execute("CREATE TABLE pack_meta (key TEXT PRIMARY KEY, value TEXT)")

        # hex_id昇順で安定ソートして書き込む（classify_terrain.py/extract_districts.py と同じ方針）。
        for hex_id in sorted(neighbors):
            neighbor_ids = neighbors[hex_id]
            conn.execute(
                "INSERT INTO hex_neighbor (hex_id, neighbor_count, neighbor_hex_ids) VALUES (?, ?, ?)",
                (hex_id, len(neighbor_ids), json.dumps(neighbor_ids)),
            )

        conn.executemany("INSERT INTO pack_meta (key, value) VALUES (?, ?)", list(meta.items()))
        conn.commit()
    finally:
        conn.close()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pack-sqlite", default=str(HERE / config.OUT_DIR / "pack.sqlite"))
    parser.add_argument("--out", default=str(HERE / config.OUT_DIR / "hex_neighbor.sqlite"))
    args = parser.parse_args()

    pack_sqlite_path = Path(args.pack_sqlite)
    out_path = Path(args.out)

    if not pack_sqlite_path.exists():
        log(f"{pack_sqlite_path} not found. 先に classify_terrain.py を実行してください。")
        sys.exit(1)

    t0 = time.perf_counter()

    log(f"reading hex set from {pack_sqlite_path} ...")
    hex_ids = read_hex_ids(pack_sqlite_path)
    log(f"  {len(hex_ids)} hexes")

    log("computing H3 grid_ring(k=1) neighbors, restricted to the pack's hex set ...")
    neighbors = compute_all_neighbors(hex_ids)

    log("verifying symmetry of the intra-pack-restricted neighbor graph ...")
    verify_symmetry(neighbors)
    log("  symmetry OK")

    neighbor_counts = [len(v) for v in neighbors.values()]
    edge_hex_count = sum(1 for c in neighbor_counts if c < 6)
    total_edges = sum(neighbor_counts)
    log(
        f"neighbor_count stats: min={min(neighbor_counts)} max={max(neighbor_counts)} "
        f"edge_hex_count(<6)={edge_hex_count} total_directed_edges={total_edges}"
    )

    elapsed = time.perf_counter() - t0

    meta = {
        "hex_neighbor_method": "h3.grid_ring(k=1)。パック範囲外の候補は除外（README「ヘクス隣接関係」参照）",
        "hex_neighbor_hex_count": str(len(hex_ids)),
        "hex_neighbor_edge_hex_count": str(edge_hex_count),
        "hex_neighbor_total_directed_edges": str(total_edges),
        "hex_neighbor_min_count": str(min(neighbor_counts)) if neighbor_counts else "0",
        "hex_neighbor_max_count": str(max(neighbor_counts)) if neighbor_counts else "0",
        "generated_at_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "generation_seconds": f"{elapsed:.3f}",
        "h3_py_version": _pkg_version("h3"),
    }

    log(f"writing SQLite -> {out_path}")
    write_sqlite(out_path, neighbors, meta)

    out_size = out_path.stat().st_size
    log(f"DONE in {elapsed:.2f}s. hexes={len(hex_ids)} out_size={out_size} bytes")
    print(json.dumps({**meta, "out_size_bytes": out_size, "out_path": str(out_path)}, ensure_ascii=False, indent=2))


def _pkg_version(name: str) -> str:
    try:
        import importlib.metadata as im

        return im.version(name)
    except Exception:
        return "unknown"


if __name__ == "__main__":
    main()
