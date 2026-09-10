# app/assets/pack/ — 同梱地域パック（バーティカルスライス対象エリア）

このディレクトリには、バーティカルスライス対象エリア（狭山湖周辺・Issue #85 で確定。
`tools/pack-builder/config.py` の `AREA_SLUG = "sayamako"`）の地域パックを配置する。

**このディレクトリの生成物（`region_pack.sqlite`・`tiles.mbtiles` 等）はコミットしない**
（`.gitignore` 参照。本 `README.md` だけがコミット対象）。`spikes/fixtures/` と同じ
「取得（生成）スクリプト + `.gitignore`」の考え方（plan.md §3・Issue #85）。

## 生成方法

```bash
cd tools/pack-builder
bash bundle_region_pack.sh
```

`tools/pack-builder/README.md` の「バーティカルスライス対象エリアの同梱」の節を参照。
実行すると、このディレクトリに次のファイルが生成される:

| ファイル | 内容 | 生成元 |
|---|---|---|
| `region_pack.sqlite` | ヘクス地形属性（`hex_terrain`）とパックメタ（`pack_meta`。`pack_version` を含む） | `classify_terrain.py` → `slim_pack_for_bundle.py` |
| `tiles.mbtiles` | ベクタタイル（表示専用の基盤地図） | `build_vector_tiles.sh`（Planetiler） |

## pubspec.yaml との関係

`app/pubspec.yaml` の `flutter.assets` はこのディレクトリを**ディレクトリ単位**
（`assets/pack/`）で宣言している。ディレクトリ宣言のため、この `README.md` だけが
存在する状態（＝生成物未取得の状態）でも `flutter test` / `flutter analyze` は失敗しない
（2026-09-10実測で確認済み。`region_pack.sqlite`・`tiles.mbtiles` を退避した状態で
`flutter pub get`・`flutter analyze`（No issues found）・`flutter test -j 1`
（13件全PASS）を確認した。CIの `ci.yml`「Test app」ステップもこの状態で走る）。
ビルド・実機実行時に地図表示を試す場合は、事前に `bundle_region_pack.sh` の実行が必要。

## 地図表示（T055）で読む際の注意

- `region_pack.sqlite` の `hex_terrain` から、`location/` が実行時に fog of war 用の
  GeoJSON FeatureCollection を組み立てる（各 Feature 直下に `feature_id` 列の値を
  整数 `id` として持たせること。`promoteId` は Android 非対応 — plan.md §8）。
  本ディレクトリに GeoJSON ファイルとして同梱しているわけではない
  （参考実装・検証は `tools/pack-builder/export_hex_geojson.py`）。
- `tiles.mbtiles` は Planetiler 標準プロファイル（OpenMapTiles互換スキーマ）で生成した
  表示専用のベクタタイル。`packages/location` の `MapView`（Issue #99・T055）が
  `mbtiles://` 方式でこのファイルをローカル読込する（`url:` を採用した理由は
  `packages/location/lib/src/map/mbtiles_source.dart` のコメント参照）。

## 実機での地図表示確認手順（代表向け・Issue #99・plan.md §8「未計測」の解消）

> **旧手順（`spikes/map_spike_gl` の検証ハーネスを使う方法）は Issue #99 で置き換えた。**
> アプリ本体（`app/lib/features/map/map_screen.dart`・T057）が地図を表示するようになった
> ため、スパイクの別ワークツリーを用意する必要はない。

1. **パックを取得する**（このディレクトリが `README.md` だけの状態ではまだ地図は出ない）:
   ```bash
   cd tools/pack-builder
   bash bundle_region_pack.sh
   ```
   `app/assets/pack/region_pack.sqlite`・`app/assets/pack/tiles.mbtiles` が生成されることを
   確認する（実測: 狭山湖周辺エリアでそれぞれ約750KB・約680KB）。
