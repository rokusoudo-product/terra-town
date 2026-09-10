#!/usr/bin/env bash
# tools/pack-builder/download_n03.sh
#
# 国土数値情報 N03（行政区域データ）の都道府県別 GML をダウンロードする（Issue #86・T041）。
# 対象エリア（config.py の BBOX_*）は埼玉県・東京都にまたがるため、両方の都道府県分を取得する。
#
# ⚠️ 「N03-YYMMDD_{pref}_GML.zip」（6桁日付）という古い命名の版は、実体が
# 「行政区域の変遷（-g）」という別データ（ksj:AdministrativeBoundary。過去の市区町村
# 合併履歴の線データで、現在の行政区域ポリゴンではない）であることを実データ確認済み
# （tools/pack-builder/README.md「データソースとライセンス」参照）。
# 本スクリプトが取得するのは8桁日付（YYYYMMDD）の最新版（第3.1版・データ基準年
# 令和5年）で、これが実際の行政区域ポリゴン（属性 N03_001〜N03_004・N03_007、
# 面データ）を含む正しい版であることを確認済み。
#
# 出力先は config.py の N03_DIR（data_cache配下・.gitignore済み・コミットしないこと）。
# 既にダウンロード・展開済みの場合はスキップする（既存の data_cache を活用し、
# 再ダウンロードを避ける）。

set -euo pipefail
cd "$(dirname "$0")"

N03_DIR="data_cache/n03"
N03_EDITION="20230101"  # config.py の N03_EDITION と一致させること
PREFECTURE_CODES="11 13"  # config.py の N03_PREFECTURE_CODES と一致させること（11=埼玉県, 13=東京都）

mkdir -p "$N03_DIR"

for pref in $PREFECTURE_CODES; do
  zip_path="$N03_DIR/N03-${N03_EDITION}_${pref}_GML.zip"
  extract_dir="$N03_DIR/${pref}"

  if [ -n "$(find "$extract_dir" -name '*.geojson' 2>/dev/null)" ]; then
    echo "cache hit: ${extract_dir} (skip)"
    continue
  fi

  if [ ! -f "$zip_path" ]; then
    echo "Downloading N03 (pref=${pref}, edition=${N03_EDITION}) ..."
    time curl -sSL -o "$zip_path" \
      "https://nlftp.mlit.go.jp/ksj/gml/data/N03/N03-2023/N03-${N03_EDITION}_${pref}_GML.zip"
  fi

  echo "Extracting ${zip_path} -> ${extract_dir} ..."
  mkdir -p "$extract_dir"
  unzip -o "$zip_path" -d "$extract_dir" >/dev/null
done

ls -la "$N03_DIR"/*/*.geojson
