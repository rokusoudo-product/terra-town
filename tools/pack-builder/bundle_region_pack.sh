#!/usr/bin/env bash
# tools/pack-builder/bundle_region_pack.sh — Issue #85・T044
#
# バーティカルスライス対象エリア（狭山湖周辺・config.AREA_SLUG・2026-09-10 代表決定で
# 本番確定。Issue #85 コメント参照）のパックをエンドツーエンドで生成し、
# app/assets/pack/ に同梱する（＝取得スクリプト。生成物自体はコミットしない。
# spikes/fixtures/fetch_fixtures.sh と同じ考え方）。
#
# 前提: data_cache/kanto-latest.osm.pbf・data_cache/area.osm.pbf が用意済みであること
#   （初回のみ `bash download_kanto.sh && bash extract_area.sh`）。
#
# 実行内容:
#   1. classify_terrain.py    — 地形属性の事前計算（out/pack.sqlite。cell_terrain込み）
#   2. slim_pack_for_bundle.py — 同梱用に軽量化（out/region_pack.sqlite。hex_terrain+pack_metaのみ）
#   3. build_vector_tiles.sh  — Planetilerでベクタタイル生成（out/tiles.mbtiles）
#   4. app/assets/pack/ へコピー
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

echo "=== 1/4: 地形属性の事前計算（classify_terrain.py） ==="
./.venv/bin/python classify_terrain.py

echo
echo "=== 2/4: 同梱用に軽量化（slim_pack_for_bundle.py） ==="
./.venv/bin/python slim_pack_for_bundle.py

echo
echo "=== 3/4: ベクタタイル生成（build_vector_tiles.sh・Planetiler） ==="
bash build_vector_tiles.sh out/tiles.mbtiles

echo
echo "=== 4/4: app/assets/pack/ へ同梱 ==="
mkdir -p "$APP_ASSETS_PACK_DIR"
cp out/region_pack.sqlite "$APP_ASSETS_PACK_DIR/region_pack.sqlite"
cp out/tiles.mbtiles "$APP_ASSETS_PACK_DIR/tiles.mbtiles"

echo
echo "=== DONE ==="
HEX_COUNT="$(./.venv/bin/python -c "import sqlite3; print(sqlite3.connect('out/region_pack.sqlite').execute('SELECT COUNT(*) FROM hex_terrain').fetchone()[0])")"
PACK_VERSION="$(./.venv/bin/python -c "import sqlite3; print(sqlite3.connect('out/region_pack.sqlite').execute(\"SELECT value FROM pack_meta WHERE key='pack_version'\").fetchone()[0])")"
echo "hex_count       = ${HEX_COUNT}"
echo "pack_version    = ${PACK_VERSION}"
echo "region_pack.sqlite = $(du -h "$APP_ASSETS_PACK_DIR/region_pack.sqlite" | cut -f1)"
echo "tiles.mbtiles       = $(du -h "$APP_ASSETS_PACK_DIR/tiles.mbtiles" | cut -f1)"
echo
echo "同梱先: $APP_ASSETS_PACK_DIR/ （コミットしないこと。.gitignore 済み）"
