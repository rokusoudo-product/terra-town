# tools/pack-builder/ — 地域パック生成パイプライン

Issue #38（[Spike] pack-builder 最小プロトタイプで地形属性の事前計算を1エリア分検証する）と
Issue #85（[Impl] Planetiler でベクタタイル MBTiles を生成しバーティカルスライスの地域パックを
同梱する）、Issue #86（[Impl] 地域パックに行政区域と名所POIを追加しT040の完了状態を確定する）、
Issue #94（[Impl] 行政区域・名所POIを region_pack.sqlite に統合しパックに同梱する）、
Issue #152（[Impl] ヘクスの隣接関係をパック生成時に事前計算して同梱する）の成果物。

`specs/001-mvp/plan.md` §3.2「地域パックの内容物」・§4「資材分類の決定論（事前計算）」・
`docs/terrain.md` §4・§5・`docs/opening_points.md` §5.2 で定義されたパイプラインの実装:

```
OSM抽出 → 細分グリッドセルでの地形判定 → H3ヘクスへの多数決集約 → SQLite出力（Issue #38・T040）
                                                                  → ベクタタイルMBTiles生成（Planetiler・Issue #85・T039）
国土数値情報N03 → 対象エリアと交差する市区町村を抽出 → トポロジ保持簡略化 → ヘクス帰属判定 → SQLite出力（Issue #86・T041）
OSM抽出 → 観光POIタグ（Tier 1）抽出 → 名称・面積フィルタ → SQLite出力（Issue #86・T042）
hex_terrainのヘクス集合 → H3で距離1の隣接候補を計算 → パック範囲外を除外 → SQLite出力（Issue #152）
上記4つの出力 → 整合性検証 → 統合・軽量化 → region_pack.sqlite（Issue #94・#152・slim_pack_for_bundle.py）
```

**本ツールの生成物（`.osm.pbf`・`*.sqlite`・`*.mbtiles`・`data_cache/`配下全般）は
コミットしないこと**（`.gitignore` 済み）。

検証結果・使用ツールのバージョン・所要時間・出力サイズなどの記録は
`specs/001-mvp/research.md` §8 を参照。ヘクスID体系（H3）・feature id橋渡し方式の
設計判断は `docs/terrain.md` §3.1・§4.2〜§4.4 に記録済み（本ツールはその実装）。

## 対象エリア（2026-09-10 代表決定・Issue #85 で本番確定）

バーティカルスライス対象エリアは、Issue #38 以来検証に使ってきた**狭山湖周辺**
（`config.AREA_SLUG = "sayamako"`・13,106ヘクス）で確定した。判断根拠は
`config.py` 冒頭のコメントと Issue #85 のコメントを参照。plan.md §15 は変更していない
（「代表の生活圏を含む約5km四方」という定義自体はそのまま有効で、狭山湖周辺が
実測でそれに該当する、という関係）。

## スコープ

本ツールが実装するのはこれだけ（Issue #38・#85・#86・#94・#152）:

- 対象エリア1つ分の OSM抽出 → 地形属性の事前計算 → SQLite出力（Issue #38・T040）
- 分類結果の抜き取り検証・決定論の検証（Issue #38）
- ヘクスID体系（H3）・feature id橋渡し方式の確定（Issue #38）
- **ベクタタイル MBTiles の生成（Planetiler・Issue #85・T039）**
- **パックメタ（`pack_version`）の付与・各ヘクスFeature直下への整数`id`の実装確認（Issue #85・T043）**
- **バーティカルスライス対象エリアのパック生成・`app/assets/`への同梱の仕組み（Issue #85・T044）**
- **パック生成のCI化（Issue #85・T045・`.github/workflows/pack-build.yml`）**
- **行政区域ポリゴン（国土数値情報N03）の取り込み・トポロジ保持簡略化・ヘクス帰属判定（Issue #86・T041）**
- **名所POI（OSM観光POI・Tier 1）の抽出（Issue #86・T042）**
- **行政区域・名所POIを`region_pack.sqlite`へ統合し`app/assets/pack/`に同梱（Issue #94。
  下記「出力（`out/region_pack.sqlite`）の統合」参照）**
- **ヘクス隣接関係の事前計算・同梱（Issue #152。下記「ヘクス隣接関係」参照）**

以下は**スコープ外**（他のIssueで実装する、または本Issueで明示的に見送った）:

- 地図表示の実装そのもの（T055）
- 地図表示側の検証（Issue #24のR1・R2。`spikes/`配下は本ツールと無関係）
- ODbL適合の詳細検証・`docs/licenses.md`への記録（Issue #37）。**Issue #94時点でもdocs/licenses.md
  はまだ存在しない**ため、出典・CC BY 4.0・加工した旨・承認番号は本ツールの`pack_meta`と
  本READMEにのみ記録した（下記「データソースとライセンス」参照）。画面上での常時表示は
  T108（未実装）の担当であり、本Issueでは実装していない
- 名所オブジェクトのゲーム内仕様（`is_bonus`・収集判定・報酬計算等。Issue #6・`docs/landmark_objects.md`）
- Tier 2（補完層）POIタグ・ボーナスオブジェクト（allowlist照合）の抽出（`poi_rules.py`のdocstring参照。
  目標密度・allowlistとも仮値/未整備のため実装しない）
- 開放ポイント消費による隣接制約の実装そのもの（Issue #151。本ツールは`hex_neighbor`の
  データを用意するところまで）
- 立入禁止エリアの判定（別Issue・MVP対象外）

## T040（地形属性の事前計算）の完了状態の調査結果（Issue #86・2026-09-10実施）

Issue #86の指示により、実装着手前に T040 の現状を調査した。結論: **T040は完了**と判断する。

### 満たされている要件（根拠つき）

- **`docs/terrain.md` §5 の判定ルール → §4 の多数決でヘクスに集約 → SQLite `cell_terrain`/`hex_terrain`**:
  `terrain_rules.py`（§5 の優先順位付きタグ判定の実装）・`classify_terrain.py`
  （`classify_cells` が優先度判定、`aggregate_to_hexes` が §4 の多数決集約と同数時の
  決定論的タイブレークを実装）・`write_sqlite`（`cell_terrain`・`hex_terrain` 両テーブルを
  出力）がすべて揃っている。本Issueで実際に再実行し確認済み（2026-09-10実施）:
  `cells=1,012,011 hexes=13,106`（`research.md` §8.1・§8.8.1の実測値と完全一致）。
- **`tasks.md` T040 の「要件追記（2026-09-08・Issue #56）」（各ヘクスFeature直下に整数`id`を
  持たせること）**: `hex_bridge.py`（下位52bitマスク方式）・`hex_terrain.feature_id`列・
  `export_hex_geojson.py`（実データ13,106件で「Feature直下の整数`id`・重複なし」を検証）で
  実装済み。T043の完了記録（tasks.md）が同じ実装を指しており重複実装ではない。
- **決定論の検証**: `verify_determinism.py` を本Issueで再実行し **PASS**（2回生成の対称差分0件。
  `research.md` §8.6・§8.8.3・§8.9.6 でも同様の結果が記録済み）。
