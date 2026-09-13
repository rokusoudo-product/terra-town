#!/usr/bin/env python3
"""tools/pack-builder/slim_pack_for_bundle.py — 同梱用の region_pack.sqlite を組み立てる。

Issue #85・T044（当初の役割）: `classify_terrain.py` の出力（`out/pack.sqlite`）は
`cell_terrain`（生成過程の中間データ。細分グリッドセル単位、5m四方で約100万行）を
含むため約63MBになる。しかし `app/assets/` に同梱する必要があるのは
`hex_terrain`（H3ヘクス単位に集約済みの最終結果。`boundary_geojson`列＝fog of war用の
ヘクス境界を含む・Issue #105）と `pack_meta` だけであり、`cell_terrain` を落とすと
大幅に縮む。

Issue #94・#152（2026-09-13代表決定・本ファイルの役割拡張）: 行政区域・名所POI
（`extract_districts.py`・`extract_poi.py`・Issue #86/PR #93で実装済みだったが
同梱に未接続だった）と、ヘクス隣接関係（`compute_hex_neighbors.py`・Issue #152で新設）を
同じ `region_pack.sqlite` に統合する。**#94と#152は同じパック作り直しにまとめること
という代表決定（pack_versionが2回変わるのを避ける）に従い、本ファイルが両方の
統合窓口を1本化する。**

入力（すべて `out/` 配下。無い場合はエラーで停止し、生成元スクリプトを案内する）:
  - `pack.sqlite`        — `classify_terrain.py`（`hex_terrain`・`pack_meta`）
  - `districts.sqlite`   — `extract_districts.py`（`district`・`hex_district`・`pack_meta`）
  - `poi.sqlite`         — `extract_poi.py`（`poi`・`pack_meta`）
  - `hex_neighbor.sqlite`— `compute_hex_neighbors.py`（`hex_neighbor`・`pack_meta`）

出力: `region_pack.sqlite`（テーブル: hex_terrain, district, hex_district, poi,
hex_neighbor, pack_meta）

## 統合前の整合性チェック（fail-loud。advisor 2026-09-13 指摘を反映）

4つの入力は別々のスクリプト・別々の実行時刻で生成されうるため、統合前に
「同じ世代のものか」を機械的に検証する。検証せずに黙って統合すると、
例えば「古い`districts.sqlite`と新しい`pack.sqlite`を組み合わせた
中身の壊れたパックが、エラーなく生成されてしまう」事故になりうる。

- `poi.sqlite`の`input_pbf_sha256`が`pack.sqlite`のそれと一致すること
  （両方とも`config.AREA_PBF_PATH`＝同じ`area.osm.pbf`から生成されるはず）。
- `hex_neighbor.sqlite`の`hex_neighbor`のhex_id集合が、`pack.sqlite`の
  `hex_terrain`のhex_id集合と**完全一致**すること（`compute_hex_neighbors.py`は
  全ヘクスに1行書き込むため、部分一致は「古い入力から生成された」ことを意味する）。
- `districts.sqlite`の`hex_district`のhex_id集合が、`hex_terrain`のhex_id集合の
  **部分集合**であること（区画に帰属しないヘクス〔水域等〕がある一方、
  パックに存在しないヘクスへの帰属は不整合）。
- `districts.sqlite`の`pack_meta`に`n03_sha256_11`・`n03_sha256_13`
  （`config.N03_PREFECTURE_CODES`の全件）が存在すること（`pack_version`の算出に
  必須の入力。`extract_districts.py`自体もfail-loudで検証しているが、
  古い`districts.sqlite`をそのまま使い回すケースに備えて統合時にも再検証する）。

## 統合後の`pack_version`（Issue #94・2026-09-13代表決定）

`classify_terrain.py`が計算する`pack_version`（地形判定ルール・OSM抽出のみを
入力とする）を**そのまま使わず**、本ファイルがN03・POI抽出ルールの入力も含めて
**組み直す**。含める入力の一覧（`tools/pack-builder/README.md`「pack_version」節にも
明記）:

1. `input_pbf_sha256`（`area.osm.pbf`。地形・POI抽出の入力）
2. `n03_sha256_11`・`n03_sha256_13`（N03行政区域データ、都道府県別GMLzip）
3. `poi_rules_sha256`（`poi_rules.py`のファイル内容のsha256。POI抽出ルールの変更を
   捕捉するため）

`{AREA_SLUG}-v{PACK_SCHEMA_VERSION}-{上記4値を連結してsha256した先頭12桁}`という
形式（`classify_terrain.py`と同じ「生成時刻に依存しない純関数」という設計方針を踏襲）。
**中間生成物`out/pack.sqlite`の`pack_meta.pack_version`は`classify_terrain.py`が
計算した値（N03/POI/隣接を含まない）のまま**であり、同梱物`region_pack.sqlite`の
`pack_version`とは値が異なる。これは意図した挙動である（`out/pack.sqlite`は
地形属性のみの中間生成物であり、統合後の値は本ファイルの責務）。

`hex_neighbor`（H3の隣接計算）は`hex_terrain`のヘクス集合とH3ライブラリのみに
依存する純関数であり、既存の`input_pbf_sha256`で入力が捕捉済みのため、
`pack_version`の追加入力にはしていない（h3ライブラリのバージョンは
`hex_neighbor_h3_py_version`として`pack_meta`に記録するのみ）。

使い方:
    ./.venv/bin/python slim_pack_for_bundle.py
"""

