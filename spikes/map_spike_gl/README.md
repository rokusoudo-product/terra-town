# map_spike_gl — Issue #24 検証ハーネス（`maplibre_gl` 用）

**これは使い捨ての検証ハーネスであり、製品コードではありません。**

- terra-town 本体（`app/` `packages/core/` `packages/location/`）とは一切関係がなく、依存もしていません。
- `DESIGN.md` のデザイントークンには準拠していません（色・サイズを直書きしています）。これは代表が実機で
  ボタンを押して数値を読み取るための検証専用UIであり、製品UIではないためです。
- 目的は [Issue #24](https://github.com/rokusoudo-product/terra-town/issues/24) の受け入れ基準を満たすための
  **実機計測を代表が行うための道具**を用意することです。このハーネス自体は Issue #24 を完了させません。
  実機での計測・`specs/001-mvp/research.md` への転記は代表が行います。

## これは何を検証するか

`specs/001-mvp/research.md`（PR #41・机上調査ドラフト、2026-08-11時点でマージ待ち）の §6 チェックリストのうち、
以下に対応する画面を提供します。

| このアプリのUI | research.md §6 の項目 |
|---|---|
| 上部バナー: プラグイン名・版数・stable/git main | §6.1「実機での最終判断」の前提記録 |
| タブ①「② 基本地図表示」 | §6.1 の基本動作確認 |
| タブ①「③ ローカルMBTiles読込」 | §6.2 T012/R1 |
| タブ①「④ PMTiles読込」 | §6.2 のフォールバック候補 |
| タブ①「⑤ addSource/addLayer 疎通」 | §6.3 T013/R1 |
| タブ①「⑥ feature-state プローブ」 | §6.3 T013/R1（feature-stateの可否） |
| タブ②「fog of war 性能」 | §6.4 T014/R2（plan.md §8 の数値基準） |

## 代表向けの実行手順

### 1. 実機をWSLに接続する

USB接続でWSLから直接使う場合（推奨・本ハーネスの手順として指定されたもの）:

1. 端末をUSBでWindows PCに接続し、開発者オプション > USBデバッグ を ON にする
2. Windows PowerShell で `usbipd list` を実行し、端末の busid（例: `2-4`）を確認する
3. `usbipd attach --wsl --busid <busid>` を実行する（管理者権限が必要な場合あり）
4. **WSLにアタッチしている間はWindows側のadbからは端末が見えなくなる。これは正常な挙動。**
   （usbipd はUSBデバイスをWindowsホストからWSL側へ「移譲」する方式のため、両側から同時には見えない）
5. WSL側で `/home/zakis/flutter/bin/flutter devices` を実行し、端末が一覧に出ることを確認する

`docs/dev-setup.md` §5 に記載のワイヤレスデバッグ（`adb pair` / `adb connect`）でも代替可能です。

### 2. アプリを実行する

```bash
cd ~/terra-town/spikes/map_spike_gl
/home/zakis/flutter/bin/flutter run
```

`flutter devices` に複数出る場合は `-d <deviceId>` を付ける。

### 3. 各タブのボタンを順に押し、画面の数値をスクリーンショット、または手で
   `specs/001-mvp/research.md` §6 の該当欄に転記する。

## タブ①: 地図/MBTiles/feature-state

1. **② 基本地図表示**: デフォルトで MapLibre 公式デモスタイル
   （`https://demotiles.maplibre.org/style.json`）が表示される。別スタイルを試したい場合は
   URL欄に入力して「スタイル適用」を押す。
2. **③ ローカルMBTiles読込**: パス欄に端末上のMBTilesファイルの絶対パスを直接入力し、
   「MBTiles読込を試す」を押す。research.md §2.1 の手順（書き込み可能ディレクトリへコピー →
   `mbtiles://<パス>` を `RasterSourceProperties` 経由で `addSource`）を実装している。
   非公式・未文書化の挙動（[Issue #318](https://github.com/maplibre/flutter-maplibre-gl/issues/318)）のため、
   例外が出ないことと実際にタイルが描画されることの両方を目視確認すること。
   **ネイティブのファイル選択ダイアログは実装していない**（下記「既知の制約」参照）。
   端末上のパスは事前に `adb push` 等で把握しておくこと。
3. **④ PMTiles読込**: 公式サンプル（`pmtiles_style.json`）と同じ「スタイルJSON内のsource.urlに
   `pmtiles://...` を書く」方式。ローカルファイルパスでの構文は公式サンプル（リモートURL）からの
   類推であり、未検証。こちらもパスはテキスト入力のみ。
4. **⑤ addSource/addLayer 疎通**: 3ヘクス分の合成GeoJSONを動的に追加し、赤いポリゴンとして描画されるか確認。
5. **⑥ feature-state プローブ**: `setFeatureState` を呼び出す。0.26.2（pub.dev安定版）では
   `UnimplementedError` が投げられる想定（research.md §3.2）。例外の型・メッセージがそのまま画面に出る。

## タブ②: fog of war 性能計測

1. ヘクス数（1,000 / 5,000 / 10,000）を選択する。
2. 「fog生成 + 更新ベンチマーク実行」を押す。穴あきポリゴン1枚のGeoJSONを作り、
   選択したヘクス数ぶん「1ヘクスずつ開示する」`setGeoJsonSource` 更新を繰り返す。
   - 各更新の所要時間（ms）を計測し、完了後に min/median/max/avg を表示する。
   - 目標（plan.md §8）: **1回の更新が200ms以内**。
   - 同時に、更新ループの実行中に発生したフレームのfps・ジャンク数も自動収集して表示する。
3. ループ完了後（=選択したヘクス数ぶん開示された状態）、「③ 手動パン・ズームfps計測」で
   「開始」を押し、**代表が実際に地図をパン・ズーム操作**してから「停止」を押す。
   - 目標（plan.md §8）: **1万ヘクス開示状態で55fps以上**。この基準を厳密に検証するには
     ヘクス数として **10000** を選んだ状態で操作すること。
   - 自動操作はできない（実端末でのタッチ操作をコード側から起こす手段は用意していない）ため、
     ここだけは手動操作が必須。

### 計測方法の限界（正直な注記）

- ジャンク判定は 16.67ms（60Hz想定）を固定閾値として使っている。実機のリフレッシュレート
  （90Hz/120Hz等）に応じた可変閾値にはしていない。
- fps は「収集期間中の観測フレーム数 ÷ 収集期間の実時間」の単純平均。
- 計測Aは `Stopwatch` で `await controller.setGeoJsonSource(...)` の完了までの時間を計測している。
  これは「Dartのawaitが返るまでの時間」であり、プラットフォームチャネルの往復・ネイティブ側の
  再テッセレーション・再描画のどこまでを含むかの内訳は分解できていない（Issue #366 の指摘する
  `jsonEncode` のメインアイソレート占有時間は、この所要時間に含まれるはず）。

## バージョン切り替え（pub.dev安定版 ⇔ git main）

`pubspec.yaml` の既定は pub.dev 安定版 `maplibre_gl: 0.26.2` です。
git 依存でmainブランチを直接参照する記述をコメントアウトで併記してあります:

```yaml
dependencies:
  maplibre_gl: ^0.26.2
  # 0.27.0（未リリース・feature-state Android対応 + #366性能改善を含む）を試す場合は
  # 上の行をコメントアウトし、以下を有効化する:
  # maplibre_gl:
  #   git:
  #     url: https://github.com/maplibre/flutter-maplibre-gl.git
  #     ref: main
  #     path: maplibre_gl
```

切り替えたら **`lib/plugin_info.dart` の `kPluginVersionLabel` も必ず手で書き換える**こと
（画面上部のバナーが自動判定していないため）。

- **安定版で回すと「今日出荷できるか」が分かる**（feature-stateは使えない前提での検証）。
- **git mainで回すと「0.27.0で直るか」が分かる**（feature-state Android対応 + Issue #366の性能改善）。
- **両方回すことを推奨**します。切り替え後は `flutter pub get` を忘れずに。

## MBTiles / PMTiles フィクスチャ

地域パック（`tools/pack-builder/`）は未実装のため、terra-town独自の実データはまだありません。
かわりに、`spikes/fixtures/fetch_fixtures.sh` で MapLibre 公式配布の軽量サンプル
（世界地図・国境ポリゴン、z0-6、MBTiles約5MB・PMTiles約3.8MB、Natural Earth Data＝パブリックドメイン）
を取得できます。詳細は `spikes/fixtures/README.md` を参照。バイナリはコミットしません。

```bash
cd ~/terra-town/spikes/fixtures
bash fetch_fixtures.sh
adb push sample.mbtiles /sdcard/Download/
adb push sample.pmtiles /sdcard/Download/
```

その後、アプリの入力欄に `/sdcard/Download/sample.mbtiles`（または`.pmtiles`）を入力するか、
「ファイル選択」で選ぶ。MBTiles/PMTilesパスは**画面から自由に指定・変更できる設計**にしてあるので、
代表が別途用意したファイル（例: [MapTiler](https://www.maptiler.com/) や
[Protomaps](https://protomaps.com/) のサンプル、`pmtiles convert` で自作したもの）でも試せます。

fog of war 性能計測（タブ②・最重要項目）はMBTilesなしで実行できます（合成GeoJSONのみで完結）。

## 既知の制約

- **ネイティブのファイル選択ダイアログは未実装**。当初 `file_picker` パッケージで実装する予定だったが、
  `file_picker: ^11.0.3` が独自に適用するKotlin Gradle Plugin（KGP）と `maplibre_gl` のそれが
  衝突し、`flutter build apk --debug` が
  `GeneratedPluginRegistrant.java: cannot find symbol FilePickerPlugin` で失敗した
  （`flutter build apk` の出力にも「Future versions of Flutter will fail to build if your app uses
  plugins that apply KGP」という警告が出ている。file_picker と maplibre_gl の両方がこれに該当）。
  無理に動かそうとせず、`file_picker` への依存自体を外し、MBTiles/PMTilesのパスは
  テキスト入力のみで指定する方式に変更した。ファイル選択が必要な場合は `adb push` で
  端末の既知のパス（例: `/sdcard/Download/`）に配置し、そのパスを手入力すること。

## 環境

- Flutter 3.44.8 / Dart 3.12.2（`docs/dev-setup.md` §2 準拠）
- `maplibre_gl: ^0.26.2`（pub.dev安定版）
- Android minSdk はFlutterのデフォルト値をそのまま使用（`maplibre_gl` の要求 minSdk 21 を上回る）
- ビルド時にAndroid SDK Platform 35が自動インストールされる（`maplibre_gl` の要求）。
  `docs/dev-setup.md` §2 記載の環境にはPlatform 36のみが入っていたため、初回ビルド時に追加された。

## コンパイル確認（実施済み・実機実行は未実施）

- `flutter analyze`: 実施済み（結果はPR本文参照）
- `flutter build apk --debug`: 実施済み（結果はPR本文参照）
- **実機での起動・動作確認はしていません。** 実機が接続されていない環境で作業したため。
