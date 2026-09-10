#!/usr/bin/env bash
# tools/pack-builder/build_vector_tiles.sh — Issue #85・T039
#
# OSM抽出（extract_area.sh の出力）から、Planetiler（Java製）で表示専用のベクタタイル
# MBTilesを生成する。plan.md §3.2「地域パックの内容物」の1行目「ベクタタイル（表示専用）
# / MBTiles（第一候補） / Planetiler（OSM日本抽出）」に対応する。
#
# ⚠️ ここで生成するMBTilesは「表示専用」の基盤地図タイル（建物・道路・landuse等）である。
# fog of war 用のヘクス地形属性（hex_terrain）とは別物であり、混同しないこと
# （T043・hex_bridge.py・export_hex_geojson.py 参照。fog of war は
# 実行時に location/ が hex_terrain から GeoJSON を組み立てて addGeoJsonSource する — plan.md §8）。
#
# 使うプロファイル: Planetiler本体（planetiler.jar）が標準で内蔵している
# OpenMapTiles互換スキーマ（`com.onthegomap.planetiler.Main` の既定エントリポイント）。
# 自前のカスタムプロファイル（Javaコードを書く）ではなくこちらを採用した理由:
#   - T055（地図表示・本Issueのスコープ外）が既存のOpenMapTiles系スタイル
#     （OSM Liberty等）をそのまま使える。plan.md §11 も
#     「OpenMapTiles系スキーマ利用時は『© OpenMapTiles』を追加」を既に想定している。
#   - 自前スキーマにすると、T055側でレイヤ名・属性名の設計からやり直す必要が生じ、
#     本Issueのスコープ（T055には踏み込まない）を超える。
# トレードオフ: 標準プロファイルは lake_centerlines・water_polygons・natural_earth という
# 世界共通の補助データセット（合計約1.4GB）を必要とする。エリアに依らず1回だけ
# 取得すればよいため、download_kanto.sh と同じ考え方でキャッシュする
# （config.PLANETILER_SOURCES_DIR・.gitignore 済み）。
#
# 前提:
#   - extract_area.sh 済みで config.AREA_PBF_PATH（data_cache/area.osm.pbf）が存在すること
#   - JDK 21（本プロジェクトの既定。docs/dev-setup.md §2）
#
# ⚠️ JDKの罠（docs/dev-setup.md §2 参照）: 対話シェルでは sdkman が JAVA_HOME を
# JDK17に固定するため、`java -version` が21を返してもGradle等が17で動くことがある。
# 本スクリプトは `java`（PATH経由）をそのまま使い、$JAVA_HOME 経由では起動しない。
# 対話シェルで実行して失敗する場合は、下記のように JAVA_HOME を明示的に上書きすること:
#   JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64 \
#     PATH=$(echo "$PATH" | tr ':' '\n' | grep -v sdkman | paste -sd:) \
#     bash build_vector_tiles.sh
#
# 使い方:
#   bash build_vector_tiles.sh [出力パス(既定: out/tiles.mbtiles)] [入力pbf(既定: config.AREA_PBF_PATH)]

set -euo pipefail
cd "$(dirname "$0")"

OUT_PATH="${1:-out/tiles.mbtiles}"
INPUT_PBF="${2:-data_cache/area.osm.pbf}"

PLANETILER_VERSION="0.10.2"
PLANETILER_JAR="data_cache/planetiler-${PLANETILER_VERSION}.jar"
PLANETILER_JAR_URL="https://github.com/onthegomap/planetiler/releases/download/v${PLANETILER_VERSION}/planetiler.jar"
SOURCES_DIR="data_cache/planetiler_sources"
TMP_DIR="data_cache/planetiler_tmp"

# --- JDKバージョンチェック（docs/dev-setup.md の罠を踏まないための早期検出）----
if ! command -v java >/dev/null 2>&1; then
  echo "ERROR: java が見つかりません。JDK 21 をインストールしてください（docs/dev-setup.md §2）。" >&2
  exit 1
fi
JAVA_VERSION_LINE="$(java -version 2>&1 | head -1)"
if ! echo "$JAVA_VERSION_LINE" | grep -q '"21\.'; then
  echo "ERROR: java -version が21系ではありません: ${JAVA_VERSION_LINE}" >&2
  echo "  本プロジェクトの既定JDKは21です（docs/dev-setup.md §2・Issue #55）。" >&2
  echo "  対話シェルでsdkmanがJDK17を優先している場合は、次のように上書きしてください:" >&2
  echo "    JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64 \\" >&2
  echo "      PATH=\$(echo \"\$PATH\" | tr ':' '\\n' | grep -v sdkman | paste -sd:) \\" >&2
  echo "      bash build_vector_tiles.sh" >&2
  exit 1
fi
echo "OK: ${JAVA_VERSION_LINE}"

if [ ! -f "$INPUT_PBF" ]; then
  echo "ERROR: 入力OSM抽出が見つかりません: $INPUT_PBF" >&2
  echo "  先に 'bash download_kanto.sh && bash extract_area.sh' を実行してください。" >&2
  exit 1
fi

# --- planetiler.jar の取得（初回のみ・以後は data_cache に再利用）--------------
mkdir -p data_cache "$SOURCES_DIR" "$TMP_DIR" out
if [ ! -f "$PLANETILER_JAR" ]; then
  echo "Downloading planetiler.jar v${PLANETILER_VERSION} ..."
  curl -fL --progress-bar -o "$PLANETILER_JAR" "$PLANETILER_JAR_URL"
fi

# --- 補助データセット（初回のみ・世界共通・以後は再利用）----------------------
# lake_centerline.shp.zip・water-polygons-split-3857.zip・natural_earth_vector.sqlite.zip
# は Planetiler標準プロファイルが常に要求する（--only_layers で絞ってもこの3つの
# フェーズ自体は無条件に実行されるため、layer選択では回避できないことを実機確認済み）。
# 合計約1.4GB。エリアを変えても再ダウンロード不要なため、data_cache に永続化する。
NEED_DOWNLOAD=false
for f in lake_centerline.shp.zip water-polygons-split-3857.zip natural_earth_vector.sqlite.zip; do
  if [ ! -f "$SOURCES_DIR/$f" ]; then
    NEED_DOWNLOAD=true
  fi
done

DOWNLOAD_FLAG=""
if [ "$NEED_DOWNLOAD" = "true" ]; then
  echo "補助データセット（lake_centerlines/water_polygons/natural_earth、合計約1.4GB）を取得します（初回のみ）..."
  DOWNLOAD_FLAG="--download"
fi

echo "Building vector tiles: $INPUT_PBF -> $OUT_PATH"
time java -jar "$PLANETILER_JAR" \
  --osm_path="$INPUT_PBF" \
  --output="$OUT_PATH" \
  --download_dir="$SOURCES_DIR" \
  --tmpdir="$TMP_DIR" \
  --force \
  $DOWNLOAD_FLAG

echo "DONE."
ls -la "$OUT_PATH"
