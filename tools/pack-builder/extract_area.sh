#!/usr/bin/env bash
# tools/pack-builder/extract_area.sh
#
# download_kanto.sh で取得した関東地方OSM抽出から、config.py の bbox（対象エリア）だけを
# osmium extract で切り出す。
#
# 前提: `osmium` コマンド（osmium-tool）が使えること。
#   - sudo が使える環境: `sudo apt-get install osmium-tool` を先に実行しておけばよい
#     （README.md 参照）。この場合、以下の OSMIUM_BIN / LD_LIBRARY_PATH の指定は不要。
#   - sudo が使えない環境（本Issueの検証環境）: README.md の
#     「osmium-tool を sudo なしでローカルに用意する」手順に従って
#     OSMIUM_BIN と LD_LIBRARY_PATH を環境変数で指定して実行すること。
#
# 例:
#   OSMIUM_BIN=/tmp/osmium_local/extracted/usr/bin/osmium \
#   LD_LIBRARY_PATH=/tmp/osmium_local/extracted/usr/lib/x86_64-linux-gnu \
#   bash extract_area.sh

set -euo pipefail
cd "$(dirname "$0")"

OSMIUM_BIN="${OSMIUM_BIN:-osmium}"

BBOX="139.352,35.7675,139.408,35.8125"  # config.py の OSMIUM_EXTRACT_BBOX と一致させること

echo "Extracting bbox=${BBOX} from data_cache/kanto-latest.osm.pbf ..."
time "$OSMIUM_BIN" extract -b "$BBOX" data_cache/kanto-latest.osm.pbf \
  -o data_cache/area.osm.pbf -s smart --overwrite

"$OSMIUM_BIN" fileinfo -e data_cache/area.osm.pbf