2. **非対話シェルでビルド/実行する**（対話シェルは sdkman が `JAVA_HOME` を JDK17に
   固定し、`maplibre_gl` 0.27.0系が要求する JDK21 でビルドできず失敗する。
   `docs/dev-setup.md` §2 参照）。**非対話シェル（`bash -lc`）は `~/.bashrc` の
   `flutter`/Android SDK の `PATH` 設定を読み込まない**（`~/.bashrc` 冒頭の
   非対話ガードのため）ので、その場で明示的に export する:
   ```bash
   bash -lc '
     export FLUTTER_HOME="$HOME/flutter"
     export ANDROID_HOME="$HOME/Android/Sdk"
     export PATH="$FLUTTER_HOME/bin:$ANDROID_HOME/platform-tools:$PATH"
     cd ~/terra-town/app && flutter run
   '
   ```
   （`flutter build apk --debug` でも成功するが、`flutter run` を使うと後述のログを
   コンソールにそのまま表示できるので、初回確認には `flutter run` を推奨する。
   `adb install` した上で `adb logcat` を見る方法は、本アプリのログの一部
   （`dart:developer` の `developer.log`）を拾えない可能性が高いため推奨しない。
   `debugPrint` 経由のログは `adb logcat` でも拾えるはずだが未検証のため、
   確実性を優先するなら `flutter run` を使うこと）。
3. **PASS の見分け方**: 起動後、地図タブ（下部ナビ左端「地図」・既定で選択済み）に、
   狭山湖周辺（初期カメラ: 緯度35.82581・経度139.41317・ズーム14・カメラ傾き45度）が
   表示される。
   - 中心付近に teal 系（`#00695C`）の水面（狭山湖の形）が見える
   - 細い灰色の線（道路・`transportation` レイヤー）が見える
   - 小さな灰色の建物footprint（`building` レイヤー。ズーム13以上でのみ描画）が見える
   - ところどころ薄い緑（`landcover`。森・草地）が見える
   - それ以外は背景色（off-white）
   - 画面上部に背景色だけの帯がある場合があるが、これはカメラ傾き（tilt 45度）による
     地平線側の表示であり、**想定どおりの見た目（異常ではない）**
   - パック範囲外（緯度35.70〜35.95・経度139.30〜139.53の外）へパン/ズームすると
     背景色だけになるのも想定どおり
   - コンソール（`flutter run`）に
     `[terra_town_location.map_view] 地域パックのレイヤーを追加しました（fill=3件・line=1件）`
     が出ていれば、addSource/addLayer が例外なく成功したことの確認になる
4. **FAIL の切り分け**:
   - 画面に「地図を表示できませんでした」の文言が出る → パック未取得
     （手順1をやり直す）か、`resolveBundledMbtilesPath` 自体の失敗（アセットコピー
     失敗等）。エラー本文の指示に従う
   - 背景色だけで何のレイヤーも見えず、コンソールに
     `[terra_town_location.map_view] 失敗: 地域パックの source/layer 追加でエラー: ...`
     が出ている → これが本Issueの主目的である「実際の地域パック（高ズーム・
     Planetiler生成）での MBTiles 読込」が実機で失敗したケース。ログの内容を
     Issue #99 のコメントに貼り付けて報告する
   - アプリ自体がクラッシュする → `flutter run` のスタックトレース、または
     `adb logcat | grep -iE 'mbgl|maplibre|terra_town'` を確認する
   - **ネガティブチェック**（パック無しで正しくエラー扱いになることの確認）:
     `app/assets/pack/region_pack.sqlite`・`tiles.mbtiles` を一時的に別の場所へ退避して
     から `flutter run` し、クラッシュせずに「地図を表示できませんでした」の
     エラー画面になることを確認する
5. **「実機で確認した」と言えるのは代表がこの手順を実行した時点から**である。
   本 PR（Issue #99）はここまでの手順を用意するところがスコープであり、
   plan.md §8「未計測」の解消（実機での確認結果の反映）は別途行うこと。