- **`feature_id` 橋渡しの検証**: `verify_feature_id.py` を本Issueで再実行し **PASS**
  （衝突0件・JSON安全整数範囲内・可逆性OK。`research.md` §8.4参照）。
- **抜き取り検証**: `research.md` §8.5で5地形タイプ（海を除く。対象エリアに海が存在しないため）
  すべてで実施済み、判定ルールどおりであることを確認済み。

### 満たされていないもの（既知の簡略化として記録済み・T040の完了を妨げない理由）

`research.md` §8.7に記録済みの簡略化のうち、今回あらためて確認したもの:

- **海岸線（`natural=coastline`）からの海面ポリゴン合成が未実装**: 対象エリア（狭山湖周辺）は
  内陸のため実際の分類結果に影響しない。沿岸部エリアを扱う場合は別途設計が必要（研究ノートに
  記録済みであり、本Issueで新たに追加すべき対応ではない）。
- **`building=*`密度による市街判定が未実装**: これは**Issue #70（2026-09-08）で市街が
  地形タイプそのものから廃止されたため、要件自体が消滅している**（`docs/terrain.md` §5参照）。
  未実装というより「対象外になった」が正確な表現。
- **bbox境界をまたぐヘクスの多数決精度**: 境界ヘクスは内側のセルのみで投票するため、内部ヘクスより
  精度が低い可能性がある（データ品質上の注意点であり、`feature_id`/`hex_id`自体の一意性・
  不変性には影響しない。`research.md` §8.7参照）。

### 結論

上記の「満たされていないもの」はいずれも (a) 対象エリアの性質上この検証では顕在化しない、
(b) 別Issueの決定により要件自体が消滅した、(c) 一意性・決定論に影響しないデータ品質上の
注意点、のいずれかであり、**T040の受け入れ基準（地形判定ルールの実装・多数決集約・
SQLite出力・整数id要件）を妨げるものではない**。したがって **T040は完了と判定し、
`specs/001-mvp/tasks.md`のチェックボックスを本Issueでオンにする**（詳細は同ファイルの
T040行の注記参照）。

## セットアップ

### 1. Python環境

```bash
cd tools/pack-builder
python3 -m venv .venv
./.venv/bin/pip install -r requirements.txt
```

`requirements.txt` に固定したバージョン（2026-09-08時点で動作確認済み）:

- `osmium` 4.3.1（pyosmium。libosmiumのPythonバインディング。**`osmium-tool`のCLIとは別物**、下記参照）
- `h3` 4.5.0（H3 v4世代のAPI。v3とv4はAPI・挙動が異なるため要注意。`specs/001-mvp/research.md` §8.3参照）
- `shapely` 2.1.2
- `numpy` 2.5.3
- `topojson` 1.10（Issue #86・T041。行政区域ポリゴンのトポロジ保持簡略化。依存は
  `numpy`・`shapely`・`packaging`のみで`geopandas`等は要求しない）

### 2. `osmium-tool`（CLI）のインストール

bbox切り出し（`extract_area.sh`）には pyosmiumとは別に、C++製のCLIツール `osmium-tool`
（`osmium extract` コマンド）が必要。

**sudoが使える環境（通常はこちら）**:

```bash
sudo apt-get install osmium-tool
```

**sudoが使えない環境**（本Issueの検証環境。パスワードなしsudoが無かったため以下の方法を使用）:

```bash
mkdir -p /tmp/osmium_local && cd /tmp/osmium_local
apt-get download osmium-tool libboost-program-options1.83.0
dpkg-deb -x osmium-tool_*.deb extracted
dpkg-deb -x libboost-program-options1.83.0_*.deb extracted
# 動作確認
LD_LIBRARY_PATH=extracted/usr/lib/x86_64-linux-gnu extracted/usr/bin/osmium --version
```

`apt-get download` はダウンロードのみでシステムへのインストール（root権限）を伴わないため、
sudoなしで実行できる。`libboost-program-options`のバージョンはUbuntuのバージョンにより
異なる場合があるため、`apt-cache policy osmium-tool` で依存関係を確認すること。

### 3. 単体テスト（`pytest`・Issue #118）

`tools/pack-builder/tests/` に、`data_cache/`（OSM抽出・Planetiler補助データ）を
一切使わない純粋関数の単体テストがある。対象は現時点で `terrain_rules.py`
（`docs/terrain.md` §5 の判定ルール本体）と `hex_bridge.py`（`feature_id`の
下位52bitマスク方式）の2モジュール。`classify_terrain.py`等のエンドツーエンド実行・
決定論検証（`verify_determinism.py`等）は引き続き手動トリガー（`pack-build.yml`・
Issue #85・T045）の担当であり、本テストのスコープではない。

```bash
cd tools/pack-builder
./.venv/bin/pip install -r requirements-dev.txt   # pytestのみ（requirements.txtとは別）
./.venv/bin/python -m pytest
```

`requirements.txt`（本番パイプライン用。`osmium`・`h3`・`shapely`・`numpy`・`topojson`）とは
意図的に別ファイル（`requirements-dev.txt`）に分離している。テスト対象が標準ライブラリのみで
動く純粋関数のため、CI・ローカルとも `pytest` 単体のインストールだけで済む
（`osmium`のネイティブビルド等、重い依存をテストのために増やさないため）。

PR CI（`.github/workflows/ci.yml`）でもこの2ファイルを対象に `pytest` を実行しており、
`terrain_rules.py`（判定ルール）を書き換えて壊すと CI が red になる
（Issue #118・変異チェックの記録は同Issueを close したPR本文参照）。

## 使い方（エンドツーエンド）

