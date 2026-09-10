#!/usr/bin/env python3
"""tools/pack-builder/extract_poi.py — 名所POI抽出（Issue #86・T042）。

入力: `config.AREA_PBF_PATH`（osmium extract 済みの1エリア分の .osm.pbf。
      `classify_terrain.py` と同じキャッシュを再利用する。既存の data_cache を
      活用し、再取得は行わない）
出力: `<out>/poi.sqlite`（テーブル: poi, pack_meta）

処理の流れ（`docs/landmark_objects.md` §2.1・plan.md §3.2に対応）:
  1. OSM抽出データから、`poi_rules.TIER1_TAGS`（観光POIタグ・Tier 1のみ）に
     該当する Node（点）/ Area（閉領域）を集める。
  2. `leisure=park` はさらに面積条件（`config.POI_PARK_MIN_AREA_M2`）を課す。
  3. 名称（`name` → `name:ja` の順でフォールバック）を持たない地物は除外する
     （名所図鑑上、名称のない地物は意味を持たないため）。
  4. Area（閉領域）は重心（ローカル平面座標で計算してから緯度経度に戻す。
     `classify_terrain.py` と同じ考え方）を代表点として採用する。
  5. `id` は OSM の型を含めた文字列（`node/<id>`・`way/<id>`・`relation/<id>`）とする。
     OSM の node/way/relation は id 空間が重複しうるため、型プレフィックスなしでは
     `PointOfInterestId`（core, plan.md §3.2）の一意性が保証できない。

決定論: OSM入力・設定が同じなら、タグ判定・重心計算・出力順序（`id`昇順ソート）は
いずれも実行順や乱数に依存しない。`verify_poi_determinism.py` で2回生成して確認する。
"""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
import time
from pathlib import Path

import osmium
import shapely
import shapely.geometry as geom
import shapely.wkb

import config
import poi_rules
from local_projection import LocalProjection

HERE = Path(__file__).resolve().parent


def log(msg: str) -> None:
    print(f"[extract_poi] {msg}", file=sys.stderr, flush=True)


