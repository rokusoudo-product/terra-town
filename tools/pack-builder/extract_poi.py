#!/usr/bin/env python3
"""tools/pack-builder/extract_poi.py — 名所POI抽出（Issue #86・T042。Tier 2/hex_poi は Issue #158）。

入力:
  - `config.AREA_PBF_PATH`（osmium extract 済みの1エリア分の .osm.pbf。
    `classify_terrain.py` と同じキャッシュを再利用する。既存の data_cache を
    活用し、再取得は行わない）
  - `<pack-sqlite>`（既定 `out/pack.sqlite`。`classify_terrain.py` の出力。
    `hex_terrain` のヘクス集合を「パックに含まれるヘクス」の正として使う。
    Issue #158 で新設した依存 — 本スクリプトは `classify_terrain.py` の
    **後**に実行すること。`bundle_region_pack.sh`・`.github/workflows/pack-build.yml`
    は元々この順序で実行しているため、パイプライン自体の変更は不要）
出力: `<out>/poi.sqlite`（テーブル: poi, hex_poi, pack_meta）

処理の流れ（`docs/landmark_objects.md` §2.1・plan.md §3.2・Issue #158に対応）:
  1. OSM抽出データから、`poi_rules.matched_tag`（Tier 1、`config.POI_INCLUDE_TIER2`が
     真なら Tier 2 も）に該当する Node（点）/ Area（閉領域）を集める。
  2. `leisure=park` はさらに面積条件（`config.POI_PARK_MIN_AREA_M2`）を課す
     （Tier 2 のタグに面積条件付きのものは無い）。
  3. 名称（`name` → `name:ja` の順でフォールバック）を持たない地物は除外する
     （名所図鑑上、名称のない地物は意味を持たないため。Tier 2 にも同じ基準を適用する）。
  4. Area（閉領域）は重心（ローカル平面座標で計算してから緯度経度に戻す。
     `classify_terrain.py` と同じ考え方）を代表点として採用する。
  5. `id` は OSM の型を含めた文字列（`node/<id>`・`way/<id>`・`relation/<id>`）とする。
     OSM の node/way/relation は id 空間が重複しうるため、型プレフィックスなしでは
     `PointOfInterestId`（core, plan.md §3.2）の一意性が保証できない。
  6. 各POIの（丸め済みの）緯度経度から、`classify_terrain.py`と同じ
     `h3.latlng_to_cell(..., config.H3_RESOLUTION)` でヘクスIDを求める
     （Kotlin `H3HexIndexer` と同一のアルゴリズム。`generate_hex_locator_fixture.py`が
     実際に両言語の出力を突き合わせて検証する）。
  7. `<pack-sqlite>` の `hex_terrain` に無いヘクスに落ちるPOIは、`poi`・`hex_poi`の
     両方から除外する（開示できないヘクスの名所は収集不能なため。Issue #158
     受け入れ基準）。除外件数をログ・`pack_meta`に記録する。

決定論: OSM入力・設定・`<pack-sqlite>`が同じなら、タグ判定・重心計算・ヘクスID計算・
出力順序（`id`昇順ソート）はいずれも実行順や乱数に依存しない。
`verify_poi_determinism.py` で2回生成して確認する。
"""

from __future__ import annotations

import argparse
import hashlib
import json
import sqlite3
import sys
import time
from pathlib import Path

import h3
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


def _hex_id_of(lat: float, lon: float) -> int:
    """`classify_terrain.py`の`aggregate_to_hexes`と同一のH3変換（本ファイルdocstring §6参照）。"""
    return h3.str_to_int(h3.latlng_to_cell(lat, lon, config.H3_RESOLUTION))