```bash
cd tools/pack-builder

# 1. 関東地方OSM抽出をダウンロード（約2分・約477MiB。1回だけでよい）
bash download_kanto.sh

# 2. 対象エリア（config.py のbbox）だけをosmium extractで切り出す
#    sudoでosmium-tool を入れた場合はそのまま:
bash extract_area.sh
#    ローカル展開した場合は環境変数で指定:
OSMIUM_BIN=/tmp/osmium_local/extracted/usr/bin/osmium \
LD_LIBRARY_PATH=/tmp/osmium_local/extracted/usr/lib/x86_64-linux-gnu \
bash extract_area.sh

# 3. 地形属性を事前計算してSQLiteに出力（約6〜7秒）
./.venv/bin/python classify_terrain.py
# out/pack.sqlite が生成される

# 4. 決定論の検証（同じ入力から2回生成して一致することを確認）
./.venv/bin/python verify_determinism.py

# 5. 抜き取り検証用のサンプル座標を出力（実地図との突き合わせは手動で行う）
./.venv/bin/python spot_check_samples.py

# 6. H3 index <-> feature_id 橋渡し方式の性質を検証（衝突なし・52bit範囲内・可逆性）
./.venv/bin/python verify_feature_id.py

# (参考) H3の解像度選定の再現。docs/terrain.md §3.1・research.md §8.2 の実測値の再現用
./.venv/bin/python h3_resolution_survey.py

# (参考) natural=peak バッファ半径の感度分析の再現。research.md §8.9.3 の実測値の再現用
./.venv/bin/python peak_radius_sensitivity.py

# 7. ベクタタイルMBTilesを生成（Planetiler・約1〜1.5分。初回のみ+補助データ約1.4GBを取得）
bash build_vector_tiles.sh
# out/tiles.mbtiles が生成される

# 8. 同一入力から同一出力になることの検証（Planetilerを2回実行して比較。約1.5〜2分）
./.venv/bin/python verify_tiles_determinism.py

# 9. 同梱用に軽量化（cell_terrainを除いたSQLiteを作る）
./.venv/bin/python slim_pack_for_bundle.py
# out/region_pack.sqlite が生成される（約3.16MB。cell_terrain込みの66MBに対して約4.8%。
# Issue #105でhex_terrain.boundary_geojson（ヘクス境界）を追加したため、
# 追加前の約750KBから増加した。詳細は下記「ヘクス境界（boundary_geojson・Issue #105）」参照）

# 10. 各ヘクスFeature直下に整数idがあることの検証（T043の受け入れ基準を実際に確認する）
# （Issue #105以降は、格納済みboundary_geojsonが再計算結果と一致することもあわせて検証する）
./.venv/bin/python export_hex_geojson.py

# 11. 国土数値情報N03（行政区域データ）をダウンロード（都道府県別。既にキャッシュ済みならスキップ）
bash download_n03.sh

# 12. 行政区域ポリゴンの取り込み（bboxと交差する市区町村を抽出→トポロジ保持簡略化→
#     ヘクス帰属判定。out/pack.sqlite の hex_terrain を先に生成しておくこと。約1〜2秒）
./.venv/bin/python extract_districts.py
# out/districts.sqlite が生成される（テーブル: district, hex_district, pack_meta）

# 13. 行政区域の決定論検証（2回生成して district・hex_district が一致することを確認）
./.venv/bin/python verify_districts_determinism.py

# 14. 名所POI（OSM観光POI・Tier 1）の抽出（約2〜3秒）
./.venv/bin/python extract_poi.py
# out/poi.sqlite が生成される（テーブル: poi, pack_meta）

# 15. POI抽出の決定論検証
./.venv/bin/python verify_poi_determinism.py

# 16. ヘクス隣接関係の事前計算（Issue #152・約0.2秒）
./.venv/bin/python compute_hex_neighbors.py
# out/hex_neighbor.sqlite が生成される（テーブル: hex_neighbor, pack_meta）

# 17. ヘクス隣接関係の決定論検証
./.venv/bin/python verify_hex_neighbor_determinism.py

# 18. 4つの出力（pack.sqlite・districts.sqlite・poi.sqlite・hex_neighbor.sqlite）を
#     統合し、同梱用に軽量化（Issue #94・#152。out/pack.sqliteのhex_terrainを先に
#     生成しておくこと。約0.1秒）
./.venv/bin/python slim_pack_for_bundle.py
# out/region_pack.sqlite が生成される（テーブル: hex_terrain, district, hex_district,
# poi, hex_neighbor, pack_meta。実測 約5.5MB）
```

上記3（`classify_terrain.py`）・7（`build_vector_tiles.sh`）・18（`slim_pack_for_bundle.py`）
と`app/assets/pack/`へのコピーを一括で実行する場合は `bash bundle_region_pack.sh` を使う
（下記「バーティカルスライス対象エリアの同梱」参照。**2026-09-13・Issue #94/#152で
拡張し、`download_n03.sh`・`extract_districts.py`・`extract_poi.py`・
`compute_hex_neighbors.py`も一括実行の対象に含めた**）。**決定論の検証（4・8・13・15・17）や
Feature id の検証（10）は含まれない**ため、それらは別途上記の手順で個別に実行すること。

## 出力（`out/pack.sqlite`）のテーブル構成

| テーブル | 列 | 説明 |
|---|---|---|
| `cell_terrain` | `cell_id, hex_id, lon, lat, terrain_type` | 細分グリッドセル（`config.CELL_SIZE_M`四方）単位の判定結果。生成過程の中間データ |
| `hex_terrain` | `hex_id, terrain_type, feature_id, cell_count, boundary_geojson` | H3ヘクス単位に多数決集約した最終結果。`hex_id`はH3 index（64bit整数、正）。`feature_id`は地図Feature用に下位52bitマスクした値（`docs/terrain.md` §4.4参照）。`boundary_geojson`はヘクス境界（`[[lon,lat],...,[lon,lat]]`の閉環・小数点以下7桁丸め・JSONテキスト。Issue #105・下記「ヘクス境界」節参照） |
| `pack_meta` | `key, value` | 生成条件（`pack_version`・bbox・解像度・セルサイズ・入力ファイルのSHA256・所要時間・各ツールのバージョン・`hex_boundary_format`等） |

**`cell_terrain`は同梱対象外と判断した**（Issue #85・T044）。生成過程の中間データであり
（抜き取り検証`spot_check_samples.py`・デバッグ用途）、fog of war の実行には`hex_terrain`
だけで足りるため。`slim_pack_for_bundle.py`が`cell_terrain`を除いた`region_pack.sqlite`
（実測 約3.16MB。Issue #105で`boundary_geojson`を追加する前は約750KBだった。
`cell_terrain`込みの66MBに対して約4.8%）を作る。

## 出力（`out/districts.sqlite`）のテーブル構成（T041）

| テーブル | 列 | 説明 |
|---|---|---|
| `district` | `district_id, name, prefecture_name, county_name, geometry_geojson` | 行政区域（市区町村）1件。`district_id`は国土数値情報N03の行政区域コード（`N03_007`。5桁）。`geometry_geojson`はトポロジ保持簡略化後のポリゴン（lon/lat・小数点以下7桁に丸め済み） |
| `hex_district` | `hex_id, district_id` | ヘクス→区画の帰属（plan.md §5「ヘクス重心が区画内かで帰属判定」）。帰属先がない場合（パック範囲外・水域等）はこのテーブルに行が存在しない |
| `pack_meta` | `key, value` | 生成条件（データソース・edition・ライセンス・簡略化許容誤差・区画数・入力ファイルのSHA256等） |

**`district_id`をキーにする理由**: `packages/core/lib/src/pack/district.dart`の
`DistrictId`が「パック生成パイプラインが国土数値情報N03から払い出す区画コード等を
そのまま保持する不透明な識別子」と定義しているため、N03の`N03_007`（都道府県コード+
市区町村コード）をそのまま使う。

**帰属判定は簡略化前の原本ポリゴンで行う**: `district.geometry_geojson`（表示用）は
簡略化後だが、`hex_district`の判定自体は`extract_districts.py`内で簡略化前の原本
ポリゴンに対して行っている（表示の簡略化が判定精度に影響しないようにする設計判断）。

**対象は「bboxと交差する市区町村」であり、bboxでクリップしていない**:
狭山湖周辺エリア（実測5市区町）程度の規模ではクリップしなくてもパックサイズへの
影響は軽微な一方、クリップは切断線上でのトポロジ再構築という別のリスクを持ち込むため、
本Issueでは採用しなかった（`extract_districts.py`冒頭のdocstring参照）。

## 出力（`out/poi.sqlite`）のテーブル構成（T042）

