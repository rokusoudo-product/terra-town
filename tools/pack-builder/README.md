# tools/pack-builder/ — 地域パック生成パイプライン

Issue #38（[Spike] pack-builder 最小プロトタイプで地形属性の事前計算を1エリア分検証する）と
Issue #85（[Impl] Planetiler でベクタタイル MBTiles を生成しバーティカルスライスの地域パックを
同梱する）、Issue #86（[Impl] 地域パックに行政区域と名所POIを追加しT040の完了状態を確定する）
の成果物。

`specs/001-mvp/plan.md` §3.2「地域パックの内容物」・§4「資材分類の決定論（事前計算）」・
`docs/terrain.md` §4・§5 で定義されたパイプラインの実装:

```
OSM抽出 → 細分グリッドセルでの地形判定 → H3ヘクスへの多数決集約 → SQLite出力（Issue #38・T040）
                                                                  → ベクタタイルMBTiles生成（Planetiler・Issue #85・T039）
国土数値情報N03 → 対象エリアと交差する市区町村を抽出 → トポロジ保持簡略化 → ヘクス帰属判定 → SQLite出力（Issue #86・T041）
OSM抽出 → 観光POIタグ（Tier 1）抽出 → 名称・面積フィルタ → SQLite出力（Issue #86・T042）
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

本ツールが実装するのはこれだけ（Issue #38・#85・#86）:

- 対象エリア1つ分の OSM抽出 → 地形属性の事前計算 → SQLite出力（Issue #38・T040）
- 分類結果の抜き取り検証・決定論の検証（Issue #38）
- ヘクスID体系（H3）・feature id橋渡し方式の確定（Issue #38）
- **ベクタタイル MBTiles の生成（Planetiler・Issue #85・T039）**
- **パックメタ（`pack_version`）の付与・各ヘクスFeature直下への整数`id`の実装確認（Issue #85・T043）**
- **バーティカルスライス対象エリアのパック生成・`app/assets/`への同梱の仕組み（Issue #85・T044）**
- **パック生成のCI化（Issue #85・T045・`.github/workflows/pack-build.yml`）**
- **行政区域ポリゴン（国土数値情報N03）の取り込み・トポロジ保持簡略化・ヘクス帰属判定（Issue #86・T041）**
- **名所POI（OSM観光POI・Tier 1）の抽出（Issue #86・T042）**

以下は**スコープ外**（他のIssueで実装する、または本Issueで明示的に見送った）:

- 地図表示の実装そのもの（T055）
- 地図表示側の検証（Issue #24のR1・R2。`spikes/`配下は本ツールと無関係）
- ODbL適合の詳細検証・`docs/licenses.md`への記録（Issue #37）
- 名所オブジェクトのゲーム内仕様（`is_bonus`・収集判定・報酬計算等。Issue #6・`docs/landmark_objects.md`）
- Tier 2（補完層）POIタグ・ボーナスオブジェクト（allowlist照合）の抽出（`poi_rules.py`のdocstring参照。
  目標密度・allowlistとも仮値/未整備のため本Issueでは実装しない）
- `district`/`hex_district`/`poi`テーブルを`region_pack.sqlite`（`slim_pack_for_bundle.py`・
  `bundle_region_pack.sh`・`app/assets/pack/`）へ同梱すること（Issue #85・T044の対象であり
  本Issueでは「作り直さない」よう明示されている。本Issueは`out/districts.sqlite`・
  `out/poi.sqlite`という独立した出力を作るところまで。同梱への統合は別途フォローアップが必要
  — 下記「既知の簡略化・未解決事項」参照）

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
# out/region_pack.sqlite が生成される（約750KB。cell_terrain込みの63MBに対して1.2%）

# 10. 各ヘクスFeature直下に整数idがあることの検証（T043の受け入れ基準を実際に確認する）
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
```

上記3（`classify_terrain.py`）・7（`build_vector_tiles.sh`）・9（`slim_pack_for_bundle.py`）
と`app/assets/pack/`へのコピーを一括で実行する場合は `bash bundle_region_pack.sh` を使う
（下記「バーティカルスライス対象エリアの同梱」参照）。**決定論の検証（4・8・13・15）や
Feature id の検証（10）は含まれない**ため、それらは別途上記の手順で個別に実行すること。
**`bundle_region_pack.sh`は12〜15（行政区域・POI）を含んでいない**（下記「スコープ」・
「既知の簡略化・未解決事項」参照。`out/districts.sqlite`・`out/poi.sqlite`は
`app/assets/pack/`への同梱・`slim_pack_for_bundle.py`への統合を本Issueでは行っていない）。

