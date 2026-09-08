"""tools/pack-builder/ 最小プロトタイプの設定値（Issue #38）。

対象エリアの座標は「代表の生活圏の確定を待たず、仮座標で先に通してよい」
（Issue #38 2026-08-11 代表回答）という前提のもと、**仮の座標**として
埼玉県狭山市〜東京都瑞穂町にまたがる狭山湖（山口貯水池）周辺を採用している。

このエリアを選んだ理由（plan.md §15 の要求「水辺・緑地・農地・市街が混在する範囲」に対応）:
- 水辺: 狭山湖（人造湖・natural=water）
- 緑地/森: 狭山丘陵の樹林地（landuse=forest, natural=wood）
- 農地: 狭山茶の茶畑（landuse=farmland 等）
- 市街: 周辺の住宅地・商業施設（landuse=residential 等、コストコ入間倉庫店・
  三井アウトレットパーク入間など landuse=retail の郊外型店舗も存在）

**本番のバーティカルスライス対象エリア（代表の生活圏）とは異なる仮座標である。**
代表の生活圏が確定した時点で、本設定を差し替えて再生成すること。
"""

from __future__ import annotations

# --- 対象エリア（仮） -------------------------------------------------------
# 狭山湖（山口貯水池）を中心とした約5.0km(緯度方向) x 約5.0km(経度方向) の矩形。
BBOX_LON_MIN = 139.352
BBOX_LON_MAX = 139.408
BBOX_LAT_MIN = 35.7675
BBOX_LAT_MAX = 35.8125

# osmium extract 用（ways/relations の参照整合性を保つため実際の抽出範囲は
# 上記より広くなる。これは意図した挙動 — smart 戦略の仕様）。
OSMIUM_EXTRACT_BBOX = f"{BBOX_LON_MIN},{BBOX_LAT_MIN},{BBOX_LON_MAX},{BBOX_LAT_MAX}"

# --- 細分グリッドセル（docs/terrain.md §4）---------------------------------
# 「緯度経度ベースの矩形グリッド（例: 数m四方）」の実装値。
# 5m四方を採用（H3 res11 の平均対辺 約49.6m に対し、1ヘクスあたり
# 概ね 100〜150 セル程度の解像度になり、多数決集約の粒度として十分と判断した）。
CELL_SIZE_M = 5.0

# --- H3 ヘクスID体系（Issue #38・2026-09-08 代表決定）------------------------
# 50mに最も近い解像度を実測して選定した結果。research.md §8.2 参照。
H3_RESOLUTION = 11

# --- OSM抽出データのキャッシュ -----------------------------------------------
DATA_CACHE_DIR = "data_cache"
KANTO_PBF_URL = "https://download.geofabrik.de/asia/japan/kanto-latest.osm.pbf"
KANTO_PBF_PATH = f"{DATA_CACHE_DIR}/kanto-latest.osm.pbf"
AREA_PBF_PATH = f"{DATA_CACHE_DIR}/area.osm.pbf"

# --- 出力 -------------------------------------------------------------------
OUT_DIR = "out"