| テーブル | 列 | 説明 |
|---|---|---|
| `poi` | `id, lat, lon, kind, name` | 名所POI 1件。`id`はOSMの型を含む文字列（`node/<id>`・`way/<id>`・`relation/<id>`）。`kind`はマッチしたOSMタグ（例: `tourism=viewpoint`）。plan.md §3.2の`poi(id, lat, lon, kind, name)`に一致 |
| `pack_meta` | `key, value` | 生成条件（データソース・ライセンス・タグ層〔Tier 1のみ〕・面積しきい値・タグ別件数・入力ファイルのSHA256等） |

**Tier 1のみを実装（`poi_rules.py`）**: `docs/landmark_objects.md` §2.1のTier 1
（`tourism=attraction`/`viewpoint`/`artwork`/`museum`/`gallery`/`zoo`/`theme_park`、
`historic=monument`/`memorial`/`castle`/`ruins`/`archaeological_site`、
`leisure=park`〔面積`config.POI_PARK_MIN_AREA_M2`以上〕）のみを抽出する。
Tier 2（補完層）・ボーナスオブジェクト（`is_bonus`・allowlist照合）は実装していない
（理由は下記「既知の簡略化・未解決事項」）。

**名称のない地物は除外する**: `name`→`name:ja`の順でフォールバックし、いずれも
持たない地物は`poi`に含めない（名所図鑑〔Issue #12〕上、名称のない地物は意味を
持たないため）。

## 出力（`out/hex_neighbor.sqlite`）のテーブル構成・ヘクス隣接関係（Issue #152）

| テーブル | 列 | 説明 |
|---|---|---|
| `hex_neighbor` | `hex_id, neighbor_count, neighbor_hex_ids` | ヘクス1件の隣接関係。`neighbor_hex_ids`は隣接ヘクスのH3 index（整数）を昇順に並べたJSON配列のテキスト（例: `[123, 456]`）。`neighbor_count`は配列長のキャッシュ（`len(json.loads(neighbor_hex_ids))`と常に一致） |
| `pack_meta` | `key, value` | 生成条件（計算方式・エッジヘクス件数・隣接数の最小/最大・所要時間・h3-pyのバージョン等） |

**計算方式**: `hex_terrain`の全ヘクスについて、H3の`grid_ring(hex, 1)`（距離ちょうど1の
隣接セル。通常6個、対象エリアにはペンタゴンセルが存在しないため考慮不要）を求め、
**パック範囲外（`hex_terrain`に存在しない）の候補は除外**して昇順に並べる
（`hex_neighbors.filter_and_sort_intra_pack_neighbors`）。**パック範囲の縁のヘクスは、
この除外の結果として隣接が6件未満になる**（実測: 狭山湖周辺エリア13,106ヘクス中469件が
6件未満・最小2件・最大6件）。全ヘクスについて1行を書き込むため
（隣接0件のヘクスがあっても行自体は存在する）、`set(hex_neighbor.hex_id)`は常に
`set(hex_terrain.hex_id)`と一致する（`slim_pack_for_bundle.py`の統合時にこの等価性を
fail-loudで検証する。下記「出力（`out/region_pack.sqlite`）の統合」参照）。

**対称性の自動検証**: パック範囲内に制限した隣接関係は構造的に対称になる
（AがBを隣接に持てば、BもAを隣接に持つ）。`compute_hex_neighbors.py`は実データに対して
これを実行時に検証し（`verify_symmetry`）、崩れていれば停止する。

**保存形式の判断（テーブル1本・JSON配列列 vs 隣接ペアの関係テーブル）**: `hex_id, neighbor_hex_id`
の2列・複合主キー（`WITHOUT ROWID`）というペア単位の関係テーブルも検討し、実データ
（13,106ヘクス・有向辺77,692本）で両方式を実測した。

| 方式 | サイズ（実測） |
|---|---|
| JSON配列列（1ヘクス1行・採用） | 1,847,296 bytes（約1.76MB） |
| 関係テーブル（1辺1行・`WITHOUT ROWID`） | 1,732,608 bytes（約1.65MB） |

関係テーブルの方が約6%（約114KB）小さいが、次の理由でJSON配列列を採用した:
- **1ヘクスの隣接一覧を得るのに1行の読み取りで済む**（関係テーブルだと`WHERE hex_id = ?`の
  範囲スキャン+集約が必要）。`RegionPackRepository`は起動時に全件をメモリへ読み込む方式
  （`region_pack_repository.dart`のクラスコメント参照）のため実行時性能への影響はどちらでも
  軽微だが、読み込みコード自体は単純になる。
- **`hex_terrain.boundary_geojson`と同じ「1行1ヘクス・JSON列」という既存パターンに揃う**
  （`hex_geometry.py`・`classify_terrain.py`参照）。パック内のテーブル設計の一貫性を優先した。
- 6%の差は同梱パック全体（`region_pack.sqlite`約5.5MB＋`tiles.mbtiles`約680KB）に対して
  無視できる規模であり、`plan.md`・`docs/`に同梱アセットのサイズ上限は明記されていない
  （「ヘクス境界」節の判断と同じ理由）。

## 出力（`out/region_pack.sqlite`）の統合（Issue #94・#152）

`slim_pack_for_bundle.py`が、これまで別々の`out/*.sqlite`だった4つの出力
（`pack.sqlite`・`districts.sqlite`・`poi.sqlite`・`hex_neighbor.sqlite`）を
1つの`region_pack.sqlite`（テーブル: `hex_terrain, district, hex_district, poi,
hex_neighbor, pack_meta`）に統合する。**2026-09-13代表決定（Issue #94本文コメント）
「#94と#152は同じパック作り直しにまとめること」に従い、両方の統合窓口を1本化した。**

**統合前の整合性チェック（fail-loud）**: 4つの入力は別々のスクリプト・別々の実行時刻で
生成されうるため、黙って統合すると「古い`districts.sqlite`と新しい`pack.sqlite`を
組み合わせた中身の壊れたパック」がエラーなく生成される事故になりうる。そのため
統合前に次を検証し、いずれかが崩れていれば停止する:
- `poi.sqlite`の`input_pbf_sha256`が`pack.sqlite`のそれと一致すること
- `hex_neighbor.sqlite`の`hex_neighbor`のhex_id集合が`pack.sqlite`の`hex_terrain`と
  **完全一致**すること
- `districts.sqlite`の`hex_district`のhex_id集合が`hex_terrain`の**部分集合**であること
- `districts.sqlite`の`pack_meta`に`n03_sha256_11`・`n03_sha256_13`が存在すること

**`pack_meta`のキー名前空間**: 4つの入力はそれぞれ独立したスクリプトが書いており、
`generated_at_utc`・`generation_seconds`・`h3_py_version`・`shapely_version`・
`osmium_version`・`input_pbf`・`input_pbf_sha256`のような共通の列名を複数の入力が持つ。
単純に全メタを1つの`pack_meta`テーブルへ入れると後勝ちで上書きされ「どの入力のどの値か」が
失われるため、`pack.sqlite`由来のキーは無印のまま、`districts.sqlite`/`poi.sqlite`/
`hex_neighbor.sqlite`由来でまだプレフィックスの付いていないキーには、それぞれ
`district_`/`poi_`/`hex_neighbor_`を付けて名前空間を分離した（`district_source`のように
既にプレフィックス済みのキーはそのまま）。

