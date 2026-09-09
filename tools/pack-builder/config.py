"""tools/pack-builder/ 地域パック生成パイプラインの設定値（Issue #38・#85）。

## 対象エリア（2026-09-10 代表決定・Issue #85 で確定）

Issue #38 では「代表の生活圏の確定を待たず、仮座標で先に通してよい」
（2026-08-11 代表回答）という前提のもと、**仮座標**として
埼玉県狭山市〜東京都瑞穂町にまたがる狭山湖（山口貯水池）周辺を採用していた。

**Issue #85（2026-09-10 代表決定）により、このエリアがバーティカルスライス本番対象
エリアとして正式に確定した。** 以後「仮座標」ではなく本番設定である。以下は
その決定コメントの要旨（詳細: Issue #85 のコメント参照）:

- plan.md §15「代表の生活圏を含む約5km四方」という**定義自体は変更しない**。
  狭山湖周辺が実測でその定義に合致する、という関係になる。
- 面積の検算: H3 res11 の対辺実測 47.68m（docs/terrain.md §3.1）から
  正六角形1個の面積 ≈ 1,968.8 m²。13,106ヘクス × 1,968.8 m² ≈ 25.80 km²
  → 正方形換算で一辺 約5.08km（仮に対辺50mで計算しても一辺約5.33km）。
  いずれも「約5km四方」に合致する。
- ヘクス数: 13,106（plan.md §3.5 の暫定上限30,000の44%）。
- 地形の混在: 空き地64.1% / 森31.9% / 水辺3.9%（research.md §8.8）。

このエリアを選んだ理由（plan.md §15 の要求「水辺・緑地・農地・市街が混在する範囲」に対応）:
- 水辺: 狭山湖（人造湖・natural=water）
- 緑地/森: 狭山丘陵の樹林地（landuse=forest, natural=wood）
- 農地: 狭山茶の茶畑（landuse=farmland 等）
- 市街: 周辺の住宅地・商業施設（landuse=residential 等、コストコ入間倉庫店・
  三井アウトレットパーク入間など landuse=retail の郊外型店舗も存在）

（農地・市街タグは Issue #70 により地形タイプとしては「空き地」に統合済み。
上記は当初の選定理由の記録として残す。）
"""

from __future__ import annotations

# --- 対象エリア（2026-09-10 代表決定・Issue #85 で本番確定） -----------------
# 狭山湖（山口貯水池）を中心とした約5.0km(緯度方向) x 約5.0km(経度方向) の矩形。
BBOX_LON_MIN = 139.352
BBOX_LON_MAX = 139.408
BBOX_LAT_MIN = 35.7675
BBOX_LAT_MAX = 35.8125

# パック生成物のファイル名・pack_version に使うエリアの短い識別子（ASCII）。
# 地形判定ルール・解像度が変わらない限り変更しないこと（変更するとpack_versionが
# 変わり、plan.md §3.3の不変性ルールに基づく比較の前提が変わる）。
AREA_SLUG = "sayamako"

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

# --- pack_version（Issue #85・T043）------------------------------------------
# パックの生成ロジック（地形判定ルール・グリッド解像度・feature_id方式等）自体の
# バージョン。terrain_rules.py の判定ルールや H3_RESOLUTION・CELL_SIZE_M を変更した
# ときは、**必ずこの値をインクリメントすること**。
#
# 理由: pack_version は classify_terrain.py 内で
# f"{AREA_SLUG}-v{PACK_SCHEMA_VERSION}-{input_pbf_sha256の先頭12桁}" として組み立てる
# （tools/pack-builder/README.md 参照）。これは「同じOSM入力なら同じpack_versionになる」
# という決定論を持たせるためだが、逆に言うと「OSM入力が同じでも判定ルールを変えた場合」に
# 本値を上げ忘れると、ロジックが変わったのに同じpack_versionになってしまい、
# plan.md §3.3「一度開示したヘクスの資材分類は、パック更新後も過去分は不変
# （獲得履歴は当時のpack_versionで確定）」という不変性ルールの前提（＝同じpack_versionなら
# 同じ分類結果）を壊す。
PACK_SCHEMA_VERSION = 1

# --- OSM抽出データのキャッシュ -----------------------------------------------
DATA_CACHE_DIR = "data_cache"
KANTO_PBF_URL = "https://download.geofabrik.de/asia/japan/kanto-latest.osm.pbf"
KANTO_PBF_PATH = f"{DATA_CACHE_DIR}/kanto-latest.osm.pbf"
AREA_PBF_PATH = f"{DATA_CACHE_DIR}/area.osm.pbf"

# --- Planetiler（ベクタタイルMBTiles生成・Issue #85・T039）--------------------
# ピン留めするバージョン。CIと開発者ローカルで同一バイナリを使うため、
# `latest` リダイレクトURLではなくタグ付きURLを固定する。
# JDK 21 が必要（本プロジェクトの既定JDKと一致。docs/dev-setup.md §2）。
PLANETILER_VERSION = "0.10.2"
PLANETILER_JAR_URL = (
    f"https://github.com/onthegomap/planetiler/releases/download/"
    f"v{PLANETILER_VERSION}/planetiler.jar"
)
PLANETILER_JAR_PATH = f"{DATA_CACHE_DIR}/planetiler-{PLANETILER_VERSION}.jar"
# Planetiler標準プロファイル（OpenMapTiles互換スキーマ）が要求する補助データセット
# （lake_centerlines・water_polygons・natural_earth。世界共通・エリアに依らず1回だけ
# 取得すればよい。合計約1.4GB、初回のみ）のダウンロード/展開先。
PLANETILER_SOURCES_DIR = f"{DATA_CACHE_DIR}/planetiler_sources"
PLANETILER_TMP_DIR = f"{DATA_CACHE_DIR}/planetiler_tmp"

# --- 出力 -------------------------------------------------------------------
OUT_DIR = "out"

# app/ への同梱先（Issue #85・T044）。bundle_region_pack.sh の出力先。
APP_ASSETS_PACK_DIR = "../../app/assets/pack"
