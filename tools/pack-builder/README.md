# tools/pack-builder/ — 地域パック生成パイプライン

Issue #38（[Spike] pack-builder 最小プロトタイプで地形属性の事前計算を1エリア分検証する）と
Issue #85（[Impl] Planetiler でベクタタイル MBTiles を生成しバーティカルスライスの地域パックを
同梱する）の成果物。

`specs/001-mvp/plan.md` §3.2「地域パックの内容物」・§4「資材分類の決定論（事前計算）」・
`docs/terrain.md` §4・§5 で定義されたパイプラインの実装:

```
OSM抽出 → 細分グリッドセルでの地形判定 → H3ヘクスへの多数決集約 → SQLite出力（Issue #38）
                                                                  → ベクタタイルMBTiles生成（Planetiler・Issue #85）
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

本ツールが実装するのはこれだけ（Issue #38・#85）:

- 対象エリア1つ分の OSM抽出 → 地形属性の事前計算 → SQLite出力（Issue #38）
- 分類結果の抜き取り検証・決定論の検証（Issue #38）
- ヘクスID体系（H3）・feature id橋渡し方式の確定（Issue #38）
- **ベクタタイル MBTiles の生成（Planetiler・Issue #85・T039）**
- **パックメタ（`pack_version`）の付与・各ヘクスFeature直下への整数`id`の実装確認（Issue #85・T043）**
- **バーティカルスライス対象エリアのパック生成・`app/assets/`への同梱の仕組み（Issue #85・T044）**
- **パック生成のCI化（Issue #85・T045・`.github/workflows/pack-build.yml`）**

以下は**スコープ外**（他のIssueで実装する）:

- 行政区域N03の取り込み（T041）・名所POI抽出（T042） — Issue #86
- 地図表示の実装そのもの（T055）
- 地図表示側の検証（Issue #24のR1・R2。`spikes/`配下は本ツールと無関係）

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
```

上記3〜10を一括で実行し、`app/assets/pack/` への同梱まで行う場合は
`bash bundle_region_pack.sh` を使う（下記「バーティカルスライス対象エリアの同梱」参照）。

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
`README.md`だけが存在する状態（＝未生成）でも`flutter test`/`flutter analyze`は失敗しない。

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

`spikes/map_spike_gl`のハーネス（ブランチ`feature/issue-24-map-spike-harness`系・
`main`にマージ済み。`spikes/map_spike_gl/lib/map_probe_page.dart`）がそのまま使える。
ただし、このハーネスは検証時のフィクスチャ（MapLibre公式デモの`maplibre.mbtiles`）に
合わせて**layer名をソースコードに直書き**している（`kFixtureFillSourceLayer =
'countries'`・`kFixtureLineSourceLayer = 'geolines'`）。terra-townのパックには
`countries`・`geolines`という層は存在しない（上記「実測」の層一覧参照）ため、
**そのまま実行すると「レイヤーが見つからない」ため描画されない**。

1. `bash bundle_region_pack.sh`で`app/assets/pack/tiles.mbtiles`を生成する。
2. `spikes/map_spike_gl/assets/`に`tiles.mbtiles`をコピーする（`fetch_fixtures.sh`が
   `sample.mbtiles`をコピーしているのと同じ要領）。
3. `spikes/map_spike_gl/lib/map_probe_page.dart`の以下2点を書き換える:
   - `rootBundle.load('assets/sample.mbtiles')` → `'assets/tiles.mbtiles'`
   - `kFixtureFillSourceLayer = 'countries'` → `'building'`（または`'water'`・`'landuse'`など、
     上記レイヤ一覧から見た目で確認しやすいもの）
   - `kFixtureLineSourceLayer = 'geolines'` → `'transportation'`
4. `flutter run`で実機にインストールし、タブ①「同梱フィクスチャをコピーして使う」→
   ②/③のボタンで`addSource`/`addLayer`が例外なく成功し、建物・道路等が実際に
   描画されるかを目視確認する。
5. ソース構築コストの計測は、ハーネスの性能計測タブが**ヘクス数を指定して合成ジオメトリを
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

## 既知の簡略化・未解決事項

`specs/001-mvp/research.md` §8.7 および `terrain_rules.py`・`docs/terrain.md` §5.1 のコメント参照。

**【Issue #71（2026-09-08）で対応済み】** 「山」判定タグを拡張（`natural=hill`/`cliff`/`rock`を追加）したが、
検証エリア（狭山湖周辺）には追加タグに該当する実データが存在せず、出現率は0.02%のまま変化しなかった
（実測結果・DEM要否の結論は`research.md` §8.9参照）。山の出現率不足の解消自体は
[Issue #72](https://github.com/rokusoudo-product/terra-town/issues/72)（石・鉄・塩の供給源）に引き継がれている。