## データソースとライセンス（Issue #86）

### 行政区域ポリゴン（T041）

- **データソース**: 国土数値情報 行政区域データ（N03）。国土交通省。
- **取得元・版**: `https://nlftp.mlit.go.jp/ksj/gml/data/N03/N03-2023/N03-20230101_{11,13}_GML.zip`
  （第3.1版・データ基準年 令和5〔2023〕年1月1日。埼玉県〔11〕・東京都〔13〕）。
- **⚠️ ファイル命名の罠（実データ確認済み）**: 同じ配布ページに `N03-YYMMDD_{pref}_GML.zip`
  （6桁日付）という古い命名の版が並んでいるが、これは実体が「行政区域の変遷」
  （`ksj:AdministrativeBoundary`。明治〜昭和の市区町村合併履歴を表す線データで、
  現在の行政区域ポリゴンではない）という**別データ**である。実際にダウンロード・
  展開して`N03_007`（狭山市=11215）が存在しないこと、属性が
  `administrativeAreaCode`/`cityName`/`formationDate`/`disappearanceDate`である
  ことを確認して判明した。8桁日付（`N03-20230101_*`）の版が現行の行政区域ポリゴン
  （属性`N03_001`〜`N03_004`・`N03_007`、面データ）であることを確認済み。
  `download_n03.sh`のコメントにも記録している。
- **利用規約**: 「国土数値情報 利用規約」（令和元年以降のデータはオープンデータ・
  **CC BY 4.0**）。配布ページには「測量法に基づく国土地理院長承認（複製）R 5JHf 357」
  「本製品を複製する場合には、国土地理院の長の承認を得なければならない。」という
  原典表示の注記がある。
- **⚠️ 承認番号の訂正（Issue #94・2026-09-13）**: 本節は当初「R 4JHf 430」と記載していたが、
  これは誤りだった。秘書が一次資料を確認した結果、本リポジトリが使用する
  `N03-20230101`（令和5年版）に対応する正しい番号は**「R 5JHf 357」**である
  （代表決定コメント: https://github.com/rokusoudo-product/terra-town/issues/94#issuecomment-5650198269 ）。
- **2026-09-13代表決定（Issue #94）**: 帰属表示に**出典（国土交通省 国土数値情報
  行政区域データ・上記URL）／CC BY 4.0／加工した旨／上記承認番号**を含める（安全側に
  倒す）。`extract_districts.py`が`district_source_url`・`district_license_cc`・
  `district_processing_note`・`district_survey_approval`として`pack_meta`に個別キーで
  記録する（`slim_pack_for_bundle.py`の統合時に`district_`プレフィックス済みのため
  そのまま`region_pack.sqlite`にも残る）。**画面上での常時表示（T108）は本Issueのスコープ外
  ─ 未実装のまま**であり、T108実装時にこれらのキーをそのまま読めばよい。
  **⚠️ 法的な判断は本Issueの範囲外**: 「派生物をアプリに同梱して一般公開する際に、
  あらためて国土地理院への承認申請が必要か」は判断できる事項ではない。**一般公開
  （ストア配信）の前に、代表が国土地理院に確認すること**を推奨する。MVPの開発・実機検証の
  段階では、上記の表示（データとしての保持）を入れたうえで進めてよい。この論点は
  Issue #37（ODbL適合検証・`docs/licenses.md`）にも記録する。
- **座標系**: JGD2011（EPSG:6668）。OSM由来データ（WGS84）との差は数10cmオーダーで、
  本パイプラインの精度要件（ヘクス約50m四方）に対して無視できるため、既存の
  `classify_terrain.py`と同様に座標変換は行っていない。

### 名所POI（T042）

- **データソース**: OpenStreetMap（`tools/pack-builder/data_cache/area.osm.pbf`。
  Geofabrik関東地方抽出からのbbox切り出し。`classify_terrain.py`と同じキャッシュを再利用）。
- **ライセンス**: Open Database License (ODbL) 1.0 — © OpenStreetMap contributors。
- **詳細な適合検証（属性表示義務・派生データベースの扱い等）はIssue #37のスコープ**であり、
  本Issueでは出典の記録のみを行う。

## `pack_version`（T043・2026-09-13代表決定でIssue #94時点で組み直し）

**中間生成物`out/pack.sqlite`の`pack_version`と、同梱物`out/region_pack.sqlite`の
`pack_version`は値が異なる。** 前者は`classify_terrain.py`が書き込む値
（例: `sayamako-v1-9a66e066b0d4`。地形判定ルール・OSM抽出のみが入力）だが、
後者は`slim_pack_for_bundle.py`が統合時に**組み直した値**（例: `sayamako-v1-2671a8f4ea2c`）
であり、**同梱物の`region_pack.sqlite`のほうを正とする**（アプリが読むのは常にこちら）。

**含める入力の一覧**（2026-09-13代表決定・Issue #94「版番号はパックの中身を一意に表す
指紋であるべき」という理由）:

1. `input_pbf_sha256`（`area.osm.pbf`。地形・POI抽出の入力）
2. `n03_sha256_11`・`n03_sha256_13`（N03行政区域データ、都道府県別GMLzip。埼玉県・東京都）
3. `poi_rules_sha256`（`poi_rules.py`のファイル内容のsha256。POI抽出ルールの変更を捕捉）

`{AREA_SLUG}-v{PACK_SCHEMA_VERSION}-{上記4値を連結した文字列のsha256先頭12桁}`という形式
（`classify_terrain.py`と同じ「生成時刻・生成順序に依存しない純関数」という設計方針を踏襲）。
実際に使った各値は`region_pack.sqlite`の`pack_meta`に監査用キー
（`pack_version_input_pbf_sha256`・`pack_version_n03_sha256_11`・
`pack_version_n03_sha256_13`・`pack_version_poi_rules_sha256`）としてそのまま残るため、
後から「何が版に効いたか」を追える。

**`hex_neighbor`（ヘクス隣接関係・Issue #152）は`pack_version`の入力に含めていない**:
`hex_terrain`のヘクス集合とH3ライブラリのみに依存する純関数であり、既存の
`input_pbf_sha256`（ヘクス集合を決める入力）で実質的に捕捉済みのため
（h3-pyのバージョンは`hex_neighbor_h3_py_version`として`pack_meta`に記録するのみで
`pack_version`のハッシュには含めない）。

**`terrain_rules.py`の判定ルールや`H3_RESOLUTION`を変えたときは、必ず
`config.PACK_SCHEMA_VERSION`をインクリメントすること**（さもないと同一OSM入力に対して
ロジックが変わったのに同じ`pack_version`になり、plan.md §3.3の不変性ルールの前提が壊れる。
この既存ルールは変更していない）。

## 各ヘクスFeature直下の整数`id`（T043）

`hex_terrain.feature_id`列がこれに当たる（Issue #38で実装済み・`hex_bridge.py`）。
`export_hex_geojson.py`が実際にGeoJSON Featureを組み立て、
「直下（`properties`の外）に整数`id`を持つ」「重複がない」ことを実データ（13,106件）で
検証する。**このGeoJSONファイル自体はパックに同梱しない**（参照実装・検証用）。