def extract_pois(
    pbf_path: Path, proj: LocalProjection, include_tier2: bool
) -> tuple[list[dict], dict[tuple[str, str], int]]:
    """POI レコードの一覧（`hex_id`計算済み・パック範囲外除外は未実施）と、
    タグ別のヒット件数（除外前）を返す。"""
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
            matched = poi_rules.matched_tag(tags, include_tier2=include_tier2)
            if matched is None:
                continue
            tag, tier = matched
            per_kind_hits[tag] = per_kind_hits.get(tag, 0) + 1
            name = _pick_name(tags)
            if not name:
                n_no_name += 1
                continue
            per_kind_kept[tag] = per_kind_kept.get(tag, 0) + 1
            lat = round(float(obj.location.lat), 7)
            lon = round(float(obj.location.lon), 7)
            records.append(
                {
                    "id": f"node/{obj.id}",
                    "name": name,
                    "kind": f"{tag[0]}={tag[1]}",
                    "tier": tier,
                    "lat": lat,
                    "lon": lon,
                    "hex_id": _hex_id_of(lat, lon),
                }
            )
        elif obj.is_area():
            tags = dict(obj.tags)
            if not tags:
                continue
            matched = poi_rules.matched_tag(tags, include_tier2=include_tier2)
            if matched is None:
                continue
            tag, tier = matched
            try:
                wkb_hex = wkbfab.create_multipolygon(obj)
            except RuntimeError as exc:
                log(f"  skip area id={obj.orig_id()} (wkb error: {exc})")
                continue
            polygon = shapely.wkb.loads(bytes.fromhex(wkb_hex))
            if not polygon.is_valid:
                polygon = polygon.buffer(0)
            polygon_m = proj.project_geom(polygon)

            if tag in poi_rules.AREA_THRESHOLD_TAGS and polygon_m.area < config.POI_PARK_MIN_AREA_M2:
                n_park_too_small += 1
                continue

            per_kind_hits[tag] = per_kind_hits.get(tag, 0) + 1
            name = _pick_name(tags)
            if not name:
                n_no_name += 1
                continue
            per_kind_kept[tag] = per_kind_kept.get(tag, 0) + 1

            centroid_m = polygon_m.centroid
            centroid_lonlat = proj.unproject_geom(centroid_m)
            osm_type = "way" if obj.from_way() else "relation"
            lat = round(float(centroid_lonlat.y), 7)
            lon = round(float(centroid_lonlat.x), 7)
            records.append(
                {
                    "id": f"{osm_type}/{obj.orig_id()}",
                    "name": name,
                    "kind": f"{tag[0]}={tag[1]}",
                    "tier": tier,
                    "lat": lat,
                    "lon": lon,
                    "hex_id": _hex_id_of(lat, lon),
                }
            )

    log(
        "tag hits (before name filter; leisure=park is counted here only after "
        f"passing the area threshold): { {f'{k}={v}': c for (k, v), c in per_kind_hits.items()} }"
    )
    log(f"kept per kind: { {f'{k}={v}': c for (k, v), c in per_kind_kept.items()} }")
    log(f"excluded: no_name={n_no_name} park_too_small={n_park_too_small}")

    return records, per_kind_kept


def read_pack_hex_id_set(pack_sqlite_path: Path) -> set[int]:
    conn = sqlite3.connect(str(pack_sqlite_path))
    try:
        return {row[0] for row in conn.execute("SELECT hex_id FROM hex_terrain")}
    finally:
        conn.close()


def exclude_out_of_pack_hex(records: list[dict], pack_hex_ids: set[int]) -> tuple[list[dict], int]:
    """`hex_terrain`に無いヘクスに落ちるPOIを除外する（本ファイルdocstring §7参照）。

    戻り値: (パック範囲内のみのレコード一覧, 除外件数)
    """
    kept = [r for r in records if r["hex_id"] in pack_hex_ids]
    excluded = len(records) - len(kept)
    return kept, excluded


