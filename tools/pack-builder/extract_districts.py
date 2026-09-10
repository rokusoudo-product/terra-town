#!/usr/bin/env python3
"""tools/pack-builder/extract_districts.py — 行政区域ポリゴンの取り込み（Issue #86・T041）。

入力:
  - `download_n03.sh` で取得済みの 国土数値情報 N03（行政区域データ、都道府県別GeoJSON。
    `config.N03_DIR` 配下）
  - `classify_terrain.py` の出力（`out/pack.sqlite` の `hex_terrain`。ヘクス→区画の
    帰属判定〔plan.md §5〕に使うヘクス集合の正）

出力: `<out>/districts.sqlite`（テーブル: district, hex_district, pack_meta）

処理の流れ（plan.md §3.2・§5、docs/landmark_objects.md とは無関係）:
  1. 対象都道府県（`config.N03_PREFECTURE_CODES`）分の N03 GeoJSON を読み込み、
     対象エリアの bbox と交差する市区町村ポリゴンを抽出する
     （「当該地域」＝bboxと交差する市区町村。bboxでのクリップは行わない。
     理由: クリップは切断線での位相再構築が別途必要になり実装リスクが高い一方、
     交差判定のみなら対象は5件程度〔狭山湖周辺〕でパックサイズへの影響は軽微）。
  2. `topojson` パッケージでトポロジ保持簡略化を行う（`config.DISTRICT_SIMPLIFY_TOLERANCE_M`）。
     隣接する市区町村境界を共有アークとして扱うため、単純に1ポリゴンずつ
     `shapely.simplify` するのと異なり、簡略化後も隣接ポリゴン間に隙間・重なりが
     生じない（本ファイル内 `verify_topology` で実行のたびに検証する）。
  3. `hex_terrain`（`classify_terrain.py`の出力）の全ヘクスについて、ヘクス中心点
     （H3セルの重心。`h3.cell_to_latlng`）が**簡略化前（原本）**のどの市区町村
     ポリゴンに含まれるかを判定し、`hex_district` に記録する（plan.md §5
     「ヘクス重心が区画内かで帰属判定」）。簡略化後のポリゴンは表示用、
     帰属判定は原本の精度を使う（両者の用途を分離する設計判断）。

決定論: GeoJSON入力・設定が同じであれば、フィルタ・トポロジ簡略化・点内判定は
いずれも実行順や乱数に依存しない演算であるため、出力は入力に対して一意に決まる。
`verify_districts_determinism.py` で実際に2回生成して確認する。
"""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
import time
from pathlib import Path

import h3
import shapely
import shapely.geometry as geom
import topojson as tp

import config
from local_projection import LocalProjection

HERE = Path(__file__).resolve().parent


def log(msg: str) -> None:
    print(f"[extract_districts] {msg}", file=sys.stderr, flush=True)