## 出力（`out/pack.sqlite`）のテーブル構成

| テーブル | 列 | 説明 |
|---|---|---|
| `cell_terrain` | `cell_id, hex_id, lon, lat, terrain_type` | 細分グリッドセル（`config.CELL_SIZE_M`四方）単位の判定結果。生成過程の中間データ |
| `hex_terrain` | `hex_id, terrain_type, feature_id, cell_count` | H3ヘクス単位に多数決集約した最終結果。`hex_id`はH3 index（64bit整数、正）。`feature_id`は地図Feature用に下位52bitマスクした値（`docs/terrain.md` §4.4参照） |
| `pack_meta` | `key, value` | 生成条件（`pack_version`・bbox・解像度・セルサイズ・入力ファイルのSHA256・所要時間・各ツールのバージョン等） |

**`cell_terrain`は同梱対象外と判断した**（Issue #85・T044）。生成過程の中間データであり
（抜き取り検証`spot_check_samples.py`・デバッグ用途）、fog of war の実行には`hex_terrain`
だけで足りるため。`slim_pack_for_bundle.py`が`cell_terrain`を除いた`region_pack.sqlite`
（実測 約750KB。`cell_terrain`込みの63MBに対して1.2%）を作る。

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
- **利用規約**: 「国土数値情報 利用規約」（令和元年以降のデータはオープンデータ）。
  ただし配布ページには「測量法に基づく国土地理院長承認（複製）R 4JHf 430」
  「本製品を複製する場合には、国土地理院の長の承認を得なければならない。」という
  原典表示の注記がある。**この複製承認の要否・対応はIssue #86では判断せず、
  代表確認事項として残す**（詳細なライセンス適合の記録・`docs/licenses.md`への反映は
  Issue #37のスコープ）。
- **座標系**: JGD2011（EPSG:6668）。OSM由来データ（WGS84）との差は数10cmオーダーで、
  本パイプラインの精度要件（ヘクス約50m四方）に対して無視できるため、既存の
  `classify_terrain.py`と同様に座標変換は行っていない。

### 名所POI（T042）

- **データソース**: OpenStreetMap（`tools/pack-builder/data_cache/area.osm.pbf`。
  Geofabrik関東地方抽出からのbbox切り出し。`classify_terrain.py`と同じキャッシュを再利用）。
- **ライセンス**: Open Database License (ODbL) 1.0 — © OpenStreetMap contributors。
- **詳細な適合検証（属性表示義務・派生データベースの扱い等）はIssue #37のスコープ**であり、
  本Issueでは出典の記録のみを行う。

## `pack_version`（T043）

`classify_terrain.py`が`pack_meta`に書き込む。形式:
`{AREA_SLUG}-v{PACK_SCHEMA_VERSION}-{入力OSM抽出のsha256先頭12桁}`
（例: `sayamako-v1-9a66e066b0d4`）。生成時刻や生成順序に依存しない純関数
（`hex_bridge.py`の`feature_id`と同じ設計方針。理由は`config.py`の`PACK_SCHEMA_VERSION`
のコメント参照）。**`terrain_rules.py`の判定ルールや`H3_RESOLUTION`を変えたときは、
必ず`config.PACK_SCHEMA_VERSION`をインクリメントすること**（さもないと同一OSM入力に対して
ロジックが変わったのに同じ`pack_version`になり、plan.md §3.3の不変性ルールの前提が壊れる）。

## 各ヘクスFeature直下の整数`id`（T043）

`hex_terrain.feature_id`列がこれに当たる（Issue #38で実装済み・`hex_bridge.py`）。
`export_hex_geojson.py`が実際にGeoJSON Featureを組み立て、
「直下（`properties`の外）に整数`id`を持つ」「重複がない」ことを実データ（13,106件）で
検証する。**このGeoJSONファイル自体はパックに同梱しない**（参照実装・検証用。
plan.md §8のとおり`location/`が実行時に`hex_terrain`から組み立てる。詳細は
`export_hex_geojson.py`冒頭のdocstring参照）。

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

## バーティカルスライス対象エリアの同梱（T044）

`bundle_region_pack.sh`が上記のパイプライン全体（地形属性事前計算 → 軽量化 →
ベクタタイル生成）を実行し、`app/assets/pack/`に同梱する。

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

**実測（2026-09-10・狭山湖周辺エリア）**:

