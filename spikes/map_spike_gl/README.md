# map_spike_gl — Issue #24 検証ハーネス（`maplibre_gl` 用）

**これは使い捨ての検証ハーネスであり、製品コードではありません。**

- terra-town 本体（`app/` `packages/core/` `packages/location/`）とは一切関係がなく、依存もしていません。
- `DESIGN.md` のデザイントークンには準拠していません（色・サイズを直書きしています）。これは代表が実機で
  ボタンを押して数値を読み取るための検証専用UIであり、製品UIではないためです。
- 目的は [Issue #24](https://github.com/rokusoudo-product/terra-town/issues/24) の受け入れ基準を満たすための
  **実機計測を代表が行うための道具**を用意することです。このハーネス自体は Issue #24 を完了させません。
  実機での計測・`specs/001-mvp/research.md` への転記は代表が行います。

## これは何を検証するか

`specs/001-mvp/research.md`（現行は main。git履歴上はPR #41の机上調査ドラフトから始まり、
その後 §6 に実機検証結果が追記された）のうち、まだ判定できていない項目に対応する画面を提供します。
**Issue #24 は既にほぼ完了しており（§6.1 プラグイン選定・§6.3 addSource/feature-state・
§6.4 fog of war性能はいずれも実機計測済み）、残っているのは次の3件だけです。**

| このアプリのUI | research.md の項目 | 状態 |
|---|---|---|
| 上部バナー: プラグイン名・版数 | §6.0〜§6.1 の前提記録 | 実機計測済み（参考表示のみ） |
| タブ①「② 基本地図表示」 | §6.1 の基本動作確認 | 実機計測済み（参考） |
| タブ①「③ ローカルMBTiles読込（ベクタソース・url/tiles方式）」 | **§6.2 T012** | **未判定（本ハーネスの主目的）** |
| タブ①「④ PMTiles読込」 | §6.2 のフォールバック候補 | 未実施（参考） |
| タブ①「⑤ addSource/addLayer 疎通」 | §6.3 T013/R1 | 実機計測済み（参考） |
| タブ①「⑥ feature-state プローブ」 | §6.3 T013/R1 | 実機計測済み（参考） |
| タブ①「⑦ feature_id（H3由来の大きい整数）疎通確認」 | **§8.4** | **未判定（本ハーネスの主目的）** |
| タブ②「fog of war 性能(第一案:再エンコード)」 | §6.4 T014/R2 | 実機計測済み・FAIL（参考。比較対象として残置） |
| タブ③「fog of war 性能(第二案:feature-state)」②・②' | §6.4 T014/R2 | 実機計測済み・PASS（参考） |
| タブ③「③ 手動パン・ズームfps計測」 | **§6.4「残る未計測事項」** | **未判定（本ハーネスの主目的）** |
| タブ③「④ スタイル再読み込み時のちらつき確認」 | **§6.4 チェックリストの「スタイル再読み込み時のちらつきの有無」** | **未判定（本ハーネスの主目的）** |

**今回の実機セッションで判定してほしいのは太字の4項目**（MBTiles url/tiles・feature_id・
パン/ズームfps・スタイル再読み込みちらつき）です。他の項目は既に判定済みで、ボタン自体は
比較のため・または回帰確認のために残してあります。

## 代表向けの実行手順

### 0. JDK / Gradle の実行環境を確認する（必ず最初に。`java -version` だけでは不十分）

```bash
java -version           # 21 であること（ただしこれだけでは不十分。下記参照）
echo "$JAVA_HOME"       # ここが sdkman の 17 を指していないか確認する
```

**理由**: `maplibre_gl` 0.27.0 は JDK 21 を無条件で要求する（research.md §6.1）。

**⚠️ `java -version` が21を返しても、Gradleビルドは17で動いて落ちることがある
（2026-09-09の実機セッションで実際に発生）。** 原因は次の通り:

- 対話シェル（`flutter run` を打つ手元のシェル）では sdkman の初期化行が実行され、
  `JAVA_HOME=/home/zakis/.sdkman/candidates/java/current`（JDK **17**.0.11-tem）が
  設定される。
- ここで `PATH` から sdkman のパスだけを取り除いても（例:
  `PATH=$(echo "$PATH" | tr ':' '\n' | grep -v sdkman | paste -sd:)`）、
  **`java -version` は `update-alternatives` 経由でシステムJDK 21 を返すようになるが、
  `JAVA_HOME` はsdkmanの17を指したまま残る**。
- Gradle は `java` コマンドの解決結果より **`JAVA_HOME` を優先する**ため、
  「`java -version` は21なのにGradleは17でビルドしようとして
  `invalid source release: 21` で落ちる」という、一見矛盾した状態になる。
- さらに、sdkmanには JDK 21 がインストールされていない
  （`~/.sdkman/candidates/java/` は `17.0.11-tem` のみ）ため、
  `sdk use java 21...` のような切り替えはそもそも使えない。

**したがって確認すべきは `java -version` ではなく `JAVA_HOME` の中身であり、
対処は「`JAVA_HOME` をシステムJDK 21のパスへ明示的に上書きする」ことである。**
実際に成功したコマンド:

```bash
cd ~/terra-town/spikes/map_spike_gl && \
  JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64 \
  PATH=$(echo "$PATH" | tr ':' '\n' | grep -v sdkman | paste -sd:) \
  /home/zakis/flutter/bin/flutter run
```

（`flutter build apk --debug` でも同様に `JAVA_HOME`/`PATH` を指定する。）

**すでに17でビルドを一度試みてGradleデーモンが起動してしまっている場合**、そのデーモンは
JDK17のまま常駐し続け（`org.gradle.jvmargs=-Xmx8G` の設定もあり重い）、上記のように
環境変数を直しただけでは効かないことがある。その場合は一度デーモンを止めてから
やり直すこと:

```bash
cd ~/terra-town/spikes/map_spike_gl && ./android/gradlew --stop
```

### 1. フィクスチャを取得する

```bash
cd ~/terra-town/spikes/fixtures
bash fetch_fixtures.sh
```

`sample.mbtiles`（約5MB）が `spikes/map_spike_gl/assets/` にもコピーされる。
**これを実行せずに `flutter run`/`flutter build apk` するとアセットが見つからずビルド自体が
失敗する**（`pubspec.yaml` の `assets:` にこのファイルを登録済みのため）。

### 2. 実機をWSLに接続する

USB接続でWSLから直接使う場合（推奨・本ハーネスの手順として指定されたもの）:

1. 端末をUSBでWindows PCに接続し、開発者オプション > USBデバッグ を ON にする
2. Windows PowerShell で `usbipd list` を実行し、端末の busid（例: `2-4`）を確認する
3. `usbipd attach --wsl --busid <busid>` を実行する（管理者権限が必要な場合あり）
4. **WSLにアタッチしている間はWindows側のadbからは端末が見えなくなる。これは正常な挙動。**
   （usbipd はUSBデバイスをWindowsホストからWSL側へ「移譲」する方式のため、両側から同時には見えない）
5. WSL側で `/home/zakis/flutter/bin/flutter devices` を実行し、端末が一覧に出ることを確認する

`docs/dev-setup.md` §5 に記載のワイヤレスデバッグ（`adb pair` / `adb connect`）でも代替可能です。

### 3. アプリを実行する

```bash
cd ~/terra-town/spikes/map_spike_gl
/home/zakis/flutter/bin/flutter run
```

`flutter devices` に複数出る場合は `-d <deviceId>` を付ける。

### 4. 各タブのボタンを順に押し、画面の数値をスクリーンショット、または手で
   `specs/001-mvp/research.md` の該当欄に転記する。**優先して判定してほしいのは
   タブ①③⑦とタブ③③④の4項目**（上の表の太字）。

## タブ①: 地図/MBTiles/feature-state/feature_id

1. **② 基本地図表示**: デフォルトで MapLibre 公式デモスタイル
   （`https://demotiles.maplibre.org/style.json`）が表示される。別スタイルを試したい場合は
   URL欄に入力して「スタイル適用」を押す。
2. **③ ローカルMBTiles読込（ベクタソース）【最優先・§6.2 T012】**:
   1. まず「① 同梱フィクスチャをコピーして使う（推奨）」を押す。アプリ内蔵のアセット
      （`fetch_fixtures.sh` が取得した `sample.mbtiles`）をアプリのキャッシュディレクトリへ
      コピーし、パス欄に自動入力される。**`adb push` は不要**（Android 13+ でSAF外の任意パスが
      読めず、権限エラーとMapLibreの失敗が区別できなくなるため廃止した。詳細は
      `spikes/fixtures/README.md`）。
   2. 「② VectorSourceProperties(url:)で読込」を押す。**注意: 既定のデモスタイル
      （`MapLibreStyles.demo`）自体が、このフィクスチャと同じ Natural Earth の国境データを
      既に描画している。** そのため「国境線が見える」ことはPASSの根拠にならない
      （デモスタイルが元から表示しているだけの可能性がある）。**PASSの判定基準は
      色**: このボタンは国境ポリゴンを**薄い青**（`#3388ff`）、経緯線を**赤**（`#ff0000`）で
      塗るので、地図が自動でズーム2まで引いた後に**青い着色と赤い線が乗って見えるか**で
      判定すること。ログに「addSource/addLayer(fill+line)成功」と出ていても、
      **青・赤が乗って見えなければFAILと判定すること**（`research.md`§6.2の教訓＝
      例外が出ないことと描画されることは別）。
   3. 続けて「③ VectorSourceProperties(tiles:)で読込」も押す（別のsource/layer IDを使うため
      ②を押した後でも独立して試せる。2回目以降に同じボタンを押しても「source already
      exists」エラーにならないよう、内部で毎回いったん削除してから追加し直している）。
      同じ基準（青い着色・赤い線が乗るか）でPASS/FAILを判定する。
   4. **両方試すこと。** `url`と`tiles`のどちらが正しいかは一次情報で確定できなかったため、
      1回のセッションで両方の結果を`research.md`§6.2に転記してほしい（両方PASS・片方のみ
      PASS・両方FAILのいずれもあり得る有効な結果）。
   5. **⚠️ 比較する際は必ず間にリセットを挟むこと。** ②と③は同じ色（青い塗り・赤い線）で
      描画するため、②を試した後にリセットせず③を重ねて追加すると、画面に見えている
      青・赤が②（url方式）と③（tiles配列方式）のどちらの寄与かを区別できなくなる。
      **2026-09-09の実機セッションではこれをせずに重ねてしまい、③を押す前
      （②のみの状態）で撮られたスクリーンショットで描画が確認できていたことから
      「url方式単独で成立している」と読めるものの、これは厳密な分離検証ではなく
      強い傍証にとどまる**（詳細はresearch.md §6.2）。同じ轍を踏まないよう、
      ②→**「リセット（②③を両方削除）」ボタンを押す**→③、の順で1つずつ試すこと。
   6. 参考: research.md §6.4は基盤地図タイル（`demotiles.maplibre.org`）がHTTP 429
      （レート制限）で読めないことがあったと記録している。デモスタイルの背景が
      真っ白/簡素に見えても異常ではない。
3. **④ PMTiles読込**: 公式サンプル（`pmtiles_style.json`）と同じ「スタイルJSON内のsource.urlに
   `pmtiles://...` を書く」方式。ローカルファイルパスでの構文は公式サンプル（リモートURL）からの
   類推であり、未検証。こちらもパスはテキスト入力のみ（優先度は低い。フォールバック候補の参考）。
4. **⑤ addSource/addLayer 疎通**: 3ヘクス分の合成GeoJSONを動的に追加し、赤いポリゴンとして
   描画されるか確認（実機計測済み・参考）。
5. **⑥ feature-state プローブ**: `setFeatureState` を呼び出す（実機計測済み・参考。
   0.27.0では例外なく成功する見込み）。
6. **⑦ feature_id（H3由来の大きい整数）疎通確認【最優先・§8.4】**: 「大きいfeature_idで
   setFeatureStateを試す」を押す。`id=833108588584959`（`tools/pack-builder/
   verify_feature_id.py` の実測最大値・research.md §8.4）を持つFeatureを追加し、
   `setFeatureState`→`getFeatureState`の順に呼ぶ。**PASSの判定基準はログ**:
   「setFeatureState 成功」「getFeatureStateで読み戻し成功 -> {probed: true}」の両方が
   出ていればPASS。`getFeatureState`の結果が`{probed: true}`と一致しない場合は、idが途中で
   丸められた可能性があるため要確認として報告すること。地図上には確認用として緑色の
   小さな四角（東京近辺、自動でズーム13へ移動する）も表示されるが、これはあくまで
   ログの結果を裏取りするための補助であり、四角が見えること自体はPASS/FAILの主基準ではない
   （③のMBTiles確認を先に試した場合、カメラがズーム2にあった状態から自動で東京近辺へ
   戻る）。

## fog of war 性能計測（タブ②・③）は実機計測済み（参考）

**タブ②・③の①〜②'（ヘクス数選択・ベンチマーク実行・ソース構築コスト計測）は
2026-08-13〜14に実機計測済みで、research.md §6.4に結果が反映されている
（第二案=feature-state方式のPASSを確認済み。1ソースあたりのヘクス数上限もplan.md §3に
明記済み）。今回のセッションで優先して判定してほしいのは、タブ③に新設した
③手動パン・ズームfps計測と④スタイル再読み込み時のちらつき確認の2項目のみ**（後述）。
以下は既存の計測方法の説明（変更していない）。

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
- **【2026-09-09 修正】手動パン・ズームfps計測の判定指標を修正した**（詳細は
  `lib/frame_stats.dart` 冒頭コメント参照）。従来は fps を「収集期間中の観測フレーム数 ÷
  収集期間の実時間」の単純平均（`naiveFps`）だけで出しており、これは「開始」→「停止」の
  間に代表が指を止めた時間（＝フレームが1枚も生成されない区間）まで分母に含んでしまう。
  そのため 2026-09-09 の実機セッションでは、実際は avgFrame 11.5ms（≒87fps相当）で
  動いていたにもかかわらず `naiveFps` が32.5にしかならず、「性能が悪い」のか
  「単に操作していない時間が長かっただけ」なのか区別できないという不具合があった。
  現在は、フレームの発生間隔が200ms（`activeGapThresholdMs`）を超えた区間を
  「無操作（アイドル）」とみなして除外し、連続して描画が起きていた区間だけを母数にした
  `activeFps` を追加した。**画面・ログとも `activeFps` が判定用（55fps基準の対象）、
  `naiveFps` は参考値（無操作区間を含む）と明示している。** 55fps基準の達成/未達は
  この `activeFps` を見れば代表が画面を見ただけで分かるようにしてある
  （Cardの色・PASS/FAILラベルは `activeFps` 基準で表示）。
- 計測Aは `Stopwatch` で `await controller.setGeoJsonSource(...)` の完了までの時間を計測している。
  これは「Dartのawaitが返るまでの時間」であり、プラットフォームチャネルの往復・ネイティブ側の
  再テッセレーション・再描画のどこまでを含むかの内訳は分解できていない（Issue #366 の指摘する
  `jsonEncode` のメインアイソレート占有時間は、この所要時間に含まれるはず）。

## タブ③: fog of war 性能計測（第二案・feature-state方式）

**⚠️ 既知の見た目の問題（壊れているわけではない）**: 合成ヘクス（10,000ヘクス等）を
ベンチマーク実行すると、そのヘクス群が**画面全体を覆ってしまい、下の基盤地図
（`demotiles.maplibre.org` のデモスタイル）が見えなくなる**。2026-09-09の実機セッションで
代表から「地図が表示されていない」という報告があったが、これはハーネスの不具合ではなく、
合成ヘクスグリッドが原点付近を広く覆う形で生成される仕様上の見た目である。
`research.md` §6.4「基盤地図を重ねての再計測」に記載の既知の残課題（基盤地図を重ねた状態での
再計測は未実施）と同じ事象なので、地図が消えても壊れたと判断しないこと。

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
3. ループ完了後、タブ②と同様に「③ 手動パン・ズームfps計測」で代表が地図をパン・ズーム操作する
   **【最優先・§6.4「残る未計測事項」】**。ヘクス数**10,000**を選択した状態で実行すること
   （plan.md §8の基準「1万ヘクス開示状態で55fps以上」を厳密に検証するため）。「開始」を押し、
   数秒間パン・ズームしてから「停止」。PASS/FAIL判定は画面に自動で出る。
4. さらに続けて「④ スタイル再読み込み時のちらつき確認」も実行する **【最優先】**。
   「スタイル再読み込みを試す」を押し、`controller.setStyle` でスタイル全体を差し替えたときに
   フォグが一時的に消える様子を目視で確認する。数値（`onStyleLoadedCallback`までの経過時間・
   フォグ再構築完了までの合計時間・観測ウィンドウ中のフレーム統計）は自動計測されるが、
   **「ちらついたか・どのくらいの時間見えなかったか」という主観的な見た目の判定は代表が行うこと**
   （PASS/FAIL基準はresearch.mdに定義がないため、本ハーネスは数値のみ表示しPASS/FAIL判定はしない）。
   再構築後は開示状態がリセットされ全面フォグに戻る（既知の制約。ちらつきの有無の判定には影響しない）。

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

## バージョン

**【2026-09-09 変更】バージョン切り替え（pub.dev安定版⇔git依存）の手順は廃止した。**
`maplibre_gl` 0.27.0 は 2026-08-19 に pub.dev へ正式公開され、main の
`packages/location/pubspec.yaml` も pub.dev版 `^0.27.0` を採用済み（Issue #55）。
本ハーネスもそれに揃え、git依存（`ref: release-0.27.0`）と `dependency_overrides` を撤去した。
feature-state の Android対応（上流#889）・Issue #366のエンコードオフロードはいずれも
0.27.0に収録済み（research.md §6.0）。バージョンを変える場合は `pubspec.yaml` と
`lib/plugin_info.dart` の `kPluginVersionLabel` を両方書き換えること。

## MBTiles / PMTiles フィクスチャ

地域パック（`tools/pack-builder/`）は未実装のため、terra-town独自の実データはまだありません。
かわりに、`spikes/fixtures/fetch_fixtures.sh` で MapLibre 公式配布の軽量サンプル
（世界地図・国境ポリゴン、z0-6、MBTiles約5MB・PMTiles約3.8MB、Natural Earth Data＝パブリックドメイン）
を取得できます。詳細は `spikes/fixtures/README.md` を参照。バイナリはコミットしません。

```bash
cd ~/terra-town/spikes/fixtures
bash fetch_fixtures.sh
```

`sample.mbtiles` は `map_spike_gl/assets/` へも自動でコピーされ、アプリのタブ①
「① 同梱フィクスチャをコピーして使う」ボタンから直接使える（**`adb push` は不要**。
Android 13+ でSAF外の任意パスが読めず権限エラーとMapLibreの失敗が区別できなくなるため
2026-09-09に廃止した）。MBTiles/PMTilesパスの手入力欄も残してあるので、
代表が別途用意したファイル（例: [MapTiler](https://www.maptiler.com/) や
[Protomaps](https://protomaps.com/) のサンプル、`pmtiles convert` で自作したもの）を
試したい場合はそちらを使うこと。

fog of war 性能計測（タブ②③）はMBTilesなしで実行できます（合成GeoJSONのみで完結）。

## 既知の制約

- **ネイティブのファイル選択ダイアログは未実装**。当初 `file_picker` パッケージで実装する予定だったが、
  `file_picker: ^11.0.3` が独自に適用するKotlin Gradle Plugin（KGP）と `maplibre_gl` のそれが
  衝突し、`flutter build apk --debug` が
  `GeneratedPluginRegistrant.java: cannot find symbol FilePickerPlugin` で失敗した
  （`flutter build apk` の出力にも「Future versions of Flutter will fail to build if your app uses
  plugins that apply KGP」という警告が出ている。file_picker と maplibre_gl の両方がこれに該当）。
  無理に動かそうとせず、`file_picker` への依存自体を外し、MBTiles/PMTilesのパスは
  テキスト入力のみで指定する方式に変更した。既定の導線はアセット同梱（タブ①の
  「同梱フィクスチャをコピー」ボタン）であり、手入力欄は補助的な用途。
- **スタイル再読み込み確認（タブ③④）は開示状態を復元しない**。`controller.setStyle` で
  スタイル全体が差し替わった後、フォグのソース/レイヤーは作り直すが、どのヘクスが
  開示済みだったかは保持していないため、再構築後は全面フォグに戻る。ちらつきの有無・
  再表示までの時間の観測には影響しない設計上の割り切り。

## 環境

- Flutter 3.44.8 / Dart 3.12.2（`docs/dev-setup.md` §2 準拠）
- `maplibre_gl`: `^0.27.0`（pub.dev正式版。`pubspec.yaml`参照。上記「バージョン」節参照）
- Android minSdk はFlutterのデフォルト値をそのまま使用（`maplibre_gl` の要求 minSdk 21 を上回る）
- ビルド時にAndroid SDK Platform 35が自動インストールされる（`maplibre_gl` の要求）。
  `docs/dev-setup.md` §2 記載の環境にはPlatform 36のみが入っていたため、初回ビルド時に追加された。
- **JDK 21が必須**（`maplibre_gl` 0.27.0の要求。「代表向けの実行手順」ステップ0参照）。

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

## コンパイル確認（2026-09-09・MBTilesベクタ対応・feature_id疎通・アセット同梱化）

**実機を保有していないため、以下はWSL上での静的検証（analyze・ビルド）のみ。
実機での動作・描画確認は行っていない（代表が行う）。**

- 実施内容: pubspec.yamlをgit依存(release-0.27.0)からpub.dev版`^0.27.0`へ変更・
  dependency_overrides撤去、android.builtInKotlin=trueの経緯コメント更新、
  MBTiles読込のRasterSourceProperties→VectorSourceProperties(url/tiles両対応)化、
  fill+lineレイヤ追加（source-layer名`countries`/`geolines`は実測・後述）、
  adb push方式を廃止しアセット同梱（`assets/sample.mbtiles`）+ アプリ内コピー方式に変更、
  feature_id（H3由来の大きい整数）疎通確認ボタンの追加、
  スタイル再読み込み時のちらつき確認ボタンの追加。
- `bash -lc "java -version"`: `21.0.12`であることを確認（非対話シェル。CIと同条件）。
- `flutter pub get`: 成功（maplibre_gl/maplibre_gl_platform_interface/maplibre_gl_web が
  gitからpub.dev 0.27.0へ切り替わったことを確認）。
- `flutter analyze`: 実施済み・問題なし。
- `flutter build apk --debug`: 実施済み・ビルド成功（既知のKGP警告のみ、無関係な既存の警告）。
  **`spikes/fixtures/fetch_fixtures.sh` を先に実行してアセットを配置しないとビルド自体が
  失敗する**（`pubspec.yaml`の`assets:`参照。この動作自体は意図どおり＝フィクスチャ未取得の
  まま気づかず実機に持ち込む事故を防ぐ）。
- source-layer名（`countries`=ポリゴン、`geolines`=線、`centroids`=点）は
  `spikes/fixtures/sample.mbtiles`のmetadataテーブルを実際に読んで確定した（推測ではない）。
  確認コマンド:
  ```bash
  cd spikes/fixtures && python3 -c \
    "import sqlite3; c=sqlite3.connect('sample.mbtiles'); \
     print(c.execute(\"select value from metadata where name='json'\").fetchone()[0])"
  ```
- **実機での動作確認（描画されるか・feature_idが正しく往復するか・fps・ちらつきの見た目）は
  一切行っていない。** これは実機を保有しないためであり、判定不能ではなく「未実施」。
  代表の実機セッションでの判定が必要。

## コンパイル確認（2026-09-09・実機セッション後のハーネス修正）

**2026-09-09の代表による実機セッション（Pixel 7a）で判明した2つの不具合を修正した
（`specs/001-mvp/research.md` §6.2・§6.4に実測結果あり。以下は今回の修正内容）。
実機を保有していないため、以下もWSL上での静的検証（analyze・ビルド）のみ。**

- **修正1: 手動パン・ズームfps計測の判定指標。** 従来の fps（`naiveFps`。
  「収集フレーム数 ÷ 収集期間の実時間」の単純平均）は、代表が指を止めていた時間まで
  分母に含んでしまい、「性能が悪い」のか「単に操作していなかった」のかを区別できない
  不具合があった（実測: naiveFps=32.5だがavgFrame=11.5ms≒87fps相当、jank率7.1%と
  矛盾する数値だった）。`lib/frame_stats.dart` の `FrameStatsCollector` を変更し、
  フレーム発生間隔（`FramePhase.vsyncStart`のタイムスタンプ差）が200ms
  （`activeGapThresholdMs`）を超える区間を「無操作」として除外した `activeFps` を
  追加。判定（55fps基準・Cardの色・PASS/FAIL表示）は `activeFps` を使うよう
  `lib/fog_benchmark_page.dart`・`lib/fog_feature_state_benchmark_page.dart` を
  修正し、`naiveFps` は参考値として画面・ログに残しつつラベルで明確に区別した。
- **修正2: MBTiles url/tiles比較のリセット手段。** 2026-09-09のセッションでは
  url方式を試した後にリセットせずtiles配列方式を重ねて追加したため、描画がどちらの
  方式単独の寄与か厳密に分離できないという精度の限界が生じた。`map_probe_page.dart`
  に「リセット（②③を両方削除）」ボタンを追加し（`_resetMbtilesVectorSources`）、
  README「タブ①」節にも比較時は必ずリセットを挟むよう追記した。
- **修正3: README ステップ0（JDK確認手順）の不備。** `java -version` だけでは
  「sdkmanがJAVA_HOME経由でJDK17を固定し、Gradleがそちらを優先してビルドが落ちる」
  事象を検出できないことが実機セッションで判明した。ステップ0を「`JAVA_HOME`の中身を
  確認し、システムJDK21のパスへ明示的に上書きする」手順に書き換え、Gradleデーモンの
  停止手順（`./android/gradlew --stop`）も追記した（詳細は本README冒頭「代表向けの
  実行手順」参照）。
- **修正4: タブ③で基盤地図が隠れる件の注記。** 合成ヘクスが画面全体を覆うため
  基盤地図が見えなくなる既知の事象を、壊れていると誤解されないようタブ③冒頭に明記した
  （`research.md` §6.4「基盤地図を重ねての再計測」と同じ既知の残課題）。
- `flutter analyze`: 実施済み・問題なし。
- `flutter build apk --debug`: 実施済み・ビルド成功（既知のKGP警告のみ、無関係な既存の警告）。
- **実機での動作確認（`activeFps`が実際に代表の体感と一致するか・リセットボタンの動作）は
  行っていない。** 次回の実機セッションでの確認が必要。
