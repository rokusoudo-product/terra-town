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
| タブ②「fog of war 性能(第一案:再エンコード)」 | §6.4 T014/R2（plan.md §8 の数値基準） |
| タブ③「fog of war 性能(第二案:feature-state)」 | §6.4 T014/R2 再検証（第一案FAIL後の代替案） |

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

## fog of war 性能計測: 第一案と第二案（タブ②・③）

fog of war の実装方式を2つ用意し、両方とも同じ指標（計測A: 更新レイテンシ min/median/max/avg、
計測B: フレーム統計）・同じ表示形式（PASS/FAIL判定含む）で比較できるようにしてある。

- **タブ②（第一案・再エンコード方式）**: 穴あきポリゴン1枚のGeoJSONを、ヘクスを開示するたびに
  **まるごと再エンコード**して `setGeoJsonSource` で差し替える。1回の更新がO(n)、全体でO(n²)。
  **実機計測済み・FAIL**（0.26.2: median 310.4ms/max 7,911ms/jank 99.6% / 0.27.0: median 341.3ms/
  max 6,875ms/jank 70.3%。いずれも200ms基準を超過）。
- **タブ③（第二案・feature-state方式）**: 全ヘクスを**最初に1回だけ**ソースとして追加し、
  以後は各ヘクスの `feature-state` をトグルして開示を表現する。更新コストが開示済み数に
  依存しない**O(1)**になることが期待される。0.26.2ではAndroid未実装
  （`UnimplementedError`）で検証不能だったが、0.27.0でAndroid実装が入ったため、
  このハーネスで初めて計測できる。**この方式が本来の狙い**であり、タブ②はその前段階の
  比較対象として残してある。

## タブ②: fog of war 性能計測（第一案・再エンコード方式）

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

## タブ③: fog of war 性能計測（第二案・feature-state方式）

1. ヘクス数（1,000 / 5,000 / 10,000 / 50,000 / 100,000）を選択する。
   **50,000・100,000 は大規模データでの一回コスト計測用に追加した選択肢。**
   端末によってはソース構築に数秒〜数十秒かかったり、メモリ不足で応答なし（ANR）や
   強制終了になる可能性がある（後述「ソース構築コスト計測」参照）。
2. 「ソース準備(初回のみ) + setFeatureStateベンチマーク実行」を押す。
   - 選択したヘクス数ぶんの全ヘクスを1つのFeatureCollectionとして構築し、`addGeoJsonSource`で
     **一度だけ**ソースに追加する。同じヘクス数で再実行する場合はソースを作り直さず、
     `removeFeatureState` で前回の開示状態だけをリセットしてから計測する。
     このソース構築自体の所要時間は、以下の「ソース構築コスト計測」節に記載の内訳計測として
     別途数値化している（計測A・Bには含めない）。
   - 以後は各ヘクスを `setFeatureState(sourceId, featureId, {'revealed': true})` で1つずつ
     「開示」していく。**この setFeatureState 呼び出し1回ぶんの所要時間だけを計測A対象にする**
     （ソース構築やGeoJSON再エンコードは含まない）。この算出方法は今回の追補作業でも変更していない。
   - 計測A・B・PASS/FAIL判定・目標値（更新200ms以内・55fps以上）はタブ②と完全に同じ算出方法・
     表示形式。並べて比較できることを最優先にしてある。
3. ループ完了後、タブ②と同様に「③ 手動パン・ズームfps計測」で代表が地図をパン・ズーム操作する。

### ソース構築コスト計測（Issue #24 追補・最初の1回だけのコスト）

**背景**: 計測A（`setFeatureState` のトグル）はO(1)で非常に速いことが実証済み
（10,000ヘクスで median 0.3ms / max 37.7ms）。しかし「全ヘクスを最初に1回だけソースとして
追加する」ソース構築自体はこれまで「計測対象外の準備作業」としてログに出すだけだった。
実測で `maxFrame=1,077.3ms`（10,000ヘクス）という約1秒の描画フレームが観測されており、
これはソース追加直後の初回描画と推測される。地域パックのヘクス数は10,000を大きく上回る
可能性があるため、「起動時・エリア切替時に何秒待たされるか」を明らかにする目的でこの計測を追加した。

ソース構築を新規に行う場合（＝ヘクス数を切り替えた時、または画面の
「ソースを破棄して再構築（計測やり直し）」ボタンを押した時）、以下の4段階に分解して計測し、
画面の「②' ソース構築コスト計測」欄に**ヘクス数を切り替えながら比較できるよう、
実行するたびに一覧へ積み上げて（消さずに）**表示する。`debugPrint`（`developer.log`）にも出力する。