| 項目 | 値 |
|---|---|
| ヘクス数 | **13,106**（plan.md §3.5 の暫定上限30,000の44%） |
| `pack_version` | `sayamako-v1-9a66e066b0d4` |
| `region_pack.sqlite`（同梱分） | 約750KB |
| `tiles.mbtiles`（同梱分） | 約680KB |
| 地形属性の事前計算（`classify_terrain.py`） | 約6.7秒 |
| ベクタタイル生成（`build_vector_tiles.sh`） | 約39秒〜1分20秒 |

## 実機での読込確認手順（代表向け・plan.md §8「未計測」の解消）

`plan.md` §8「未計測」に残る「実際の地域パック（Planetiler生成・日本・高ズーム）での
MBTiles読込は未実施」（T012が確認したのはMapLibre公式デモの世界地図サンプルであって
terra-town自身の地域パックではない）を解消するための手順。**実機実行は代表が行う
ため、以下は手順の用意のみ（本Issueのスコープ）。**

`spikes/map_spike_gl`のハーネス（`spikes/map_spike_gl/lib/map_probe_page.dart`）が
そのまま使える。**⚠️ ただしこのブランチ（`feature/issue-24-map-spike-harness`系）は
まだ`main`にマージされていない**（`git ls-tree -r main -- spikes/`が空であることを
確認済み。作業ディレクトリに残っている`spikes/`はビルド成果物のみで`lib/`を含まない）。
別途チェックアウトが必要:

```bash
git fetch origin feature/issue-24-map-spike-harness
git worktree add ../terra-town-spike origin/feature/issue-24-map-spike-harness
cd ../terra-town-spike/spikes/map_spike_gl
```

このハーネスは検証時のフィクスチャ（MapLibre公式デモの`maplibre.mbtiles`。世界地図・
z0-6）に合わせて**layer名・ズーム範囲・カメラ位置をソースコードに直書き**している
（`kFixtureFillSourceLayer = 'countries'`・`kFixtureLineSourceLayer = 'geolines'`・
`kFixtureMinZoom/MaxZoom = 0/6`・`kOriginLat/Lng`＝東京駅付近）。terra-townのパックは
`countries`・`geolines`という層を持たず、ズーム0-14・狭山湖周辺という別のデータのため、
**書き換えずに実行すると「レイヤーが見つからない」「ズーム範囲外で何も描画されない」
「カメラが無関係の場所を向いている」のいずれかで失敗する**。

1. terra-townリポジトリ側で`bash bundle_region_pack.sh`を実行し、
   `app/assets/pack/tiles.mbtiles`を生成する。
2. 生成した`tiles.mbtiles`を、ハーネス側の`spikes/map_spike_gl/assets/sample.mbtiles`
   に**上書きコピー**する（ファイル名を`sample.mbtiles`のままにすることで、
   `rootBundle.load('assets/sample.mbtiles')`やタブ①「同梱フィクスチャをコピーして
   使う」ボタンをコード変更なしで流用できる）。
3. `spikes/map_spike_gl/lib/map_probe_page.dart`の以下を書き換える:
   - `kFixtureFillSourceLayer = 'countries'` → `'building'`（または`'water'`・
     `'landuse'`など。上記「実測」のレイヤ一覧から見た目で確認しやすいもの）
   - `kFixtureLineSourceLayer = 'geolines'` → `'transportation'`
   - `kFixtureMinZoom = 0` / `kFixtureMaxZoom = 6` → `0` / `14`（terra-townのパックは
     zoom 0-14。`building`はminzoom 13のため、maxzoomを6のままにすると
     ズーム範囲外で常に空振りする）
4. `spikes/map_spike_gl/lib/hex_grid.dart`の`kOriginLat`/`kOriginLng`
   （既定は東京駅付近: 35.681236 / 139.767125）を、狭山湖周辺のパック中心付近
   （`tiles.mbtiles`のmetadata実測値: 緯度35.82581・経度139.41317）に書き換える
   （`map_probe_page.dart`の`initialCameraPosition`と各ベンチマークページのカメラが
   この定数を参照しているため、変更しないと無関係の場所（東京駅周辺）にカメラが
   向いたままになる）。
5. `flutter run`で実機にインストールし、タブ①「同梱フィクスチャをコピーして使う」→
   ②/③のボタンで`addSource`/`addLayer`が例外なく成功し、建物・道路等が実際に
   描画されるかを目視確認する。