def sha256_of_file(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def load_n03_features(n03_dir: Path, pref_codes: list[str]) -> list[tuple[dict, "shapely.Geometry"]]:
    """都道府県別 N03 GeoJSON を読み込み、(properties, shapely geometry) の一覧を返す。"""
    features: list[tuple[dict, "shapely.Geometry"]] = []
    for pref in pref_codes:
        geojson_paths = sorted((n03_dir / pref).glob("*.geojson"))
        if not geojson_paths:
            log(f"N03 GeoJSON not found for pref={pref} under {n03_dir / pref}. 先に download_n03.sh を実行してください。")
            sys.exit(1)
        path = geojson_paths[0]
        with open(path, encoding="utf-8") as f:
            fc = json.load(f)
        for feat in fc["features"]:
            props = feat["properties"]
            g = geom.shape(feat["geometry"])
            if not g.is_valid:
                g = g.buffer(0)
            features.append((props, g))
    return features


def select_intersecting(
    features: list[tuple[dict, "shapely.Geometry"]], bbox_poly: "shapely.Geometry"
) -> list[tuple[dict, "shapely.Geometry"]]:
    return [(props, g) for props, g in features if g.intersects(bbox_poly)]


def round_coords(g: "shapely.Geometry", ndigits: int = 7) -> "shapely.Geometry":
    """座標を小数点以下 ndigits 桁に丸める（決定論の安定化・出力サイズ削減）。"""

    def _tf(coords):
        import numpy as np

        return np.round(np.asarray(coords), ndigits)

    return shapely.transform(g, _tf)


def simplify_topology(
    geoms_m: list["shapely.Geometry"], tolerance_m: float
) -> list["shapely.Geometry"]:
    """`topojson` でトポロジ保持簡略化を行う（ローカル平面座標・メートル単位で実行）。"""
    topo = tp.Topology(geoms_m, prequantize=False)
    simplified = topo.toposimplify(tolerance_m, prevent_oversimplify=True)
    gj = json.loads(simplified.to_geojson())
    return [geom.shape(f["geometry"]) for f in gj["features"]]


def verify_topology(originals_m: list["shapely.Geometry"], simplified_m: list["shapely.Geometry"]) -> None:
    """簡略化後も隣接関係（隙間・重なりの有無）が壊れていないことを検証する。"""
    n = len(originals_m)
    for i in range(n):
        for j in range(i + 1, n):
            inter = simplified_m[i].intersection(simplified_m[j])
            if inter.area > 1e-6:
                raise AssertionError(
                    f"簡略化後のポリゴン {i}/{j} が重なっています（area={inter.area}）。"
                    f"DISTRICT_SIMPLIFY_TOLERANCE_M を下げて再実行してください。"
                )
    sum_area = sum(g.area for g in simplified_m)
    union_area = shapely.union_all(simplified_m).area
    gap = sum_area - union_area
    # 隣接ポリゴン間に隙間があると union_area が sum_area より小さくなる。
    # 浮動小数点誤差（実測 1e-7 オーダー）を超える乖離があれば異常とみなす。
    if abs(gap) > max(1.0, sum_area * 1e-6):
        raise AssertionError(
            f"簡略化後のポリゴン間に隙間または重なりが疑われます（sum_area={sum_area}, "
            f"union_area={union_area}, diff={gap}）。"
        )
    log(f"topology check OK（sum_area - union_area = {gap:.6f} m^2、境界共有は壊れていない）")


def assign_hexes_to_districts(
    hex_ids: list[int],
    districts: list[tuple[str, "shapely.Geometry"]],
) -> dict[int, str]:
    """各ヘクス中心点が属する区画を判定する（plan.md §5「ヘクス重心が区画内か」）。

    `districts` は (district_id, 原本ポリゴン〔簡略化前・lon/lat〕) のリスト。
    複数区画の境界上に重心が乗るまれなケースでは、`district_id` 昇順で最初に
    一致したものを採用する（決定論的なタイブレーク。classify_terrain.py の
    多数決タイブレークと同じ考え方）。
    """
    ordered = sorted(districts, key=lambda d: d[0])
    prepared = [(did, shapely.prepare(g) or g) for did, g in ordered]

    result: dict[int, str] = {}
    for hex_id in hex_ids:
        lat, lon = h3.cell_to_latlng(h3.int_to_str(hex_id))
        pt = geom.Point(lon, lat)
        for district_id, prepared_geom in prepared:
            # covers: 境界上の点も含む（contains は境界を除外するため、
            # 隣接区画の境界線上に重心が乗るケースを取りこぼす恐れがある）。
            if prepared_geom.covers(pt):
                result[hex_id] = district_id
                break
    return result


def read_hex_ids(pack_sqlite_path: Path) -> list[int]:
    import sqlite3

    conn = sqlite3.connect(str(pack_sqlite_path))
    try:
        return [row[0] for row in conn.execute("SELECT hex_id FROM hex_terrain ORDER BY hex_id")]
    finally:
        conn.close()


def write_sqlite(
    out_path: Path,
    districts: list[tuple[str, str, str, str, "shapely.Geometry"]],
    hex_district: dict[int, str],
    meta: dict[str, str],
) -> None:
    import sqlite3

    out_path.parent.mkdir(parents=True, exist_ok=True)
    if out_path.exists():
        out_path.unlink()

    conn = sqlite3.connect(str(out_path))
    try:
        conn.execute(
            """
            CREATE TABLE district (
                district_id TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                prefecture_name TEXT NOT NULL,
                county_name TEXT NOT NULL,
                geometry_geojson TEXT NOT NULL
            )
            """
        )
        conn.execute(
            """
            CREATE TABLE hex_district (
                hex_id INTEGER PRIMARY KEY,
                district_id TEXT NOT NULL
            )
            """
        )
        conn.execute("CREATE INDEX idx_hex_district_district_id ON hex_district(district_id)")
        conn.execute("CREATE TABLE pack_meta (key TEXT PRIMARY KEY, value TEXT)")

        for district_id, name, pref_name, county_name, simplified_geom in sorted(
            districts, key=lambda d: d[0]
        ):
            conn.execute(
                "INSERT INTO district (district_id, name, prefecture_name, county_name, geometry_geojson) "
                "VALUES (?, ?, ?, ?, ?)",
                (
                    district_id,
                    name,
                    pref_name,
                    county_name,
                    json.dumps(geom.mapping(simplified_geom), ensure_ascii=False),
                ),
            )

        for hex_id in sorted(hex_district):
            conn.execute(
                "INSERT INTO hex_district (hex_id, district_id) VALUES (?, ?)",
                (hex_id, hex_district[hex_id]),
            )

        conn.executemany(
            "INSERT INTO pack_meta (key, value) VALUES (?, ?)", list(meta.items())
        )
        conn.commit()
    finally:
        conn.close()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pack-sqlite", default=str(HERE / config.OUT_DIR / "pack.sqlite"))
    parser.add_argument("--out", default=str(HERE / config.OUT_DIR / "districts.sqlite"))
    args = parser.parse_args()

    pack_sqlite_path = Path(args.pack_sqlite)
    out_path = Path(args.out)
    n03_dir = HERE / config.N03_DIR

    if not pack_sqlite_path.exists():
        log(f"{pack_sqlite_path} not found. 先に classify_terrain.py を実行してください。")
        sys.exit(1)

    t0 = time.perf_counter()

    bbox_poly = geom.box(
        config.BBOX_LON_MIN, config.BBOX_LAT_MIN, config.BBOX_LON_MAX, config.BBOX_LAT_MAX
    )

    log(f"loading N03 GeoJSON for prefectures {config.N03_PREFECTURE_CODES} ...")
    all_features = load_n03_features(n03_dir, config.N03_PREFECTURE_CODES)
    log(f"  {len(all_features)} municipality records loaded (all prefectures)")

    selected = select_intersecting(all_features, bbox_poly)
    log(f"  {len(selected)} municipalities intersect the target bbox")
    for props, _ in selected:
        log(f"    {props['N03_007']} {props['N03_001']}{props.get('N03_003') or ''}{props['N03_004']}")

    if not selected:
        log("ERROR: 対象bboxと交差する市区町村が見つかりませんでした。")
        sys.exit(1)

    lat0 = (config.BBOX_LAT_MIN + config.BBOX_LAT_MAX) / 2
    lon0 = (config.BBOX_LON_MIN + config.BBOX_LON_MAX) / 2
    proj = LocalProjection(lon0, lat0)

    original_geoms = [g for _, g in selected]
    original_geoms_m = [proj.project_geom(g) for g in original_geoms]

    log(f"simplifying topology (tolerance={config.DISTRICT_SIMPLIFY_TOLERANCE_M}m) ...")
    simplified_geoms_m = simplify_topology(original_geoms_m, config.DISTRICT_SIMPLIFY_TOLERANCE_M)
    verify_topology(original_geoms_m, simplified_geoms_m)

    simplified_geoms = [round_coords(proj.unproject_geom(g)) for g in simplified_geoms_m]

    vertices_before = sum(_count_vertices(g) for g in original_geoms_m)
    vertices_after = sum(_count_vertices(g) for g in simplified_geoms_m)
    log(f"vertices: {vertices_before} -> {vertices_after} ({vertices_after / vertices_before * 100:.1f}%)")

    districts = [
        (props["N03_007"], props["N03_004"], props["N03_001"], props.get("N03_003") or "", sg)
        for (props, _), sg in zip(selected, simplified_geoms)
    ]

    log(f"reading hex set from {pack_sqlite_path} ...")
    hex_ids = read_hex_ids(pack_sqlite_path)
    log(f"  {len(hex_ids)} hexes")

    log("assigning hexes to districts (original geometry, hex centroid) ...")
    district_polys_for_assign = [(props["N03_007"], g) for props, g in selected]
    hex_district = assign_hexes_to_districts(hex_ids, district_polys_for_assign)
    unassigned = len(hex_ids) - len(hex_district)
    log(f"  assigned={len(hex_district)} unassigned={unassigned} (total={len(hex_ids)})")

    elapsed = time.perf_counter() - t0

    n03_sha256 = {}
    for pref in config.N03_PREFECTURE_CODES:
        zip_paths = sorted((n03_dir).glob(f"N03-{config.N03_EDITION}_{pref}_GML.zip"))
        if zip_paths:
            n03_sha256[pref] = sha256_of_file(zip_paths[0])

    meta = {
        "district_source": "国土数値情報 行政区域データ（N03）",
        "district_source_publisher": "国土交通省",
        "district_edition": f"N03-{config.N03_EDITION}（第3.1版・データ基準年 令和5年）",
        "district_prefecture_codes": ",".join(config.N03_PREFECTURE_CODES),
        "district_license": "国土数値情報 利用規約（令和元年以降オープンデータ）。"
        "測量法に基づく国土地理院長承認（複製）が必要な原典表示あり（README参照）",
        "district_simplify_tolerance_m": str(config.DISTRICT_SIMPLIFY_TOLERANCE_M),
        "district_count": str(len(districts)),
        "hex_district_assigned_count": str(len(hex_district)),
        "hex_district_unassigned_count": str(unassigned),
        "vertices_before_simplify": str(vertices_before),
        "vertices_after_simplify": str(vertices_after),
        "generated_at_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "generation_seconds": f"{elapsed:.3f}",
        "topojson_version": _pkg_version("topojson"),
        "shapely_version": _pkg_version("shapely"),
        "h3_py_version": _pkg_version("h3"),
    }
    for pref, sha in n03_sha256.items():
        meta[f"n03_sha256_{pref}"] = sha

    log(f"writing SQLite -> {out_path}")
    write_sqlite(out_path, districts, hex_district, meta)

    out_size = out_path.stat().st_size
    log(f"DONE in {elapsed:.2f}s. districts={len(districts)} out_size={out_size} bytes")
    print(json.dumps({**meta, "out_size_bytes": out_size, "out_path": str(out_path)}, ensure_ascii=False, indent=2))


def _count_vertices(g: "shapely.Geometry") -> int:
    if g.geom_type == "Polygon":
        return len(g.exterior.coords) + sum(len(r.coords) for r in g.interiors)
    if g.geom_type == "MultiPolygon":
        return sum(_count_vertices(p) for p in g.geoms)
    return len(getattr(g, "coords", []))


def _pkg_version(name: str) -> str:
    try:
        import importlib.metadata as im

        return im.version(name)
    except Exception:
        return "unknown"


if __name__ == "__main__":
    main()
