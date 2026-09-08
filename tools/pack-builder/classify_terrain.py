#!/usr/bin/env python3
"""tools/pack-builder/classify_terrain.py — Issue #38 最小プロトタイプ本体。

入力: config.AREA_PBF_PATH（osmium extract 済みの1エリア分の .osm.pbf。
      事前に `bash extract_area.sh` 等で作成しておくこと）
出力: <out>/pack.sqlite （テーブル: cell_terrain, hex_terrain, pack_meta）

処理の流れ（docs/terrain.md §4・§5、plan.md §4 に対応）:
  1. OSM抽出データから、地形判定に関係するタグを持つ Area（閉領域）/ Way（線）/
     Node（点）を集める
  2. docs/terrain.md §5 の優先順位でタグを地形タイプに割り当て、優先度ごとに
     ジオメトリを合成（union）する
  3. 対象エリアをメートル単位の細分グリッドセル（config.CELL_SIZE_M）に敷き詰め、
     各セルの中心点がどの優先度ジオメトリに含まれるかを優先度が高い順に判定する
     （= cell_terrain）
  4. 各セルの中心点の緯度経度から H3 index（config.H3_RESOLUTION）を求め、
     セルをヘクスごとにグルーピングし、多数決で1ヘクス1地形タイプに集約する
     （= hex_terrain。同数の場合は優先度が高い方を採用する決定論的なタイブレーク）

決定論: OSM入力・設定が同じなら、上記のどのステップも実行順・乱数に依存しない
純粋な集合演算・幾何演算・多数決であるため、出力は入力に対して一意に決まる。
`verify_determinism.py` で実際に2回生成して確認している。
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import platform
import sqlite3
import sys
import time
from collections import Counter, defaultdict
from pathlib import Path

import h3
import numpy as np
import osmium
import shapely
import shapely.wkb

import config
import terrain_rules as rules
from hex_bridge import h3_to_feature_id, header_bits_of
from local_projection import LocalProjection

HERE = Path(__file__).resolve().parent


def log(msg: str) -> None:
    print(f"[classify_terrain] {msg}", file=sys.stderr, flush=True)


def load_geometries(pbf_path: Path, proj: LocalProjection) -> dict[int, list]:
    """OSM pbf から優先度別のジオメトリ一覧（ローカル平面座標）を作る。"""
    wkbfab = osmium.geom.WKBFactory()
    buckets: dict[int, list] = {p: [] for p in rules.TERRAIN_BY_PRIORITY}

    n_nodes = n_ways = n_areas = 0
    n_area_hits = n_way_hits = n_node_hits = 0

    fp = osmium.FileProcessor(str(pbf_path)).with_areas()
    for obj in fp:
        if obj.is_area():
            n_areas += 1
            tags = dict(obj.tags)
            if not tags:
                continue
            priority = rules.classify_area_tags(tags)
            if priority is None:
                continue
            try:
                wkb_hex = wkbfab.create_multipolygon(obj)
            except RuntimeError as exc:
                log(f"  skip area id={obj.orig_id()} (wkb error: {exc})")
                continue
            geom = shapely.wkb.loads(bytes.fromhex(wkb_hex))
            if not geom.is_valid:
                geom = geom.buffer(0)
            geom_m = proj.project_geom(geom)
            buckets[priority].append(geom_m)
            n_area_hits += 1
        elif obj.is_way() and not obj.is_area():
            n_ways += 1
            tags = dict(obj.tags)
            if not tags:
                continue
            priority = rules.classify_way_tags(tags)
            if priority is None:
                continue
            try:
                wkb_hex = wkbfab.create_linestring(obj)
            except RuntimeError as exc:
                log(f"  skip way id={obj.id} (wkb error: {exc})")
                continue
            line = shapely.wkb.loads(bytes.fromhex(wkb_hex))
            line_m = proj.project_geom(line)
            geom_m = line_m.buffer(rules.WATERWAY_LINE_BUFFER_M)
            buckets[priority].append(geom_m)
            n_way_hits += 1
        elif obj.is_node():
            n_nodes += 1
            tags = dict(obj.tags)
            if not tags:
                continue
            priority = rules.classify_point_tags(tags)
            if priority is None:
                continue
            pt = shapely.geometry.Point(obj.location.lon, obj.location.lat)
            pt_m = proj.project_geom(pt)
            geom_m = pt_m.buffer(rules.MOUNTAIN_PEAK_BUFFER_M)
            buckets[priority].append(geom_m)
            n_node_hits += 1

    log(
        f"OSM objects scanned: nodes={n_nodes} ways={n_ways} areas={n_areas} "
        f"| terrain-tagged: area={n_area_hits} way={n_way_hits} node={n_node_hits}"
    )
    return buckets


def union_buckets(buckets: dict[int, list]) -> dict[int, object]:
    unioned = {}
    for priority, geoms in buckets.items():
        if not geoms:
            unioned[priority] = None
            continue
        merged = shapely.union_all(geoms)
        shapely.prepare(merged)
        unioned[priority] = merged
    return unioned


def build_grid(proj: LocalProjection) -> tuple[np.ndarray, np.ndarray, np.ndarray, np.ndarray]:
    """対象bboxをローカル平面座標のグリッドに敷き詰め、セル中心の (x_m, y_m, lon, lat) を返す。"""
    x_min, y_min = proj.to_xy(config.BBOX_LON_MIN, config.BBOX_LAT_MIN)
    x_max, y_max = proj.to_xy(config.BBOX_LON_MAX, config.BBOX_LAT_MAX)

    n_cols = int(math.floor((float(x_max) - float(x_min)) / config.CELL_SIZE_M))
    n_rows = int(math.floor((float(y_max) - float(y_min)) / config.CELL_SIZE_M))

    xs = float(x_min) + (np.arange(n_cols) + 0.5) * config.CELL_SIZE_M
    ys = float(y_min) + (np.arange(n_rows) + 0.5) * config.CELL_SIZE_M
    grid_x, grid_y = np.meshgrid(xs, ys)
    grid_x = grid_x.ravel()
    grid_y = grid_y.ravel()

    lon, lat = proj.to_lonlat(grid_x, grid_y)
    log(f"grid: {n_cols} x {n_rows} = {grid_x.size} cells (cell size = {config.CELL_SIZE_M}m)")
    return grid_x, grid_y, np.asarray(lon), np.asarray(lat)


def classify_cells(grid_x: np.ndarray, grid_y: np.ndarray, unioned: dict[int, object]) -> np.ndarray:
    """各セル中心点の優先度（int）を決める。未分類は PRIORITY_VACANT_LOT（フォールバック）。"""
    n = grid_x.size
    result = np.full(n, rules.PRIORITY_VACANT_LOT, dtype=np.int8)
    classified = np.zeros(n, dtype=bool)

    points = shapely.points(grid_x, grid_y)

    for priority in sorted(unioned):
        if priority == rules.PRIORITY_VACANT_LOT:
            continue
        geom = unioned[priority]
        if geom is None:
            continue
        remaining_idx = np.nonzero(~classified)[0]
        if remaining_idx.size == 0:
            break
        hits = shapely.contains(geom, points[remaining_idx])
        hit_idx = remaining_idx[hits]
        result[hit_idx] = priority
        classified[hit_idx] = True
        log(
            f"  priority {priority} ({rules.TERRAIN_BY_PRIORITY[priority]}): "
            f"{hit_idx.size} cells newly classified "
            f"({classified.sum()}/{n} total so far)"
        )

    return result


def aggregate_to_hexes(
    lon: np.ndarray, lat: np.ndarray, cell_priority: np.ndarray
) -> tuple[dict[int, tuple[str, int, Counter]], list[tuple]]:
    """セル単位の判定結果をH3ヘクス単位に多数決集約する。

    戻り値:
      hex_result: {h3_int: (terrain_type, winning_priority, Counter(priority -> count))}
      cell_rows: [(cell_index, h3_int, lon, lat, terrain_type), ...]  (cell_terrain 用)
    """
    hex_votes: dict[int, Counter] = defaultdict(Counter)
    cell_rows = []

    for i in range(lon.size):
        h3_int = h3.str_to_int(h3.latlng_to_cell(float(lat[i]), float(lon[i]), config.H3_RESOLUTION))
        priority = int(cell_priority[i])
        hex_votes[h3_int][priority] += 1
        cell_rows.append((i, h3_int, float(lon[i]), float(lat[i]), rules.TERRAIN_BY_PRIORITY[priority]))

    hex_result = {}
    for h3_int, counter in hex_votes.items():
        # 多数決（セル数最大）。同数の場合は優先度番号が小さい方（=より希少・特徴的な地形）を採用する
        # 決定論的なタイブレークルール。
        max_count = max(counter.values())
        tied = [p for p, c in counter.items() if c == max_count]
        winning_priority = min(tied)
        hex_result[h3_int] = (
            rules.TERRAIN_BY_PRIORITY[winning_priority],
            winning_priority,
            counter,
        )

    return hex_result, cell_rows


def write_sqlite(
    out_path: Path,
    cell_rows: list[tuple],
    hex_result: dict[int, tuple[str, int, Counter]],
    meta: dict[str, str],
) -> None:
    out_path.parent.mkdir(parents=True, exist_ok=True)
    if out_path.exists():
        out_path.unlink()

    conn = sqlite3.connect(str(out_path))
    try:
        conn.execute(
            """
            CREATE TABLE cell_terrain (
                cell_id INTEGER PRIMARY KEY,
                hex_id INTEGER NOT NULL,
                lon REAL NOT NULL,
                lat REAL NOT NULL,
                terrain_type TEXT NOT NULL
            )
            """
        )
        conn.execute(
            """
            CREATE TABLE hex_terrain (
                hex_id INTEGER PRIMARY KEY,
                terrain_type TEXT NOT NULL,
                feature_id INTEGER NOT NULL,
                cell_count INTEGER NOT NULL
            )
            """
        )
        conn.execute("CREATE INDEX idx_cell_terrain_hex_id ON cell_terrain(hex_id)")
        conn.execute("CREATE UNIQUE INDEX idx_hex_terrain_feature_id ON hex_terrain(feature_id)")
        conn.execute("CREATE TABLE pack_meta (key TEXT PRIMARY KEY, value TEXT)")

        conn.executemany(
            "INSERT INTO cell_terrain (cell_id, hex_id, lon, lat, terrain_type) VALUES (?, ?, ?, ?, ?)",
            cell_rows,
        )

        # hex_id で安定ソートして書き込む（決定論チェックのしやすさのため）。
        for hex_id in sorted(hex_result):
            terrain_type, _winning_priority, counter = hex_result[hex_id]
            cell_count = sum(counter.values())
            feature_id = h3_to_feature_id(hex_id)
            conn.execute(
                "INSERT INTO hex_terrain (hex_id, terrain_type, feature_id, cell_count) VALUES (?, ?, ?, ?)",
                (hex_id, terrain_type, feature_id, cell_count),
            )

        conn.executemany(
            "INSERT INTO pack_meta (key, value) VALUES (?, ?)",
            list(meta.items()),
        )
        conn.commit()
    finally:
        conn.close()


def sha256_of_file(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", default=str(HERE / config.AREA_PBF_PATH))
    parser.add_argument("--out", default=str(HERE / config.OUT_DIR / "pack.sqlite"))
    args = parser.parse_args()

    input_path = Path(args.input)
    out_path = Path(args.out)

    if not input_path.exists():
        log(f"input not found: {input_path}. 先に extract_area.sh を実行してください。")
        sys.exit(1)

    t0 = time.perf_counter()

    lat0 = (config.BBOX_LAT_MIN + config.BBOX_LAT_MAX) / 2
    lon0 = (config.BBOX_LON_MIN + config.BBOX_LON_MAX) / 2
    proj = LocalProjection(lon0, lat0)

    log(f"loading geometries from {input_path} ...")
    buckets = load_geometries(input_path, proj)
    for p, geoms in buckets.items():
        log(f"  priority {p} ({rules.TERRAIN_BY_PRIORITY[p]}): {len(geoms)} raw geometries")

    log("unioning geometries per priority ...")
    unioned = union_buckets(buckets)

    log("building grid ...")
    grid_x, grid_y, lon, lat = build_grid(proj)

    log("classifying cells ...")
    cell_priority = classify_cells(grid_x, grid_y, unioned)

    log("aggregating to H3 hexes ...")
    hex_result, cell_rows = aggregate_to_hexes(lon, lat, cell_priority)

    headers = {header_bits_of(h) for h in hex_result}
    if len(headers) != 1:
        log(f"WARNING: 複数の H3 index ヘッダビットが混在しています: {headers}")
    else:
        log(f"H3 index header bits（全ヘクス共通）: {headers.pop()}")

    elapsed = time.perf_counter() - t0

    meta = {
        "generated_at_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "h3_resolution": str(config.H3_RESOLUTION),
        "cell_size_m": str(config.CELL_SIZE_M),
        "bbox_lon_min": str(config.BBOX_LON_MIN),
        "bbox_lon_max": str(config.BBOX_LON_MAX),
        "bbox_lat_min": str(config.BBOX_LAT_MIN),
        "bbox_lat_max": str(config.BBOX_LAT_MAX),
        "input_pbf": str(input_path.name),
        "input_pbf_sha256": sha256_of_file(input_path),
        "cell_count": str(len(cell_rows)),
        "hex_count": str(len(hex_result)),
        "generation_seconds": f"{elapsed:.3f}",
        "python_version": platform.python_version(),
        "osmium_version": _pkg_version("osmium"),
        "h3_py_version": _pkg_version("h3"),
        "shapely_version": _pkg_version("shapely"),
    }

    log(f"writing SQLite -> {out_path}")
    write_sqlite(out_path, cell_rows, hex_result, meta)

    out_size = out_path.stat().st_size
    log(f"DONE in {elapsed:.2f}s. cells={len(cell_rows)} hexes={len(hex_result)} out_size={out_size} bytes")
    print(json.dumps({**meta, "out_size_bytes": out_size, "out_path": str(out_path)}, ensure_ascii=False, indent=2))


def _pkg_version(name: str) -> str:
    try:
        import importlib.metadata as im

        return im.version(name)
    except Exception:
        return "unknown"


if __name__ == "__main__":
    main()