1. **① ヘクスジオメトリ生成**: Dart側で `generateHexGrid` → `FeatureCollection` の
   Map構造を組み立てるところまでを `Stopwatch` で計測。この間はメインアイソレートが
   占有されるため、UIスレッドは実質フリーズする。
2. **② `addGeoJsonSource` 呼び出し**: `await controller.addGeoJsonSource(...)` の
   完了までを `Stopwatch` で計測。内部で `jsonEncode` とプラットフォームチャネル経由の
   ネイティブ転送（GeoJSON パース・テッセレーション）が走る。この呼び出し1回の
   所要時間がO(n)であっても、ソース構築は1回しか発生しないため許容範囲かどうかを見る。
3. **③ `addLayer` 呼び出し**: `await controller.addLayer(...)` の完了までを同様に計測。
4. **④ 初回描画の観測ウィンドウ**（近似計測。詳細は下記）。ウィンドウ内で観測された
   **最大フレーム時間（maxFrame）**を④の値として使う。
5. **⑤ 合計**: ①+②+③+④（maxFrame）の単純合計。**観測ウィンドウの長さ（2/5/10秒。
   ヘクス数の階層で決め打ちの定数）は合計に含めない**。ウィンドウ長を含めてしまうと、
   合計が実測コストではなくヘクス数の階層境界でジャンプするだけの数値になり、
   スケール特性を読むという本計測の目的を損なうため。

#### ④「初回描画の完了まで」の定義と近似の限界（正直な注記）

`setFeatureState` のO(1)性が実証済みなのに対し、「addGeoJsonSourceの完了 → 実際に地図上に
フォグのポリゴンが描画され切るまで」を**厳密に**検出する手段は用意していない
（MapLibreのレンダリングパイプラインの「このフレームで描画が完全に収束した」という
イベントをFlutter側から取得するAPIがない）。そのため、次の近似で代替した:

- `addGeoJsonSource` を呼ぶ**直前**から `FrameStatsCollector`
  （`SchedulerBinding.instance.addTimingsCallback` ベース。`lib/frame_stats.dart` 参照）で
  フレームタイミングの収集を開始する。
- `addGeoJsonSource` → `addLayer` が完了した後、**固定の観測ウィンドウだけ待機**してから
  収集を停止し、そのウィンドウ内で観測された**最大フレーム時間（maxFrame）**を
  「初回描画コストの近似指標」として採用する。
- 観測ウィンドウの長さはヘクス数に応じて変える（`postSourceBuildSettleWindow`、
  `lib/fog_feature_state_benchmark_page.dart`）:
  - 10,000以下: 2秒
  - 50,000以下: 5秒
  - それ以上（100,000）: 10秒
  - 大きいヘクス数ほど初回描画の「落ち着き」に時間がかかりうるため長くしてあるが、
    これも固定値であり、動的に「もう描画が収束した」ことを検出しているわけではない。
- **これは近似である**: 観測ウィンドウ内に真の初回描画が収まらなければ実際のコストを
  過小評価するし、逆に地図のパン慣性やGCなど無関係な要因で発生したフレームスパイクを
  誤って「初回描画のコスト」として拾ってしまう可能性もある。合否判定に使わず、
  あくまで「大まかにどの程度のフレームスパイクが起きるか」の目安として読むこと。
- ⑤合計に足し込んでいるのは④の**maxFrame値**であり、観測ウィンドウの長さ（2/5/10秒）
  そのものは合計に含めていない（画面・ログには両方とも表示する）。

#### 既存の計測B（更新ループ中のフレーム統計）との比較に関する注意

今回の追補で、ソース構築（新規のとき）の直後に2〜10秒の観測ウィンドウ（＝待機）を
挟むようになった。そのため、以前は「更新ループ（計測A・計測Bのフレーム統計）」の
最初の数フレームに乗っていた**初回描画のスパイク（例: 過去実測の maxFrame=1,077.3ms）は、
今回の変更後は④（ソース構築コスト計測）側に吸収され、計測A実行中のフレーム統計
（`_updateFrameStats`・ボタン②のログに出る「更新ループ中のフレーム統計」）には
乗らなくなる**。したがって、この追補より前に取得した計測Bの数値と、追補後に
新規ソースで取得した計測Bの数値を比較すると、追補後の方が見かけ上改善しているように
見える場合がある。これは計測方法が変わったことによる見かけ上の変化であり、
`setFeatureState`本体の性能（計測A・トグルの所要時間）には影響していない。

