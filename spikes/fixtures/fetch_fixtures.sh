#!/usr/bin/env bash
# spikes/map_spike_gl・spikes/map_spike_josxha のMBTiles/PMTiles読込テスト用フィクスチャを
# 取得するスクリプト。
#
# 【重要】取得したファイルはリポジトリにコミットしないこと（.gitignoreで除外済み）。
# 地域パック（tools/pack-builder/）はまだ存在しないため、terra-town独自のデータではなく、
# MapLibreプロジェクト公式が配布する軽量サンプルを使う。
#
# 出典・ライセンス:
#   - リポジトリ: https://github.com/maplibre/demotiles （コード: BSD-3-Clause）
#   - 地図データ: Natural Earth Data (https://www.naturalearthdata.com/) — パブリックドメイン
#     （"No permission is needed to use Natural Earth. Crediting the authors is unnecessary."）
#   - maplibre.mbtiles: ベクタタイル, z0-6, 約5MB
#     https://github.com/maplibre/demotiles/releases/download/v1.0/maplibre.mbtiles
#   - world.pmtiles: 同データのPMTiles版, 約3.8MB
#     https://demotiles.maplibre.org/pmtiles/vector/world.pmtiles
#
# 探索方針（時間を区切って対応・README参照）: 地域パック未実装のため実データは存在しない。
# 「軽量・入手元が明確・ライセンスがクリア」を条件に、MapLibre公式配布のサンプルのみを対象にした。
# 大きめのOSM由来サンプル（klokantech/vector-tiles-sample の countries.mbtiles 等）も検討したが、
# 出典・更新状況の確認にさらに時間がかかるため、今回は見送った。

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT_DIR="$SCRIPT_DIR"

MBTILES_URL="https://github.com/maplibre/demotiles/releases/download/v1.0/maplibre.mbtiles"
PMTILES_URL="https://demotiles.maplibre.org/pmtiles/vector/world.pmtiles"

echo "== MBTiles取得: $MBTILES_URL"
curl -fL --progress-bar -o "$OUT_DIR/sample.mbtiles" "$MBTILES_URL"
echo "-> $OUT_DIR/sample.mbtiles ($(du -h "$OUT_DIR/sample.mbtiles" | cut -f1))"

echo "== PMTiles取得: $PMTILES_URL"
curl -fL --progress-bar -o "$OUT_DIR/sample.pmtiles" "$PMTILES_URL"
echo "-> $OUT_DIR/sample.pmtiles ($(du -h "$OUT_DIR/sample.pmtiles" | cut -f1))"

echo
echo "完了。map_spike_gl / map_spike_josxha アプリの各パス入力欄に以下を指定してください:"
echo "  MBTiles: $OUT_DIR/sample.mbtiles"
echo "  PMTiles: $OUT_DIR/sample.pmtiles"
echo
echo "（Androidアプリからアクセスする場合は、この絶対パスが端末側から見えないため、"
echo " adb push でアプリの外部ストレージ領域等へ転送してから、そのパスを指定すること）"