6. ソース構築コストの計測は、ハーネスの性能計測タブが**ヘクス数を指定して合成ジオメトリを
   生成する**方式のため、terra-townの実パックそのものの計測ではない。
   **本Issueで生成した実際のヘクス数（13,106）を指定して計測すること**を手順として
   明記する。これは「同じFeature数・合成ジオメトリでの代理計測」であり、
   実パックのジオメトリ複雑さを反映した計測ではない点に注意（plan.md §3.5の
   「実測で確定する」という宿題に対して、この代理計測がどこまで有効かは代表の判断に委ねる）。

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
- `slim_pack_for_bundle.py` — 同梱用に`cell_terrain`を除いた軽量SQLiteを作る（Issue #85・T044）
- `export_hex_geojson.py` — 各ヘクスFeature直下の整数`id`要件（T043）の検証・参照実装
- `bundle_region_pack.sh` — 上記を一括実行し`app/assets/pack/`へ同梱する（Issue #85・T044）
- `download_n03.sh` — 国土数値情報N03（行政区域データ）のダウンロード（Issue #86・T041）
- `extract_districts.py` — 行政区域ポリゴンの取り込み・トポロジ保持簡略化・ヘクス帰属判定（Issue #86・T041）
- `verify_districts_determinism.py` — 行政区域データの決定論検証（Issue #86・T041）
- `poi_rules.py` — `docs/landmark_objects.md` §2.1 の名所POI抽出ルール（Tier 1のみ）の実装（Issue #86・T042）
- `extract_poi.py` — 名所POI抽出パイプライン本体（Issue #86・T042）
- `verify_poi_determinism.py` — 名所POIデータの決定論検証（Issue #86・T042）

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
- **`pack_version`の対象範囲**: `config.PACK_SCHEMA_VERSION`は「地形判定ルール・
  グリッド解像度・feature_id方式」の変更時にインクリメントする値であり（`config.py`の
  コメント参照）、N03・POI入力の変更はこの定義に含めていない（`PACK_SCHEMA_VERSION`は
  1のまま据え置いた）。`district_progress.district_id`・`collection.poi_id`が参照する
  識別子はいずれもN03の`N03_007`・OSMの`node/way/relation`id由来の**安定した外部ID**
  であるため、N03/POIの入力データが更新されても`pack_version`を変えるか否かに関わらず
  plan.md §3.3の不変性ルール（過去の獲得履歴の同一性）は保たれるという整理である。
  この整理が妥当か、あるいは`pack_version`にN03のedition・POI入力のsha256等も
  含めるべきかは代表確認事項として残す。
- **国土数値情報N03の複製承認表示**: 配布ページに「測量法に基づく国土地理院長承認
  （複製）R 4JHf 430」「本製品を複製する場合には、国土地理院の長の承認を得なければ
  ならない。」という原典表示の注記がある。この対応要否の判断は本Issueでは行わず、
  代表確認事項として残す（詳細な適合検証・`docs/licenses.md`への反映はIssue #37）。
- **`district`/`hex_district`/`poi`テーブルは`region_pack.sqlite`（`app/assets/pack/`への
  同梱物）に統合されていない**: `slim_pack_for_bundle.py`・`bundle_region_pack.sh`・
  `.github/workflows/pack-build.yml`はいずれも`hex_terrain`/`pack_meta`のみを対象に
  ハードコードされており（Issue #85・T044・T045で完了済み）、本Issueではこれらを
  変更していない（「ベクタタイルMBTilesの生成・パック同梱はIssue #85完了済みで
  作り直さない」というIssue #86のスコープ制約に従った）。したがって
  `out/districts.sqlite`・`out/poi.sqlite`は現時点では`app/assets/pack/`に
  同梱されず、アプリの`RegionPack`実装（`location/`側のT069）から参照できない。
  **同梱への統合は別途フォローアップIssueが必要**（代表確認事項）。
- **`hex_district`の帰属判定は簡略化前の原本ポリゴンで行っている**が、`district`テーブルに
  格納するのは簡略化後のポリゴンであるため、両者の間に厳密な対応はない（表示用途と
  判定用途を分離する設計判断。詳細は「出力（`out/districts.sqlite`）のテーブル構成」参照）。
  この分離が許容できるかは代表確認事項として残す。
- **CI（`.github/workflows/pack-build.yml`）は本Issueの新スクリプト
  （`download_n03.sh`・`extract_districts.py`・`extract_poi.py`とその検証スクリプト）を
  呼び出していない**: 上記の同梱未統合と同じ理由でワークフローを変更していない。