**⚠️ 旧記述の訂正（Issue #105）**: 本節はかつて「`location/`が実行時に`hex_terrain`から
組み立てる」としていたが、これは実装が存在しない設計意図倒れだったとIssue #105で判明した。
**現在の採用方式（下記「ヘクス境界」節参照）はヘクス境界自体を`hex_terrain.boundary_geojson`
列にパック生成時点で事前計算・格納し、`location/`は読むだけ**にする。

## ヘクス境界（`hex_terrain.boundary_geojson`・Issue #105）

**背景**: fog of war（Issue #100・T056）の`FogOfWarController`は、全ヘクスの六角形境界を
持つGeoJSON FeatureCollectionを受け取る前提で実装されていたが、その境界を実際に組み立てる
手段がどこにも存在しなかった（`location/`にH3の依存が無かった）ため、実データ13,106件を
fog of warに載せられなかった（Issue #105）。

**採用方式（2026-09-10代表決定・案A）**: `tools/pack-builder/hex_geometry.py`が
`h3-py`（4.5.0・既存依存）でH3セルの境界を計算し、`classify_terrain.py`が
`hex_terrain.boundary_geojson`列（`[[lon,lat],...,[lon,lat]]`の閉環・GeoJSON Polygon座標配列・
小数点以下7桁丸め・JSONテキスト）に格納する。`location/`はこの列を読むだけで、
実行時にH3ライブラリで境界計算を行わない。

**採用理由（要旨。全文はIssue #105の代表決定コメント参照）**:
- **決定論**: 実行時計算はH3ライブラリのバージョン差で形状が揺れうる。CIで1回だけ計算し
  固定するほうが安定する（plan.md §4 advisor必須修正②と同じ論理）。
- **実行時コストを増やさない**: 起動時に13,106ヘクス分の境界計算を端末で行わずに済む。
- 追加依存が不要（`h3-py`は既存）。

**退けた案**: 案B（Dartに`h3_dart`を入れて実行時計算）・案C（`export_hex_geojson.py`の
GeoJSONをそのまま同梱）。いずれもIssue #105の代表決定コメントに理由つきで記録済み。

**丸め桁数について（圧縮ではない）**: 小数点以下7桁への丸めは、`extract_districts.py`の
`district.geometry_geojson`が既に採用している精度（約1.1cm相当）に合わせただけであり、
「圧縮」ではない（`hex_geometry.py`冒頭docstring参照）。

**エンコード方式とサイズの実測（Issue #105受け入れ基準）**: 最初から凝った圧縮は作らず、
まず素朴な形式（GeoJSON座標配列のJSONテキストをそのままSQLiteのTEXT列に格納）で実装し、
実測した。

| 項目 | 値 |
|---|---|
| `region_pack.sqlite`（`boundary_geojson`追加前・Issue #105着手前の実測） | 770,048 bytes（約752KB） |
| `region_pack.sqlite`（`boundary_geojson`追加後・7桁丸め・本Issueで採用） | 3,313,664 bytes（約3.16MB） |
| 参考: 7桁丸めをしない場合の境界データ単体（`hex_id`+`boundary_geojson`のみの表・比較用） | 4,157,440 bytes（約3.96MB）。7桁丸めにより約20%削減 |
| 増分（採用した7桁丸め版 − 追加前） | 約2.44MB（13,106ヘクス、1ヘクスあたり約195バイト） |

**判断（要確認）**: 上記の増分は「代表決定コメントに書かれた見積り（約300KB）」を大きく
上回るが、以下の理由から**この実測値のまま確定してよいと判断した**。ただし本判断は
代表確認を経ていないため要確認として記録する。
- MVPは1エリアのみをアプリに同梱する方式であり（plan.md §3.3。拡張エリアは静的ホスティングから
  初回DL）、対象は狭山湖エリア1つの13,106ヘクス分に限られる。
- 同梱パック全体（`region_pack.sqlite` + `tiles.mbtiles`）でも約4.0MBであり、
  `plan.md`・`docs/`のどこにもAPK/同梱アセットの総サイズ上限は明記されていない
  （本README作成時点でgrep済み。Android Auto Backupの25MB上限はゲーム状態の
  エクスポート/インポート要件であり、同梱アセットとは無関係 — plan.md §6）。
- fog of warのソース構築コスト（plan.md §8の主基準「2秒以内」）はヘクス**数**に依存する
  基準であり、1ヘクスあたりのバイト数（同梱サイズ）とは別の指標のため、本変更は
  その基準に影響しない。
- 「許容できない場合に限り圧縮を検討する」という代表決定の方針に従い、まず素朴な実装を
  確定する。bbox相対の固定小数点等の圧縮は、代表が上記実測値を見て「許容できない」と
  判断した場合のフォローアップIssueとする。

詳細な実測条件・追加の比較値は`specs/001-mvp/research.md` §8.10参照。

## ベクタタイルMBTiles生成（T039）

`build_vector_tiles.sh`がPlanetiler（Java製。JDK 21必須）を実行する。

- **Planetiler標準プロファイル（OpenMapTiles互換スキーマ）をそのまま使う**（自前の
  カスタムプロファイルは書かない）。理由: T055（地図表示）が既存のOpenMapTiles系
  スタイル（OSM Liberty等）をそのまま使えるようにするため。plan.md §11も
  「OpenMapTiles系スキーマ利用時は『© OpenMapTiles』を追加」を既に想定している。
- 標準プロファイルは世界共通の補助データセット（`lake_centerline.shp.zip`・
  `water-polygons-split-3857.zip`・`natural_earth_vector.sqlite.zip`、合計約1.4GB）を
  要求する。`--only_layers`で層を絞ってもこの3フェーズ自体は無条件に実行されるため
  回避できないことを実機確認済み。エリアに依らず1回だけ取得すればよいため、
  `download_kanto.sh`と同じ考え方で`data_cache/planetiler_sources/`にキャッシュする
  （`.gitignore`済み）。
- Planetilerバージョンは`v0.10.2`にピン留め（`latest`のリダイレクトではなくタグ付きURL）。
  JDK 21を要求する（`Java-Version: 21`がjarのマニフェストに明記されている。
  本プロジェクトの既定JDKと一致 — docs/dev-setup.md §2・Issue #55）。
- **実測（2026-09-10・狭山湖周辺エリア）**: 生成時間 約39秒〜1分20秒（初回はJVM起動・
  ファイルI/Oのばらつきで長め）、出力サイズ **696,320 bytes（約680KiB）**、
  レイヤ: `boundary, building, housenumber, landcover, landuse, mountain_peak, place,
  poi, transportation, transportation_name, water, water_name, waterway`
  （OpenMapTiles標準スキーマの全13層）、タイル数73（zoom 0-14）、feature数53,308。
- **決定論の検証**: `verify_tiles_determinism.py`が2回生成して
  `(zoom_level, tile_column, tile_row, sha256(tile_data))`の集合を比較する
  （バイト単位のファイル比較ではない。理由はスクリプト内docstring参照）。
  **2026-09-10実施・PASS**（73/73タイル完全一致・metadata差分なし）。

