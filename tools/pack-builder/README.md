# tools/pack-builder/ — 地域パック生成パイプライン（最小プロトタイプ）

Issue #38（[Spike] pack-builder 最小プロトタイプで地形属性の事前計算を1エリア分検証する）の成果物。

`specs/001-mvp/plan.md` §4「資材分類の決定論（事前計算）」・`docs/terrain.md` §4・§5 で定義された
「OSM抽出 → 細分グリッドセルでの地形判定 → H3ヘクスへの多数決集約 → SQLite出力」という
パイプラインの**最小プロトタイプ**（使い捨てコード可・1エリア分の検証が目的）。

**本ツールの生成物（`.osm.pbf`・`.sqlite`）はコミットしないこと**（`.gitignore` 済み）。

検証結果・使用ツールのバージョン・所要時間・出力サイズなどの記録は
`specs/001-mvp/research.md` §8 を参照。ヘクスID体系（H3）・feature id橋渡し方式の
設計判断は `docs/terrain.md` §3.1・§4.2〜§4.4 に記録済み（本ツールはその実装）。

## スコープ

本Issueで実装するのはこれだけ:

- 対象エリア1つ分の OSM抽出 → 地形属性の事前計算 → SQLite出力
- 分類結果の抜き取り検証・決定論の検証
- ヘクスID体系（H3）・feature id橋渡し方式の確定

以下は**スコープ外**（他のタスクで実装する）:

- ベクタタイル MBTiles の生成（Planetiler本体・tasks.md T039）
- 行政区域N03の取り込み（T041）・名所POI抽出（T042）・`pack_version`付与（T043）
- パック生成のCI化（T045・`.github/workflows/pack-build.yml`）
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
```

## 出力（`out/pack.sqlite`）のテーブル構成

| テーブル | 列 | 説明 |
|---|---|---|
| `cell_terrain` | `cell_id, hex_id, lon, lat, terrain_type` | 細分グリッドセル（`config.CELL_SIZE_M`四方）単位の判定結果。生成過程の中間データ |
| `hex_terrain` | `hex_id, terrain_type, feature_id, cell_count` | H3ヘクス単位に多数決集約した最終結果。`hex_id`はH3 index（64bit整数、正）。`feature_id`は地図Feature用に下位52bitマスクした値（`docs/terrain.md` §4.4参照）。`cell_count`はそのヘクスに属した細分セル数（多数決の強さの参考値） |
| `pack_meta` | `key, value` | 生成条件（bbox・解像度・セルサイズ・入力ファイルのSHA256・所要時間・各ツールのバージョン等） |

`hex_terrain`だけを残した場合のサイズは`cell_terrain`込みの場合よりかなり小さい
（実測: `specs/001-mvp/research.md` §8.1）。`cell_terrain`を実際のパックに同梱するかは
`plan.md` §3.2 のパック内容物設計で別途判断すること。

## ファイル構成

- `config.py` — 対象エリア(bbox)・グリッドセルサイズ・H3解像度などの設定値
- `terrain_rules.py` — `docs/terrain.md` §5 の判定ルールの実装（優先順位付きタグ判定）
- `local_projection.py` — 緯度経度⇔ローカル平面座標（メートル）の簡易変換（グリッド敷き詰め・バッファ計算用）
- `hex_bridge.py` — H3 index ⇔ 地図Feature `id` の変換（下位52bitマスク方式。設計判断は`docs/terrain.md` §4.4）
- `classify_terrain.py` — パイプライン本体
- `verify_determinism.py` — 決定論の検証（2回生成して`hex_terrain`を比較）
- `verify_feature_id.py` — H3 index <-> feature_id 橋渡し方式の検証（衝突なし・JSON安全整数範囲内・可逆性）
- `spot_check_samples.py` — 抜き取り検証用のサンプルヘクス抽出
- `h3_resolution_survey.py` — H3解像度ごとの平均対辺・実測対辺の算出（`docs/terrain.md` §3.1・`research.md` §8.2 の実測値の再現用）
- `peak_radius_sensitivity.py` — `natural=peak`バッファ半径（`terrain_rules.MOUNTAIN_PEAK_BUFFER_M`）を30〜200mで変化させた場合の山ヘクス数・森の侵食数の再現用（`research.md` §8.9.3。Issue #71で「30m据え置き」と判断した根拠データ）
- `download_kanto.sh` / `extract_area.sh` — OSM抽出のダウンロード・bbox切り出し

## 既知の簡略化・未解決事項

`specs/001-mvp/research.md` §8.7 および `terrain_rules.py`・`docs/terrain.md` §5.1 のコメント参照。

**【Issue #71（2026-09-08）で対応済み】** 「山」判定タグを拡張（`natural=hill`/`cliff`/`rock`を追加）したが、
検証エリア（狭山湖周辺）には追加タグに該当する実データが存在せず、出現率は0.02%のまま変化しなかった
（実測結果・DEM要否の結論は`research.md` §8.9参照）。山の出現率不足の解消自体は
[Issue #72](https://github.com/rokusoudo-product/terra-town/issues/72)（石・鉄・塩の供給源）に引き継がれている。