from __future__ import annotations

import argparse
import hashlib
import sqlite3
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent


def log(msg: str) -> None:
    print(f"[slim_pack_for_bundle] {msg}", file=sys.stderr, flush=True)


def sha256_of_file(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def read_meta(path: Path) -> dict[str, str]:
    conn = sqlite3.connect(str(path))
    try:
        return dict(conn.execute("SELECT key, value FROM pack_meta").fetchall())
    finally:
        conn.close()


def read_hex_id_set(path: Path, table: str) -> set[int]:
    conn = sqlite3.connect(str(path))
    try:
        return {row[0] for row in conn.execute(f"SELECT hex_id FROM {table}")}
    finally:
        conn.close()


def verify_inputs_consistent(
    pack_path: Path,
    districts_path: Path,
    poi_path: Path,
    hex_neighbor_path: Path,
    pack_meta: dict[str, str],
    districts_meta: dict[str, str],
    poi_meta: dict[str, str],
) -> None:
    """4入力が同じ世代のものであることを検証する（本ファイルdocstring参照）。不整合はfail-loud。"""

    pack_input_sha = pack_meta.get("input_pbf_sha256")
    poi_input_sha = poi_meta.get("input_pbf_sha256")
    if pack_input_sha != poi_input_sha:
        raise AssertionError(
            f"poi.sqlite の input_pbf_sha256（{poi_input_sha}）が pack.sqlite のそれ"
            f"（{pack_input_sha}）と一致しません。classify_terrain.py と extract_poi.py を"
            "同じ area.osm.pbf に対して再実行してください。"
        )

    hex_terrain_ids = read_hex_id_set(pack_path, "hex_terrain")
    hex_neighbor_ids = read_hex_id_set(hex_neighbor_path, "hex_neighbor")
    if hex_neighbor_ids != hex_terrain_ids:
        missing = hex_terrain_ids - hex_neighbor_ids
        extra = hex_neighbor_ids - hex_terrain_ids
        raise AssertionError(
            "hex_neighbor.sqlite の hex_id 集合が pack.sqlite の hex_terrain と一致しません "
            f"(不足={len(missing)}件, 余剰={len(extra)}件)。compute_hex_neighbors.py を "
            "現在の out/pack.sqlite に対して再実行してください。"
        )

    hex_district_ids = read_hex_id_set(districts_path, "hex_district")
    if not hex_district_ids.issubset(hex_terrain_ids):
        extra = hex_district_ids - hex_terrain_ids
        raise AssertionError(
            f"districts.sqlite の hex_district に pack.sqlite の hex_terrain に存在しない "
            f"hex_id が{len(extra)}件あります。extract_districts.py を現在の out/pack.sqlite "
            "に対して再実行してください。"
        )

    for pref in ("11", "13"):
        if f"n03_sha256_{pref}" not in districts_meta:
            raise AssertionError(
                f"districts.sqlite の pack_meta に n03_sha256_{pref} がありません。"
                "pack_version の算出に必須の入力です。download_n03.sh で N03 GML zip を"
                "復元したうえで extract_districts.py を再実行してください。"
            )


def compute_merged_pack_version(
    pack_meta: dict[str, str], districts_meta: dict[str, str]
) -> tuple[str, dict[str, str]]:
    """N03・POI抽出ルールの入力を含めて pack_version を組み直す（本ファイルdocstring参照）。"""

    area_slug = pack_meta["area_slug"]
    schema_version = pack_meta["pack_schema_version"]
    input_pbf_sha256 = pack_meta["input_pbf_sha256"]
    n03_sha256_11 = districts_meta["n03_sha256_11"]
    n03_sha256_13 = districts_meta["n03_sha256_13"]
    poi_rules_sha256 = sha256_of_file(HERE / "poi_rules.py")

    combined = hashlib.sha256(
        f"{input_pbf_sha256}:{n03_sha256_11}:{n03_sha256_13}:{poi_rules_sha256}".encode("ascii")
    ).hexdigest()
    pack_version = f"{area_slug}-v{schema_version}-{combined[:12]}"

    audit_keys = {
        "pack_version_input_pbf_sha256": input_pbf_sha256,
        "pack_version_n03_sha256_11": n03_sha256_11,
        "pack_version_n03_sha256_13": n03_sha256_13,
        "pack_version_poi_rules_sha256": poi_rules_sha256,
    }
    return pack_version, audit_keys


def _prefixed(meta: dict[str, str], prefix: str, already_prefixed_keys: set[str]) -> dict[str, str]:
    """`meta`のキーのうち`already_prefixed_keys`に無いものへ`prefix`を付け直す。

    4入力のpack_metaはそれぞれ独立したスクリプトが書いており、
    `generated_at_utc`・`generation_seconds`・`h3_py_version`・`shapely_version`・
    `osmium_version`・`input_pbf`・`input_pbf_sha256`のような**共通の列名**を
    複数の入力が持つ（例: pack.sqlite/poi.sqliteの両方に`input_pbf_sha256`がある）。
    単純に全メタを1つのpack_metaテーブルへ`INSERT`すると、後勝ちで上書きされ
    「どの入力のどの値か」が失われる（advisor 2026-09-13指摘）。そのため、
    まだプレフィックスの付いていないキーにのみ`prefix`を付けて名前空間を分離する。
    """
    result = {}
    for k, v in meta.items():
        key = k if k in already_prefixed_keys or k.startswith(prefix) else f"{prefix}{k}"
        result[key] = v
    return result


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pack-sqlite", default=str(HERE / "out" / "pack.sqlite"))
    parser.add_argument("--districts-sqlite", default=str(HERE / "out" / "districts.sqlite"))
    parser.add_argument("--poi-sqlite", default=str(HERE / "out" / "poi.sqlite"))
    parser.add_argument("--hex-neighbor-sqlite", default=str(HERE / "out" / "hex_neighbor.sqlite"))
    parser.add_argument("--out", default=str(HERE / "out" / "region_pack.sqlite"))
    args = parser.parse_args()

    pack_path = Path(args.pack_sqlite)
    districts_path = Path(args.districts_sqlite)
    poi_path = Path(args.poi_sqlite)
    hex_neighbor_path = Path(args.hex_neighbor_sqlite)
    out_path = Path(args.out)

    for path, generator in [
        (pack_path, "classify_terrain.py"),
        (districts_path, "extract_districts.py"),
        (poi_path, "extract_poi.py"),
        (hex_neighbor_path, "compute_hex_neighbors.py"),
    ]:
        if not path.exists():
            log(f"input not found: {path}. 先に {generator} を実行してください。")
            sys.exit(1)

    out_path.parent.mkdir(parents=True, exist_ok=True)
    if out_path.exists():
        out_path.unlink()

    pack_meta = read_meta(pack_path)
    districts_meta = read_meta(districts_path)
    poi_meta = read_meta(poi_path)
    hex_neighbor_meta = read_meta(hex_neighbor_path)

    log("verifying the 4 inputs are from the same generation (fail-loud consistency checks) ...")
    verify_inputs_consistent(
        pack_path, districts_path, poi_path, hex_neighbor_path, pack_meta, districts_meta, poi_meta
    )
    log("  consistency OK")

    pack_version, pack_version_audit = compute_merged_pack_version(pack_meta, districts_meta)
    log(f"merged pack_version = {pack_version}")

    src = sqlite3.connect(str(pack_path))
    dst = sqlite3.connect(str(out_path))
    try:
        dst.execute("ATTACH DATABASE ? AS src_pack", (str(pack_path),))
        dst.execute("ATTACH DATABASE ? AS src_districts", (str(districts_path),))
        dst.execute("ATTACH DATABASE ? AS src_poi", (str(poi_path),))
        dst.execute("ATTACH DATABASE ? AS src_neighbor", (str(hex_neighbor_path),))

        # --- hex_terrain（cell_terrainを除いた地形属性。Issue #85・T044の元の役割） ---
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
        dst.execute("INSERT INTO hex_terrain SELECT * FROM src_pack.hex_terrain")

        # --- district / hex_district（Issue #94・extract_districts.pyの出力を統合） ---
        dst.execute(
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
        dst.execute(
            "CREATE TABLE hex_district (hex_id INTEGER PRIMARY KEY, district_id TEXT NOT NULL)"
        )
        dst.execute("CREATE INDEX idx_hex_district_district_id ON hex_district(district_id)")
        dst.execute("INSERT INTO district SELECT * FROM src_districts.district")
        dst.execute("INSERT INTO hex_district SELECT * FROM src_districts.hex_district")

        # --- poi（Issue #94・extract_poi.pyの出力を統合） ---
        dst.execute(
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
        dst.execute("INSERT INTO poi SELECT * FROM src_poi.poi")

        # --- hex_neighbor（Issue #152・compute_hex_neighbors.pyの出力を統合） ---
        dst.execute(
            """
            CREATE TABLE hex_neighbor (
                hex_id INTEGER PRIMARY KEY,
                neighbor_count INTEGER NOT NULL,
                neighbor_hex_ids TEXT NOT NULL
            )
            """
        )
        dst.execute("INSERT INTO hex_neighbor SELECT * FROM src_neighbor.hex_neighbor")

        # --- pack_meta（4入力の名前空間分離 + 統合pack_version。本ファイルdocstring参照） ---
        dst.execute("CREATE TABLE pack_meta (key TEXT PRIMARY KEY, value TEXT)")

        district_already_prefixed = {k for k in districts_meta if k.startswith("district_")} | {
            "hex_district_assigned_count",
            "hex_district_unassigned_count",
            "n03_sha256_11",
            "n03_sha256_13",
        }
        merged_meta: dict[str, str] = {}
        merged_meta.update(pack_meta)  # 地形属性側は無印のまま（元々の同梱物の主とみなす）。
        merged_meta.update(_prefixed(districts_meta, "district_", district_already_prefixed))
        merged_meta.update(_prefixed(poi_meta, "poi_", {k for k in poi_meta if k.startswith("poi_")}))
        merged_meta.update(
            _prefixed(
                hex_neighbor_meta,
                "hex_neighbor_",
                {k for k in hex_neighbor_meta if k.startswith("hex_neighbor_")},
            )
        )
        merged_meta["pack_version"] = pack_version
        merged_meta.update(pack_version_audit)
        merged_meta["bundle_kind"] = "region_pack_slim"
        merged_meta["bundle_note"] = (
            "cell_terrainを除いた同梱用サブセット + district/hex_district/poi/hex_neighborを統合"
            "（tools/pack-builder/slim_pack_for_bundle.py・Issue #94/#152）"
        )

        dst.executemany(
            "INSERT INTO pack_meta (key, value) VALUES (?, ?)", list(merged_meta.items())
        )

        dst.commit()
        dst.execute("DETACH DATABASE src_pack")
        dst.execute("DETACH DATABASE src_districts")
        dst.execute("DETACH DATABASE src_poi")
        dst.execute("DETACH DATABASE src_neighbor")
        dst.execute("VACUUM")
    finally:
        src.close()
        dst.close()

    conn = sqlite3.connect(str(out_path))
    try:
        hex_count = conn.execute("SELECT COUNT(*) FROM hex_terrain").fetchone()[0]
        district_count = conn.execute("SELECT COUNT(*) FROM district").fetchone()[0]
        poi_count = conn.execute("SELECT COUNT(*) FROM poi").fetchone()[0]
        hex_neighbor_count = conn.execute("SELECT COUNT(*) FROM hex_neighbor").fetchone()[0]
    finally:
        conn.close()

    out_size = out_path.stat().st_size
    in_size = pack_path.stat().st_size
    log(
        f"DONE. {pack_path} ({in_size} bytes) + districts/poi/hex_neighbor -> {out_path} "
        f"({out_size} bytes). hex_terrain={hex_count} district={district_count} "
        f"poi={poi_count} hex_neighbor={hex_neighbor_count} pack_version={pack_version}"
    )


if __name__ == "__main__":
    main()