def sha256_of_file(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def _pick_name(tags: dict[str, str]) -> str | None:
    return tags.get("name") or tags.get("name:ja")


def extract_pois(pbf_path: Path, proj: LocalProjection) -> tuple[list[dict], dict[tuple[str, str], int]]:
    """POI レコードの一覧と、タグ別のヒット件数（除外前）を返す。"""
    wkbfab = osmium.geom.WKBFactory()
    records: list[dict] = []
    per_kind_hits: dict[tuple[str, str], int] = {}
    per_kind_kept: dict[tuple[str, str], int] = {}
    n_no_name = 0
    n_park_too_small = 0

    fp = osmium.FileProcessor(str(pbf_path)).with_areas()
    for obj in fp:
        if obj.is_node():
            tags = dict(obj.tags)
            if not tags:
                continue
            matched = poi_rules.matched_tag(tags)
            if matched is None:
                continue
            per_kind_hits[matched] = per_kind_hits.get(matched, 0) + 1
            name = _pick_name(tags)
            if not name:
                n_no_name += 1
                continue
            per_kind_kept[matched] = per_kind_kept.get(matched, 0) + 1
            records.append(
                {
                    "id": f"node/{obj.id}",
                    "name": name,
                    "kind": f"{matched[0]}={matched[1]}",
                    "lat": round(float(obj.location.lat), 7),
                    "lon": round(float(obj.location.lon), 7),
                }
            )
        elif obj.is_area():
            tags = dict(obj.tags)
            if not tags:
                continue
            matched = poi_rules.matched_tag(tags)
            if matched is None:
                continue
            try:
                wkb_hex = wkbfab.create_multipolygon(obj)
            except RuntimeError as exc:
                log(f"  skip area id={obj.orig_id()} (wkb error: {exc})")
                continue
            polygon = shapely.wkb.loads(bytes.fromhex(wkb_hex))
            if not polygon.is_valid:
                polygon = polygon.buffer(0)
            polygon_m = proj.project_geom(polygon)

            if matched in poi_rules.AREA_THRESHOLD_TAGS and polygon_m.area < config.POI_PARK_MIN_AREA_M2:
                n_park_too_small += 1
                continue

            per_kind_hits[matched] = per_kind_hits.get(matched, 0) + 1
            name = _pick_name(tags)
            if not name:
                n_no_name += 1
                continue
            per_kind_kept[matched] = per_kind_kept.get(matched, 0) + 1

            centroid_m = polygon_m.centroid
            centroid_lonlat = proj.unproject_geom(centroid_m)
            osm_type = "way" if obj.from_way() else "relation"
            records.append(
                {
                    "id": f"{osm_type}/{obj.orig_id()}",
                    "name": name,
                    "kind": f"{matched[0]}={matched[1]}",
                    "lat": round(float(centroid_lonlat.y), 7),
                    "lon": round(float(centroid_lonlat.x), 7),
                }
            )

    log(
        f"tag hits (before name/area filter): { {f'{k}={v}': c for (k, v), c in per_kind_hits.items()} }"
    )
    log(f"kept per kind: { {f'{k}={v}': c for (k, v), c in per_kind_kept.items()} }")
    log(f"excluded: no_name={n_no_name} park_too_small={n_park_too_small}")

    return records, per_kind_kept


def write_sqlite(out_path: Path, records: list[dict], meta: dict[str, str]) -> None:
    import sqlite3

    out_path.parent.mkdir(parents=True, exist_ok=True)
    if out_path.exists():
        out_path.unlink()

    conn = sqlite3.connect(str(out_path))
    try:
        conn.execute(
            """
            CREATE TABLE poi (
                id TEXT PRIMARY KEY,
                lat REAL NOT NULL,
                lon REAL NOT NULL,
                kind TEXT NOT NULL,
                name TEXT NOT NULL
            )
            """
        )
        conn.execute("CREATE TABLE pack_meta (key TEXT PRIMARY KEY, value TEXT)")

        # id昇順で安定ソートして書き込む（決定論チェックのしやすさのため。
        # classify_terrain.py が hex_id 昇順で書き込むのと同じ方針）。
        for r in sorted(records, key=lambda r: r["id"]):
            conn.execute(
                "INSERT INTO poi (id, lat, lon, kind, name) VALUES (?, ?, ?, ?, ?)",
                (r["id"], r["lat"], r["lon"], r["kind"], r["name"]),
            )

        conn.executemany("INSERT INTO pack_meta (key, value) VALUES (?, ?)", list(meta.items()))
        conn.commit()
    finally:
        conn.close()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", default=str(HERE / config.AREA_PBF_PATH))
    parser.add_argument("--out", default=str(HERE / config.OUT_DIR / "poi.sqlite"))
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

    log(f"scanning {input_path} for Tier 1 POI tags ...")
    records, per_kind_kept = extract_pois(input_path, proj)

    ids = [r["id"] for r in records]
    if len(ids) != len(set(ids)):
        log("ERROR: id が重複しています（node/way/relation の型プレフィックスを確認してください）。")
        sys.exit(1)

    elapsed = time.perf_counter() - t0
    input_pbf_sha256 = sha256_of_file(input_path)

    meta = {
        "poi_source": "OpenStreetMap（観光POI・Tier 1のみ。docs/landmark_objects.md §2.1）",
        "poi_license": "Open Database License (ODbL) 1.0 — © OpenStreetMap contributors。"
        "詳細な適合検証は別Issue（#37）のスコープ",
        "poi_tag_tier": "tier1_only",
        "poi_park_min_area_m2": str(config.POI_PARK_MIN_AREA_M2),
        "poi_count": str(len(records)),
        "poi_count_by_kind": json.dumps(
            {f"{k}={v}": c for (k, v), c in per_kind_kept.items()}, ensure_ascii=False
        ),
        "input_pbf": str(input_path.name),
        "input_pbf_sha256": input_pbf_sha256,
        "generated_at_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "generation_seconds": f"{elapsed:.3f}",
        "osmium_version": _pkg_version("osmium"),
        "shapely_version": _pkg_version("shapely"),
    }

    log(f"writing SQLite -> {out_path}")
    write_sqlite(out_path, records, meta)

    out_size = out_path.stat().st_size
    log(f"DONE in {elapsed:.2f}s. poi={len(records)} out_size={out_size} bytes")
    print(json.dumps({**meta, "out_size_bytes": out_size, "out_path": str(out_path)}, ensure_ascii=False, indent=2))


def _pkg_version(name: str) -> str:
    try:
        import importlib.metadata as im

        return im.version(name)
    except Exception:
        return "unknown"


if __name__ == "__main__":
    main()