#### 大規模ヘクス数（50,000 / 100,000）での失敗時の扱い

ヘクスジオメトリ生成〜ソース構築のどこかで例外（メモリ不足など）が発生した場合はクラッシュさせず、
例外の型とメッセージをそのまま結果一覧に残す方針にしてある
（タブ①⑥・タブ③計測Aの既存の例外処理方針と同じ）。ただし、**Dartレベルで捕捉できない
致命的なOOM（プロセスごとネイティブに強制終了される場合）や、真のANR（UIスレッドが
応答不能になり続ける場合）は原理的に捕捉できない**。その場合はアプリが無応答になったり
プロセスが消えたりすること自体が「このヘクス数は現在の実装では実用に耐えない」という
有効な検証結果になる。無理に動かそうとせず、そのまま代表に報告すること。

### Feature id の付与方式（実装上の注意）

`setFeatureState` は features に id が付いていないと対象を特定できない。maplibre_gl の
ソースコード（`controller.dart` の `setFeatureState` doc comment）によると、`addGeoJsonSource`
の `promoteId` パラメータは**Web専用**で、Androidでは無視される
（"Android has no promoteId, so there the GeoJSON itself must contain a top-level id"）。
そのため `properties.hexId` のような形でIDを持たせる方式は使えず、**各Featureの直下
（`properties`の外）に整数の`id`を持たせる必要がある**。本ハーネスではヘクス配列のインデックス
（0起点の連番）をそのままFeature直下の`id`にしている。`setFeatureState`の`featureId`引数は
`String`型なので、呼び出し時に`.toString()`で変換して渡す。

### 例外処理

`setFeatureState`が例外を投げた場合（版数を安定版0.26.2に戻したときの`UnimplementedError`等）は、
タブ①⑥のfeature-stateプローブと同じ方針で、クラッシュさせずに例外の型とメッセージをそのまま
ログ・画面に表示する。ループ途中で例外が出た場合は、そこまでに計測できた分だけで
min/median/max/avgを計算し、部分結果として表示する（全滅として握りつぶさない）。

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
- `maplibre_gl`: 現在の既定は git依存 `release-0.27.0`（`pubspec.yaml`参照。pub.dev安定版
  `^0.26.2`はコメントアウトで併記。切り替え方法は下記「バージョン切り替え」参照）
- Android minSdk はFlutterのデフォルト値をそのまま使用（`maplibre_gl` の要求 minSdk 21 を上回る）
- ビルド時にAndroid SDK Platform 35が自動インストールされる（`maplibre_gl` の要求）。
  `docs/dev-setup.md` §2 記載の環境にはPlatform 36のみが入っていたため、初回ビルド時に追加された。

## コンパイル・起動確認（feature-state方式追加時点）

- `flutter analyze`: 実施済み・問題なし
- `flutter build apk --debug`: 実施済み・ビルド成功
  （既知の`maplibre_gl`のKGP警告は出るが、ビルド自体は成功する。無関係な既存の警告）
- `adb install -r` でPixel 7a（`3B101JEHN11229`）にインストール済み
- `adb shell am start` で起動し、`adb logcat` でFATAL EXCEPTION/AndroidRuntimeのクラッシュが
  ないこと、プロセスが起動後も生存し続けていることを確認済み
- **ベンチマークボタンの実行・数値の読み取りは代表が行う**（本ハーネスの方針どおり、
  自動化していない）。

## コンパイル・起動確認（ソース構築コスト計測追加時点）

- `flutter analyze`: 実施済み・問題なし
- `flutter build apk --debug`: 実施済み・ビルド成功（既知のKGP警告のみ、無関係な既存の警告）
- `adb install -r` でPixel 7a（`3B101JEHN11229`）にインストール済み
- `adb shell am force-stop` → `adb shell am start` で起動し、`adb logcat -d` で
  FATAL EXCEPTION/AndroidRuntimeのクラッシュがないこと、プロセスが起動後も生存し
  続けていることを確認済み
- **50,000・100,000ヘクスでの実際のベンチマーク実行・数値の読み取りは代表が行う**
  （本ハーネスの方針どおり自動化していない。実行時間が長くなる・端末が無応答になる
  可能性があるため特に注意）。
