#!/usr/bin/env bash
# tools/pack-builder/bundle_region_pack.sh — Issue #85・T044（Issue #94・#152・#158で拡張）
#
# バーティカルスライス対象エリア（狭山湖周辺・config.AREA_SLUG・2026-09-10 代表決定で
# 本番確定。Issue #85 コメント参照）のパックをエンドツーエンドで生成し、
# app/assets/pack/ に同梱する（＝取得スクリプト。生成物自体はコミットしない。
# spikes/fixtures/fetch_fixtures.sh と同じ考え方）。
#
# 前提: data_cache/kanto-latest.osm.pbf・data_cache/area.osm.pbf が用意済みであること
#   （初回のみ `bash download_kanto.sh && bash extract_area.sh`）。N03（行政区域データ）は
#   本スクリプトが未取得なら自動で `download_n03.sh` を実行する。
#
# 2026-09-13 代表決定（Issue #94・#152・同一コメント）: 行政区域・名所POI（Issue #86で
# 実装済みだったが同梱に未接続）と、ヘクス隣接関係（Issue #152で新設）を、
# **同じ1回のパック作り直しにまとめる**（別々に行うとpack_versionが2回変わるため）。
# 本スクリプトはその統合後の手順である。
#
# 2026-09-13 代表決定（Issue #158・同日別コメント）: 名所POI（Tier 1）に加えて
# Tier 2（神社・寺等）も同じこのパック作り直しで採用し、POI→ヘクス対応（hex_poi）を
# 事前計算して同梱する（extract_poi.py が out/pack.sqlite の hex_terrain に依存する
# ようになったため、classify_terrain.py の後に実行する必要がある。手順の順序自体は
# 元々この並びだったため変更不要）。
#
# 実行内容:
#   1. classify_terrain.py     — 地形属性の事前計算（out/pack.sqlite。cell_terrain込み）
#   2. download_n03.sh         — 国土数値情報N03のダウンロード（未取得時のみ）
#   3. extract_districts.py    — 行政区域ポリゴンの取り込み（out/districts.sqlite）
#   4. extract_poi.py          — 名所POI（Tier 1+2）の抽出とhex_poiの事前計算
#                                 （out/poi.sqlite。out/pack.sqliteのhex_terrainに依存・Issue #158）
#   5. compute_hex_neighbors.py — ヘクス隣接関係の事前計算（out/hex_neighbor.sqlite・Issue #152）
#   6. slim_pack_for_bundle.py — 上記4つ（poi.sqliteのhex_poi含む）を統合し軽量化
#                                 （out/region_pack.sqlite）
#   7. build_vector_tiles.sh   — Planetilerでベクタタイル生成（out/tiles.mbtiles）
#   8. app/assets/pack/ へコピー
#
# **決定論の検証（verify_determinism.py・verify_districts_determinism.py・
# verify_poi_determinism.py・verify_hex_neighbor_determinism.py・
# verify_tiles_determinism.py）は含まれない**（実行に数分かかるため）。
# `.github/workflows/pack-build.yml`・README.md「使い方（エンドツーエンド）」で
# 個別に実行すること。
#
# 使い方:
#   bash bundle_region_pack.sh

set -euo pipefail
cd "$(dirname "$0")"

APP_ASSETS_PACK_DIR="../../app/assets/pack"

if [ ! -f data_cache/area.osm.pbf ]; then
  echo "ERROR: data_cache/area.osm.pbf が見つかりません。" >&2
  echo "  先に 'bash download_kanto.sh && bash extract_area.sh' を実行してください。" >&2
  exit 1
fi

echo "=== 1/8: 地形属性の事前計算（classify_terrain.py） ==="
./.venv/bin/python classify_terrain.py

echo
echo "=== 2/8: 国土数値情報N03のダウンロード（download_n03.sh・未取得時のみ） ==="
bash download_n03.sh

echo
echo "=== 3/8: 行政区域ポリゴンの取り込み（extract_districts.py・Issue #86/#94） ==="
./.venv/bin/python extract_districts.py

echo
echo "=== 4/8: 名所POI（Tier1+2）の抽出とhex_poiの事前計算（extract_poi.py・Issue #86/#94/#158） ==="
./.venv/bin/python extract_poi.py

echo
echo "=== 5/8: ヘクス隣接関係の事前計算（compute_hex_neighbors.py・Issue #152） ==="
./.venv/bin/python compute_hex_neighbors.py

echo
echo "=== 6/8: 統合・同梱用に軽量化（slim_pack_for_bundle.py） ==="
./.venv/bin/python slim_pack_for_bundle.py

echo
echo "=== 7/8: ベクタタイル生成（build_vector_tiles.sh・Planetiler） ==="
bash build_vector_tiles.sh out/tiles.mbtiles

echo
echo "=== 8/8: app/assets/pack/ へ同梱 ==="
mkdir -p "$APP_ASSETS_PACK_DIR"
cp out/region_pack.sqlite "$APP_ASSETS_PACK_DIR/region_pack.sqlite"
cp out/tiles.mbtiles "$APP_ASSETS_PACK_DIR/tiles.mbtiles"

echo
echo "=== DONE ==="
HEX_COUNT="$(./.venv/bin/python -c "import sqlite3; print(sqlite3.connect('out/region_pack.sqlite').execute('SELECT COUNT(*) FROM hex_terrain').fetchone()[0])")"
DISTRICT_COUNT="$(./.venv/bin/python -c "import sqlite3; print(sqlite3.connect('out/region_pack.sqlite').execute('SELECT COUNT(*) FROM district').fetchone()[0])")"
POI_COUNT="$(./.venv/bin/python -c "import sqlite3; print(sqlite3.connect('out/region_pack.sqlite').execute('SELECT COUNT(*) FROM poi').fetchone()[0])")"
HEX_NEIGHBOR_COUNT="$(./.venv/bin/python -c "import sqlite3; print(sqlite3.connect('out/region_pack.sqlite').execute('SELECT COUNT(*) FROM hex_neighbor').fetchone()[0])")"
PACK_VERSION="$(./.venv/bin/python -c "import sqlite3; print(sqlite3.connect('out/region_pack.sqlite').execute(\"SELECT value FROM pack_meta WHERE key='pack_version'\").fetchone()[0])")"
echo "hex_count       = ${HEX_COUNT}"
echo "district_count  = ${DISTRICT_COUNT}"
echo "poi_count       = ${POI_COUNT}"
echo "hex_neighbor_count = ${HEX_NEIGHBOR_COUNT}"
echo "pack_version    = ${PACK_VERSION}"
echo "region_pack.sqlite = $(du -h "$APP_ASSETS_PACK_DIR/region_pack.sqlite" | cut -f1)"
echo "tiles.mbtiles       = $(du -h "$APP_ASSETS_PACK_DIR/tiles.mbtiles" | cut -f1)"
echo
echo "同梱先: $APP_ASSETS_PACK_DIR/ （コミットしないこと。.gitignore 済み）"
