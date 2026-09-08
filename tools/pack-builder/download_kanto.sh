#!/usr/bin/env bash
# tools/pack-builder/download_kanto.sh
#
# Geofabrik の関東地方OSM抽出（.osm.pbf）をダウンロードする。
# 対象エリア（config.py の BBOX_*）は関東地方に含まれるため、この地方単位の抽出を
# ベースに osmium extract で bbox 切り出しを行う（extract_area.sh）。
#
# 出力先は config.py の DATA_CACHE_DIR（.gitignore 済み・コミットしないこと）。
#
# 所要時間の目安: 約2分（約477MiB、2026-09-08計測。回線速度に依存）。

set -euo pipefail
cd "$(dirname "$0")"

mkdir -p data_cache
echo "Downloading kanto-latest.osm.pbf from Geofabrik ..."
time curl -sSL -o data_cache/kanto-latest.osm.pbf \
  https://download.geofabrik.de/asia/japan/kanto-latest.osm.pbf

ls -la data_cache/kanto-latest.osm.pbf