def write_sqlite(out_path: Path, records: list[dict], meta: dict[str, str]) -> None:
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
        conn.execute(
            """
            CREATE TABLE hex_poi (
                poi_id TEXT PRIMARY KEY,
                hex_id INTEGER NOT NULL
            )
            """
        )
        conn.execute("CREATE INDEX idx_hex_poi_hex_id ON hex_poi(hex_id)")
        conn.execute("CREATE TABLE pack_meta (key TEXT PRIMARY KEY, value TEXT)")

        # id昇順で安定ソートして書き込む（決定論チェックのしやすさのため。
        # classify_terrain.py が hex_id 昇順で書き込むのと同じ方針）。
        for r in sorted(records, key=lambda r: r["id"]):
            conn.execute(
                "INSERT INTO poi (id, lat, lon, kind, name) VALUES (?, ?, ?, ?, ?)",
                (r["id"], r["lat"], r["lon"], r["kind"], r["name"]),
            )
            conn.execute(
                "INSERT INTO hex_poi (poi_id, hex_id) VALUES (?, ?)",
                (r["id"], r["hex_id"]),
            )

        conn.executemany("INSERT INTO pack_meta (key, value) VALUES (?, ?)", list(meta.items()))
        conn.commit()
    finally:
        conn.close()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", default=str(HERE / config.AREA_PBF_PATH))
    parser.add_argument(
        "--pack-sqlite",
        default=str(HERE / config.OUT_DIR / "pack.sqlite"),
        help="classify_terrain.py の出力（hex_terrain のヘクス集合をパック範囲の正として使う）",
    )
    parser.add_argument("--out", default=str(HERE / config.OUT_DIR / "poi.sqlite"))
    args = parser.parse_args()

    input_path = Path(args.input)
    pack_sqlite_path = Path(args.pack_sqlite)
    out_path = Path(args.out)

    if not input_path.exists():
        log(f"input not found: {input_path}. 先に extract_area.sh を実行してください。")
        sys.exit(1)
    if not pack_sqlite_path.exists():
        log(f"{pack_sqlite_path} not found. 先に classify_terrain.py を実行してください。")
        sys.exit(1)

    t0 = time.perf_counter()

    lat0 = (config.BBOX_LAT_MIN + config.BBOX_LAT_MAX) / 2
    lon0 = (config.BBOX_LON_MIN + config.BBOX_LON_MAX) / 2
    proj = LocalProjection(lon0, lat0)

    include_tier2 = config.POI_INCLUDE_TIER2
    log(
        f"scanning {input_path} for POI tags (Tier 1"
        f"{'+Tier 2' if include_tier2 else ' only'}) ..."
    )
    records, per_kind_kept = extract_pois(input_path, proj, include_tier2=include_tier2)

    ids = [r["id"] for r in records]
    if len(ids) != len(set(ids)):
        log("ERROR: id が重複しています（node/way/relation の型プレフィックスを確認してください）。")
        sys.exit(1)

    log(f"loading pack hex set from {pack_sqlite_path} ...")
    pack_hex_ids = read_pack_hex_id_set(pack_sqlite_path)
    log(f"  {len(pack_hex_ids)} hexes in pack")

    records, n_excluded_out_of_pack_hex = exclude_out_of_pack_hex(records, pack_hex_ids)
    log(f"excluded out-of-pack-hex POIs: {n_excluded_out_of_pack_hex}")

    per_tier_kept: dict[int, int] = {1: 0, 2: 0}
    for r in records:
        per_tier_kept[r["tier"]] = per_tier_kept.get(r["tier"], 0) + 1

    elapsed = time.perf_counter() - t0
    input_pbf_sha256 = sha256_of_file(input_path)

    meta = {
        "poi_source": "OpenStreetMap（観光POI。docs/landmark_objects.md §2.1）",
        "poi_license": "Open Database License (ODbL) 1.0 — © OpenStreetMap contributors。"
        "詳細な適合検証は別Issue（#37）のスコープ",
        "poi_tag_tier": "tier1_and_tier2" if include_tier2 else "tier1_only",
        "poi_park_min_area_m2": str(config.POI_PARK_MIN_AREA_M2),
        "poi_count": str(len(records)),
        "poi_count_by_tier": json.dumps(
            {str(k): v for k, v in per_tier_kept.items()}, ensure_ascii=False
        ),
        "poi_count_by_kind": json.dumps(
            {f"{k}={v}": c for (k, v), c in per_kind_kept.items()}, ensure_ascii=False
        ),
        "poi_excluded_out_of_pack_hex_count": str(n_excluded_out_of_pack_hex),
        "poi_hex_poi_count": str(len(records)),
        "input_pbf": str(input_path.name),
        "input_pbf_sha256": input_pbf_sha256,
        "generated_at_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "generation_seconds": f"{elapsed:.3f}",
        "osmium_version": _pkg_version("osmium"),
        "shapely_version": _pkg_version("shapely"),
        "h3_py_version": _pkg_version("h3"),
    }

    log(f"writing SQLite -> {out_path}")
    write_sqlite(out_path, records, meta)

    out_size = out_path.stat().st_size
    log(
        f"DONE in {elapsed:.2f}s. poi={len(records)} "
        f"(tier1={per_tier_kept.get(1, 0)} tier2={per_tier_kept.get(2, 0)}) "
        f"excluded_out_of_pack_hex={n_excluded_out_of_pack_hex} out_size={out_size} bytes"
    )
    print(json.dumps({**meta, "out_size_bytes": out_size, "out_path": str(out_path)}, ensure_ascii=False, indent=2))


def _pkg_version(name: str) -> str:
    try:
        import importlib.metadata as im

        return im.version(name)
    except Exception:
        return "unknown"


if __name__ == "__main__":
    main()