### ⚠️ JDKの罠（docs/dev-setup.md §2 参照）

対話シェルではsdkmanが`JAVA_HOME`をJDK17に固定するため、`java -version`が21を
返してもGradle等が17で動くことがある。`build_vector_tiles.sh`は`java -version`が
21系であることを実行前に確認し、そうでなければ次の対処法を表示して停止する:

```bash
JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64 \
  PATH=$(echo "$PATH" | tr ':' '\n' | grep -v sdkman | paste -sd:) \
  bash build_vector_tiles.sh
```

（`bash -lc "..."`のような非対話シェル経由では、この分岐自体に到達せずシステムの
JDK 21がそのまま使われる。この罠は対話シェルで代表が実行する場合にのみ関係する。）

## バーティカルスライス対象エリアの同梱（T044・Issue #94/#152で拡張）

`bundle_region_pack.sh`が上記のパイプライン全体（地形属性事前計算 → N03取得 →
行政区域・POI抽出 → ヘクス隣接関係計算 → 統合・軽量化 → ベクタタイル生成）を実行し、
`app/assets/pack/`に同梱する。

```bash
cd tools/pack-builder
bash bundle_region_pack.sh
```

**生成物（`app/assets/pack/region_pack.sqlite`・`app/assets/pack/tiles.mbtiles`）は
コミットしない**（`spikes/fixtures/fetch_fixtures.sh`と同じ「取得（生成）スクリプト+
`.gitignore`」の考え方。`app/assets/pack/README.md`と`.gitignore`参照）。
`app/pubspec.yaml`の`flutter.assets`はこのディレクトリをディレクトリ単位で宣言しており、
`README.md`だけが存在する状態（＝未生成）でも`flutter test`/`flutter analyze`は失敗しない
（2026-09-10実測: `region_pack.sqlite`・`tiles.mbtiles`を一時退避し`README.md`のみの
状態で`flutter pub get`・`flutter analyze`（No issues found）・`flutter test -j 1`
（13件全PASS）を確認済み。CIの`ci.yml`「Test app」ステップもこの状態で走る）。

**実測（2026-09-13・狭山湖周辺エリア・Issue #94/#152統合後）**:

| 項目 | 値 |
|---|---|
| ヘクス数 | **13,106**（plan.md §3.5 の暫定上限30,000の44%） |
| 行政区域数（`district`） | 5（埼玉県狭山市・入間市、東京都東大和市・武蔵村山市・西多摩郡瑞穂町） |
| 名所POI数（`poi`） | 16 |
| ヘクス隣接関係（`hex_neighbor`） | 13,106行（全ヘクス）。隣接数 最小2・最大6、6件未満（縁）469件 |
| `pack_version`（統合後・`region_pack.sqlite`の値） | `sayamako-v1-2671a8f4ea2c`（統合前の`sayamako-v1-9a66e066b0d4`から変化。「`pack_version`」節参照） |
| `region_pack.sqlite`（同梱分） | 約5.5MB（内訳: Issue #105で`boundary_geojson`追加前は約750KB → 追加後（Issue #105）約3.16MB → 行政区域・POI・ヘクス隣接関係を統合（Issue #94/#152）で約5.5MB。詳細は「ヘクス境界」「ヘクス隣接関係」節参照） |
| `tiles.mbtiles`（同梱分） | 約680KB（変化なし。行政区域・POI・隣接関係はベクタタイルに含まれないため） |
| 地形属性の事前計算（`classify_terrain.py`） | 約5.3秒 |
| 行政区域の取り込み（`extract_districts.py`） | 約1.4秒 |
| 名所POIの抽出（`extract_poi.py`） | 約2.3秒 |
| ヘクス隣接関係の計算（`compute_hex_neighbors.py`） | 約0.15秒 |
| 統合・軽量化（`slim_pack_for_bundle.py`） | 約0.1秒 |
| ベクタタイル生成（`build_vector_tiles.sh`） | 約34秒 |

**旧実測（2026-09-10・行政区域/POI/隣接関係を統合する前）**: ヘクス数13,106・
`pack_version`=`sayamako-v1-9a66e066b0d4`・`region_pack.sqlite`約3.16MB・
`tiles.mbtiles`約680KB・地形属性事前計算約6.7秒・ベクタタイル生成約39秒〜1分20秒。

## 実機での地図表示確認手順（代表向け）

> **本節は Issue #99 で置き換えられた。** `spikes/map_spike_gl` の検証ハーネスを
> 使う旧手順（別ワークツリーを用意し `kFixtureFillSourceLayer` 等を書き換える方法）は
> もう使わない。アプリ本体（T055・T057）が地図を表示するようになったため、
> 実機での確認手順は `app/assets/pack/README.md`「実機での地図表示確認手順」に
> 集約した。plan.md §8「未計測」の解消もそちらを参照。

## ファイル構成

- `config.py` — 対象エリア(bbox)・グリッドセルサイズ・H3解像度・`pack_version`・Planetiler設定
- `terrain_rules.py` — `docs/terrain.md` §5 の判定ルールの実装（優先順位付きタグ判定）
- `local_projection.py` — 緯度経度⇔ローカル平面座標（メートル）の簡易変換（グリッド敷き詰め・バッファ計算用）
- `hex_bridge.py` — H3 index ⇔ 地図Feature `id` の変換（下位52bitマスク方式。設計判断は`docs/terrain.md` §4.4）
- `classify_terrain.py` — 地形属性事前計算パイプライン本体（`pack_version`付与を含む）
- `verify_determinism.py` — 決定論の検証（2回生成して`hex_terrain`を比較）
- `verify_feature_id.py` — H3 index <-> feature_id 橋渡し方式の検証（衝突なし・JSON安全整数範囲内・可逆性）
- `spot_check_samples.py` — 抜き取り検証用のサンプルヘクス抽出
- `h3_resolution_survey.py` — H3解像度ごとの平均対辺・実測対辺の算出（`docs/terrain.md` §3.1・`research.md` §8.2 の実測値の再現用）
- `peak_radius_sensitivity.py` — `natural=peak`バッファ半径（`terrain_rules.MOUNTAIN_PEAK_BUFFER_M`）を30〜200mで変化させた場合の山ヘクス数・森の侵食数の再現用（`research.md` §8.9.3。Issue #71で「30m据え置き」と判断した根拠データ）
- `download_kanto.sh` / `extract_area.sh` — OSM抽出のダウンロード・bbox切り出し
- `build_vector_tiles.sh` — Planetilerでベクタタイル MBTiles を生成（Issue #85・T039）
- `verify_tiles_determinism.py` — ベクタタイル生成の決定論検証（Issue #85・T045）
- `export_hex_geojson.py` — 各ヘクスFeature直下の整数`id`要件（T043）の検証・参照実装
- `bundle_region_pack.sh` — 上記を一括実行し`app/assets/pack/`へ同梱する（Issue #85・T044・Issue #94/#152で拡張）
- `download_n03.sh` — 国土数値情報N03（行政区域データ）のダウンロード（Issue #86・T041）
- `extract_districts.py` — 行政区域ポリゴンの取り込み・トポロジ保持簡略化・ヘクス帰属判定（Issue #86・T041。Issue #94で帰属表示メタを追加）
- `verify_districts_determinism.py` — 行政区域データの決定論検証（Issue #86・T041）
- `poi_rules.py` — `docs/landmark_objects.md` §2.1 の名所POI抽出ルール（Tier 1のみ）の実装（Issue #86・T042）
- `extract_poi.py` — 名所POI抽出パイプライン本体（Issue #86・T042）
- `verify_poi_determinism.py` — 名所POIデータの決定論検証（Issue #86・T042）
- `hex_neighbors.py` — ヘクス隣接関係の計算ロジック（Issue #152。h3呼び出しと純粋関数を分離しテスト容易性を確保）
- `compute_hex_neighbors.py` — ヘクス隣接関係の事前計算パイプライン本体（Issue #152）
- `verify_hex_neighbor_determinism.py` — ヘクス隣接関係の決定論検証（Issue #152）
- `slim_pack_for_bundle.py` — `pack.sqlite`・`districts.sqlite`・`poi.sqlite`・`hex_neighbor.sqlite`の4出力を統合し、`cell_terrain`を除いた同梱用`region_pack.sqlite`を作る（Issue #85・T044が新設・Issue #94/#152で統合窓口として拡張。整合性チェック・`pack_version`の組み直しを行う）

## 既知の簡略化・未解決事項

`specs/001-mvp/research.md` §8.7 および `terrain_rules.py`・`docs/terrain.md` §5.1 のコメント参照。

**【Issue #71（2026-09-08）で対応済み】** 「山」判定タグを拡張（`natural=hill`/`cliff`/`rock`を追加）したが、
検証エリア（狭山湖周辺）には追加タグに該当する実データが存在せず、出現率は0.02%のまま変化しなかった
（実測結果・DEM要否の結論は`research.md` §8.9参照）。山の出現率不足の解消自体は
[Issue #72](https://github.com/rokusoudo-product/terra-town/issues/72)（石・鉄・塩の供給源）に引き継がれている。

### Issue #86（行政区域・名所POI）で新たに生じた既知の簡略化・要確認事項

- **Tier 2（補完層）POIタグ・ボーナスオブジェクト（allowlist照合）は未実装**:
  `docs/landmark_objects.md` §2.1のTier 2は「地域内の主要層密度が目標密度を下回る
  場合のみ採用」という条件付き仕様だが、目標密度自体が§3.1で「目標値・仮」と
  明記されている仮値であり、密度判定の実装は本Issueのスコープを超えると判断した。
  ボーナスオブジェクト（§2.2）も同様にallowlist（`bonus_landmarks.csv`相当）の
  整備自体がplan/tasks工程の宿題として明記されている（§7）。実測: 狭山湖周辺の
  Tier 1抽出結果は16件（`tourism=viewpoint`×2・`museum`×4・`artwork`×2・
  `attraction`×1・`historic=memorial`×5・`leisure=park`×2）。§3.1の目標密度
  （都市部で150〜250m四方に1件）と比較すると、25.3km²に16件は疎らであり、
  **V-B（土地の固有性）の動機づけとして十分な密度かは要確認事項として残す**
  （Tier 2導入の要否を含め代表確認事項）。
- **`leisure=park`の面積しきい値（`config.POI_PARK_MIN_AREA_M2` = 10,000m²＝1ha）は仮値**:
  `docs/landmark_objects.md`上「一定面積以上」としか定義されておらず具体的な
  しきい値がない。`terrain_rules.MOUNTAIN_SMALL_FEATURE_BUFFER_M`と同種の
  「実測に基づかないオーダー感の判断」であり、代表確認事項として残す
  （実測: `leisure=park`のArea 27件中24件がこのしきい値未満で除外され、
  面積条件を満たした3件のうち名称ありは2件だった）。
- **【Issue #94（2026-09-13）で解決済み】`pack_version`の対象範囲**: 当初
  `config.PACK_SCHEMA_VERSION`はN03・POI入力の変更を含めていなかったが、
  「版番号はパックの中身を一意に表す指紋であるべき」という代表決定により、
  `slim_pack_for_bundle.py`の統合時に`input_pbf_sha256`・`n03_sha256_11`・
  `n03_sha256_13`・`poi_rules_sha256`を含めて組み直すよう変更した
  （詳細は「`pack_version`」節参照）。
- **【Issue #94（2026-09-13）で解決済み】国土数値情報N03の複製承認表示**:
  配布ページの承認番号は「R 4JHf 430」ではなく**「R 5JHf 357」**であることを
  秘書が一次資料で確認・訂正した（「データソースとライセンス」節参照）。
  出典・CC BY 4.0・加工した旨・承認番号を`pack_meta`に記録した。
  **⚠️ ただし画面上での常時表示（T108）は未実装のまま**であり、一般公開前に
  代表が国土地理院へ確認することを推奨する、という論点自体は解決していない
  （引き続きIssue #37・T108で扱う）。
- **【Issue #94（2026-09-13）で解決済み】`district`/`hex_district`/`poi`/`hex_neighbor`
  テーブルの`region_pack.sqlite`への統合**: `slim_pack_for_bundle.py`が4つの出力を
  統合し、`app/assets/pack/`に同梱されるようになった（`bundle_region_pack.sh`・
  `.github/workflows/pack-build.yml`もあわせて更新）。アプリの`RegionPack`実装
  （`location/`側の`RegionPackRepository`）はforward-compat設計により
  コード変更なしに実データを返すようになった。
- **`hex_district`の帰属判定は簡略化前の原本ポリゴンで行っている**が、`district`テーブルに
  格納するのは簡略化後のポリゴンであるため、両者の間に厳密な対応はない（表示用途と
  判定用途を分離する設計判断。詳細は「出力（`out/districts.sqlite`）のテーブル構成」参照）。
  この分離が許容できるかは代表確認事項として残す（未解決のまま）。
- **Tier 2（補完層）POIタグ・ボーナスオブジェクト（allowlist照合）・
  `leisure=park`の面積しきい値の妥当性**: 上記の同梱統合はデータの受け渡し経路の問題
  であり、これらの抽出ルール自体の当否（密度・しきい値が妥当か）とは別の論点のため、
  Issue #94では判断していない（未解決のまま。上記2項目参照）。

### Issue #152（ヘクス隣接関係）で新たに生じた既知の簡略化・要確認事項

- **ペンタゴンセルは考慮していない**: H3の基準グリッドには12個のペンタゴンセル
  （通常5隣接）が存在するが、対象エリア（狭山湖周辺・解像度11）にはいずれも
  出現しないため、`hex_neighbors.py`はこれを特別扱いしていない。将来別エリアの
  パックを作る際、ペンタゴンセルが混入する場合は動作未検証（`grid_ring`自体は
  ペンタゴンでも正しく5隣接を返すため、実害は無いと推測されるが未確認）。
- **保存形式の実測差（約6%）**: 「ヘクス隣接関係」節に記載のとおり、関係テーブル方式の
  ほうが実測で約6%小さいが、単純さ・既存パターン（`boundary_geojson`）との一貫性を
  優先してJSON配列列を採用した。この判断が妥当かは代表確認事項として残す。
