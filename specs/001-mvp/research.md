---
type: spec
project: terra-town
doc: research.md（Flutter 地図プラグイン選定スパイク・机上調査）
feature: 001-mvp
status: review               # 机上調査＋R2実機計測が完了。R1（MBTiles読込）は未検証
created: 2026-08-11
updated: 2026-08-13
related:
  - specs/001-mvp/plan.md
  - specs/001-mvp/tasks.md
  - docs/dev-setup.md
  - docs/terrain.md
  - https://github.com/rokusoudo-product/terra-town/issues/24
---

# terra-town — Flutter 地図プラグイン選定スパイク（Issue #24・R1・R2）研究ノート

> **本ドキュメントの現在の状態（2026-08-13 更新）: 机上調査に加え、R2（fog of war 性能）の実機計測が完了。R1（ローカルMBTiles読込）は未検証。**
>
> - **R2 の結論**: plan.md §8 の**第二案（feature-state によるヘクス単位の開示トグル）が合格**。第一案（GeoJSON 全体の再エンコード）は不合格。詳細と数値は §6.4。ただし第一案の計測には但し書きがある（§6.4 の⚠️を必ず読むこと）
> - **§3.2・§4 に誤りがあった**。0.27.0 の修正は `main` ではなく `release-0.27.0` ブランチにある。訂正は §6.0
> - 以下の §1〜§5 は 2026-08-11 時点の**机上調査のまま**であり、上記の実測結果で更新していない箇所がある。実測との齟齬がある場合は §6 を正とする
>
> （以下、机上調査時点の記述）
> 本書はローカルMBTiles読込・fog of war 性能計測について、代表が実機で確認する前の下調べとして、Web上の一次情報（pub.dev・GitHub リポジトリ・Issue/PR）を調査した結果をまとめたものである。**実機で計測した数値は一切含まない。** 推測・断定は行わず、根拠が見つからなかった項目は「見つからなかった」と明記する。
>
> 本書は plan.md・tasks.md を書き換える確定文書ではない。Issue #24 の受け入れ基準のうち「プラグイン候補比較（採用・却下の理由と検証したバージョン）」のみを暫定的に満たすためのドラフトであり、残りの受け入れ基準（実機MBTiles読込の成否、fog of war 性能の数値、plan.md §16 の確定）は代表の実機検証後に別途更新する。

## 0. 調査日・調査方法

- **調査日**: 2026-08-11
- **調査方法**: Web調査のみ（pub.dev・GitHub リポジトリ本体・GitHub Issue/PR/Release を `gh api` / `gh issue view` / `gh release list` / `gh search code` で直接確認、および `WebFetch`/`WebSearch`）。実機・エミュレータでの動作確認は一切行っていない。
- **前提環境**（`docs/dev-setup.md` §2 実測値・2026-07-30時点）: Flutter **3.44.8**（stable）／Dart **3.12.2**／Android SDK Platform android-36／Android SDK Build-Tools 37.0.0。

---

## 1. プラグイン候補比較

plan.md §1 が最大の実装リスクとして挙げた2系統を比較した。MapLibre GL Native の採用自体は closed #18 で確定済みのため、本調査は「Flutter からこの SDK を叩くプラグイン」の比較に限定する（`flutter_map` など別レンダリングエンジン系は #18 の決定と競合するため対象外とした）。

| 項目 | `maplibre_gl`（`maplibre/flutter-maplibre-gl`） | `maplibre`（`josxha/flutter-maplibre`） |
|---|---|---|
| 位置づけ | `flutter-mapbox-gl` からの fork。旧来のメソッドチャネル方式 | ゼロから書き直された新パッケージ。JNI（`jnigen`）ベースのネイティブ相互運用 |
| 最新バージョン（pub.dev） | **0.26.2** | **0.3.5** |
| 最終リリース日 | 2026-06-19 [^gl-release] | 2026-04-11 [^new-release] |
| リポジトリ最終push | 2026-08-10（活発） [^gl-repo] | 2026-08-09（活発） [^new-repo] |
| GitHub Stars / Open Issues | 356 / 84 [^gl-repo] | 150 / 30 [^new-repo] |
| pub.dev Likes / Pub Points | 117 / 160（満点） [^gl-pubdev] | 67 / 160（満点） [^new-pubdev] |
| 週間ダウンロード数 | 約71,000 [^gl-pubdev] | 記載未確認（見つからなかった） |
| Publisher | `maplibre.org`（verified） [^gl-pubdev] | `joscha-eckert.de`（verified） [^new-pubdev] |
| Dart SDK 制約 | `>=3.7.0 <4.0.0` [^gl-pubspec] | `^3.12.0`（`>=3.12.0 <4.0.0`） [^new-pubspec] |
| Flutter SDK 制約 | `>=3.29.0` [^gl-pubspec] | `>=3.44.0` [^new-pubspec] |
| 本リポジトリ実測環境との整合 | 適合（Dart 3.12.2 / Flutter 3.44.8 とも余裕あり） | **適合するが際どい**（Dart 制約下限 3.12.0 に対し実測 3.12.2＝パッチ2つ分の余裕しかない） |
| 対応プラットフォーム | Android / iOS / Web（Windows/Linux/macOS 非対応） [^gl-pubdev] | Android / iOS / Web / Windows / macOS（**Linux 非対応**） [^new-features] |
| Android 対応 | フル対応（スタイル・カメラ・ジェスチャ・自己位置・各種レイヤー） [^gl-pubdev] | フル対応。機能マトリクスで主要機能はほぼ全て Android ✅ [^new-features] |
| minSdkVersion | 21 [^gl-minsdk] | 21 [^new-minsdk] |
| API 設計思想 | 命令的（`MapLibreMapController` への逐次呼び出し） | 宣言的（Flutter の `setState`/Widget ツリーに近い設計。`MapController`/`StyleController` も併用可） [^new-migrate] |
| ローカル MBTiles 対応（`mbtiles://`） | 非公式・未文書化（コミュニティ検証あり、詳細は§2.1） [^gl-318] | 公式機能マトリクス上は Android/iOS ✅ だが参照構文の一次情報未発見（詳細は§2.2） [^new-features] |
| 動的 `addSource`/`addLayer` | ○（公式API・命令的） | ○（公式API・`StyleController`経由） [^new-sources-layers] |
| `feature-state`（Android） | **✕（0.26.2時点）**／0.27.0で対応済みだが**未リリース**（詳細は§3.2） [^gl-featurestate-code] [^gl-889] | 根拠見つからず（詳細は§3.2） [^new-featurestate-search] |

**採用・却下の暫定判断（机上時点）**: どちらも Android で実用に耐えるだけの機能を備えており、机上調査だけでは決定打を欠く。ただし `maplibre_gl` は「安定運用中の枯れた実装＋圧倒的に大きい採用実績（71k weekly downloads）」、`maplibre` は「宣言的APIでFlutterらしい書き味＋MBTilesが機能マトリクス上明記されている」という異なる強みを持つ。§5 に暫定推奨をまとめる。

---

## 2. ローカル MBTiles 読込（`mbtiles://`）のサポート状況

### 2.1 `maplibre_gl`

- 公式ドキュメントには **MBTiles 専用ページが存在しない**。`website/docs/advanced/` 配下にあるのは `pmtiles.md` のみで、PMTiles が第一級（公式ドキュメント化された）機能として案内されている。同ドキュメントは「MBTiles を PMTiles に変換して使う」ことを推奨している（`pmtiles convert input.mbtiles output.pmtiles`）[^gl-pmtiles-doc]。
- 一方で、コミュニティの実地検証は存在する。Issue #318「How to load an mbtiles file」（2023-10 open、直近コメント2023-11、**未クローズ**）で、`mbtiles://` スキームは **maplibre-native 自体には実装されている**ことが示唆され、実際に動作報告が複数ある [^gl-318]:
  - `RasterSourceProperties(tiles: ['mbtiles:///<絶対パス>/map.mbtiles'])` を `addSource` に渡す方式で動作（ラスタ・ベクタタイル双方の報告あり）。
  - **Flutter の asset バンドルから直接は読めない**。`assets/` 同梱ファイルはアプリの署名パッケージ内に封じ込まれており、ネイティブSQLiteが直接開けない。`rootBundle.load()` で読み出し、`getApplicationCacheDirectory()`（や `getExternalStorageDirectory()`）配下の**書き込み可能なファイルシステムパスにコピーしてから** `mbtiles://` で参照する、という2段階の実装が必要（同Issueの `venomwine` 氏のコードで確認）。
  - 既知の不具合報告（`timautin` 氏）: ズームイン時とズームアウト時でタイルの表示/非表示が切り替わる閾値がずれる、80MB程度の大きめのmbtilesでは min/max zoom を明示しないと一部タイルが表示されないことがある。
  - この経路は**公式サポートではなくコミュニティが発見した挙動**であり、READMEには「アセット参照方法のドキュメント化」を目的とした PR #346（2023-12 マージ済）はあるが、これは主にPMTiles/一般的なアセット参照に関する追記で、MBTilesの正式サポート表明ではない [^gl-346]。
- **結論（机上）**: `maplibre_gl` でも `mbtiles://` は**動く可能性が高いが非公式扱い**。実装には「アプリ書き込み可能ディレクトリへの事前コピー」という一手間が必須で、公式に文書化された安定機能ではない。

### 2.2 `maplibre`（josxha 版）

- 公式の機能マトリクス（`website/features/index.md`）に **MBTiles / PMTiles が独立した行として明記**されており、**MBTiles は Android ✅・iOS ✅**（Web/Windows/macOS/Linux は ❌）と表になっている [^new-features]。
- ただし本文ドキュメント（`sources.md`）内には MBTiles の具体的な参照構文（URLスキームの書式）についての説明が見当たらず、明示されているのは PMTiles の構文（`pmtiles://https://example.com/tiles.pmtiles` や、ローカルファイルを指す `pmtiles://files://path/tiles.pmtiles`）のみ [^new-sources]。リポジトリ内のコード・issue検索でも `mbtiles://` という文字列そのものはヒットしなかった。
- **結論（机上）**: 機能マトリクス上は MBTiles 対応が明言されているため望みは持てるが、**具体的な参照方法（構文・ファイル配置要件）の一次情報が見つからなかった**。実機検証で最初に確認すべき対象。

### 2.3 フォールバックの実現可能性（PMTiles）

- 両パッケージとも **PMTiles はローカルファイル参照込みで公式サポート**しており、ドキュメント化の完成度も高い [^gl-pmtiles-doc] [^new-sources]。
- `pmtiles convert input.mbtiles output.pmtiles` でMBTiles→PMTiles変換が可能であることが `maplibre_gl` 側ドキュメントに明記されている [^gl-pmtiles-doc]。`tools/pack-builder/` のパイプライン（tasks.md T039）にこの変換ステップを1つ足すだけで、MBTilesが直接読めない場合のフォールバックが成立する可能性が高い。

### 2.4 ネイティブビュー埋め込み（plan.md §3.3・§14 R1のもう一つのフォールバック候補）の実現可能性（机上レベルの見立てのみ）

- 本調査では実装や一次情報の収集は行っていない。以下は§1〜§2で確認した事実からの**机上レベルの推測**であり、検証を経た結論ではない。
- `maplibre_gl`・`maplibre`（josxha版）とも、Android側はいずれも同じ **MapLibre Native（maplibre-native）Androidエンジン**の上に構築されたラッパーである（`maplibre_gl` はメソッドチャネル、`maplibre`はJNI/`jnigen`経由 [^new-parity]）。両パッケージが依存するネイティブ層自体は Kotlin から直接呼び出し可能なはずで、`mbtiles://` や `feature-state` はネイティブ層（`maplibre-native` Android SDK）には既に存在する可能性が高い（Issue #318 のコメントで `m0nac0` 氏が「Android/iOSでは動くはず」と述べている根拠も同エンジンの挙動 [^gl-318]）。
- したがって「ネイティブビュー埋め込み」とは、実質的に **Flutterプラグインを介さず、`app/android/` 側でKotlinから直接 `maplibre-native` Android SDKを呼び、`PlatformView`（`AndroidView`）でFlutter側に埋め込む**という選択肢を指すと考えられる。plan.md §1-C の「機微処理はKotlinネイティブ＋Pigeon」という既存方針と設計思想は合致する。
- ただし、この経路を取る場合は**Pigeon契約の設計・PlatformViewのライフサイクル管理・イベント（タップ等）のブリッジを自前で書く必要があり、`maplibre_gl`/`maplibre`が担っているAPI表層（addSource/addLayer/feature-state等の型安全なDart API）を自前で再実装するコストを負う**ことになる。「両プラグインとも公式に文書化された形でMBTiles・feature-stateが安定して使えない」という最悪ケースでのみ検討する価値がある、重い選択肢と見立てる。
- **結論**: 技術的には実現可能性が高いと推測されるが、一次情報（実装事例・工数感）は確認できていない。実機検証でR1・R2が明確に不合格になった場合にのみ、詳細調査の対象とすることを推奨する。

---

## 3. 動的 `addSource` / `addLayer` / `feature-state` のAPI提供状況

### 3.1 `addSource` / `addLayer`

- **両パッケージとも Dart 側APIとして明確に提供されている。**
  - `maplibre_gl`: `MapLibreMapController.addSource()` / `.addLayer()`（命令的API）。
  - `maplibre`（josxha版）: `StyleController.addSource()` / `.addLayer()`（`mapController.style?.addSource(...)`）。ドキュメントの各レイヤー種別ページ（fill/line/circle/raster/symbol/heatmap/hillshade/fill-extrusion）すべてに `await style.addSource(...)` → `await style.addLayer(...)` のサンプルコードが掲載されている [^new-sources-layers]。機能マトリクスでも「Add or remove a Map Source」「Add or remove a Map Layer」がAndroid ✅ [^new-features]。

### 3.2 `feature-state`

**これが今回の調査で最大の発見**。両パッケージで状況が大きく異なる。

- **`maplibre_gl`**: `setFeatureState` / `removeFeatureState` は Dart API 上は存在するが、実装コード（`maplibre_gl_platform_interface/lib/src/method_channel_maplibre_gl.dart`）を直接確認したところ、Android/iOS 向けの実装は

  ```dart
  // TODO: Implement feature state support for iOS and Android
  throw UnimplementedError(
    'setFeatureState is not yet implemented on iOS and Android. '
    'This feature is currently only available on web.',
  );
  ```

  という状態だった [^gl-featurestate-code]。**つまり現行の安定版（0.26.2）ではAndroidで `feature-state` は使えない（例外がスローされる）。**
  - ただし Issue #889「Support feature-state (setFeatureState / removeFeatureState) on Android & iOS」が **2026-08-07（本調査のわずか4日前）に Android 対応がマージされてクローズ**されていることを確認した [^gl-889]。コメントいわく "Implemented on Android in 0.27.0"。**iOSは引き続き未対応**（MapLibre iOS SDK自体がfeature-state APIを公開していないため。upstream の `maplibre-native#1698` に依存し #951 で追跡中、との説明）。
  - **重要**: この 0.27.0 は、本調査時点（2026-08-11）で **pub.dev にはまだ公開されていない**（`gh release list` で確認できる最新タグは v0.26.2・2026-06-19公開）[^gl-release]。ロードマップ Issue #873「Roadmap: maplibre_gl 0.27.0」で feature-state のAndroid実装と、後述のGeoJSONエンコード性能改善が「マージ済み（チェック済み）」の項目として掲載されている [^gl-873]。**実機検証時点でこのリリースが出ているかどうかの確認が必要**（出ていなければ `git` 依存でmainブランチを直接参照する選択肢も検討要）。

- **`maplibre`（josxha版）**: リポジトリ全体を `feature-state` / `featureState` / `setFeatureState` でコード検索したが、**実装・ドキュメントともに一切ヒットしなかった**（唯一のヒットは、フィルタ式の制約について触れたdocコメント内の「feature-state expression is not supported in filter expressions」という無関係な一文のみ）[^new-featurestate-search]。`maplibre_gl parity` ラベルの issue 一覧にも feature-state 関連の項目は見当たらなかった [^new-parity]。**結論: 現時点で feature-state APIが存在するという根拠は見つからなかった。**（実装されているのに検索でヒットしなかった可能性はゼロではないため、実機検証で改めて確認が必要）

---

## 4. fog of war（穴あきポリゴン1枚のGeoJSON差分更新）に関する既知の制約・性能報告

- **terra-town固有の「fog of war」事例は両リポジトリのIssue検索で見つからなかった。** `flutter_map`（別エンジン）向けには `mazenodd/fog-of-war` という穴あきポリゴンGeoJSONベースのライブラリが存在することを確認したが [^fogofwar-fluttermap]、MapLibre系（`maplibre_gl`・`maplibre` いずれも）の Issue には fog of war 名指しの事例・議論は見当たらなかった。
- **ただし、直接関連する性能上の既知の問題を `maplibre_gl` 側で発見した**。Issue #366「Performance issue - Main isolate is blocked when encoding geojsonFeature」（現在も open）:
  > `addGeoJsonSource` / `setGeoJsonSource` は内部で `jsonEncode` を**同期的**にメインアイソレートで実行しており、点数の多いジオメトリ（例: 4万点のライン）ではUIスレッドが数秒単位でフリーズしうる。フレームチャートで実測されたフリーズが添付されている。[^gl-366]
  - この項目はロードマップ Issue #873（0.27.0）で「マージ済み」としてチェックされている（`compute` によるオフロード or Pigeon経由の構造化データ送信で対応、との記載）[^gl-873]。**ただし#366 issue自体はまだopen状態のままであり、0.27.0が未リリースの現状、この修正が安定版に反映されているかは実機検証時点で要確認。**
  - さらに Issue #889（feature-state・上述）のコメントには、実運用での定量報告として「約1,000ポリゴンを毎フレーム再彩色するアニメーションで、モバイルでは `setGeoJsonSource` がジオメトリ全体を毎回再エンコード・再テッセレーションする」という記述があった（具体的なms/fps数値は本文冒頭のみで、コメント全文の詳細計測値は本調査では取得していない）[^gl-889]。**これは plan.md §8 の「開示ヘクス1つ追加ごとの `setGeoJSON` 更新を200ms以内」という基準に対して直接のリスク要因**である。ヘクス数千〜1万規模の差分更新を伴うfog of war実装で、同様のメインスレッドブロッキングが起きうることを示唆する。
- **MapLibre GL JS（Web版・参考情報）の一般的な大規模GeoJSON最適化ガイド**では、座標精度を約6桁（1cm相当）に削減する、ジオメトリを簡略化する、データを地理的/更新頻度別に2〜3チャンクへ分割する、といった助言がある [^maplibre-largedata]。plan.md §8 が既に採用している「隣接結合によるunion」「isolateでの演算」「ビューポート近傍限定の再計算」という方針は、この一般的なベストプラクティスと整合している。ただしこれはWeb版（maplibre-gl-js）のドキュメントであり、モバイル版（maplibre-native）に同程度の最適化ガイドが公式に存在するかは確認できなかった。
- **結論**: fog of war 実装そのものの事例は見つからなかったが、その土台となる「頻繁なGeoJSON差分更新」の性能問題は `maplibre_gl` 側で実際に issue化・修正中であることが確認できた。これは実機計測（T014）で最優先に確認すべきリスクである。

---

## 5. 机上調査時点での暫定推奨と理由

**暫定推奨: `maplibre_gl` を第一候補として実機検証を開始し、`maplibre`（josxha版）を並行して短時間だけ試す。**

理由:

1. **feature-state の状況が意思決定に直結する**。plan.md §8 のフォールバック案（「ローカルタイルプロバイダ＋feature-stateで開示トグル」）は、`maplibre_gl` では2026-08-07時点でAndroid対応がmainにマージされたばかりで安定版未リリース、`maplibre` では対応の根拠自体が見つからなかった。**どちらを選んでも feature-state フォールバックは「今すぐ安定して使える」状態ではない**。したがって R2 の第一案（GeoJSON差分更新）が実機で基準を満たせるかどうかが、プラグイン選定よりも優先度の高い検証事項になる。
2. **`maplibre_gl` はダウンロード数・Star数・Issue解決の実績で優位**（71k weekly downloads、356 stars、84 open issuesだが機能追加・性能改善が継続的にマージされている）。枯れた命令的APIは、`core/`（純粋ロジック）と `location/`（GPS/地図）を分離するGPS_ARCHITECTURE制約とも相性がよい（`location/` 側で薄いラッパーを書けばよく、宣言的APIの学習コストが不要）。
3. **`maplibre` はMBTilesが機能マトリクス上明記されている点が魅力的**だが、具体的な参照構文の一次情報が見つからず、pub.dev公開版（0.3.5・2026-04-11）とmainブランチ（2026-08-09まで活発にpush）の差分がどの程度あるか不明。宣言的APIはFlutterらしいが、まだ若いパッケージ（Stars 150・Open issues 30・Likes 67）でエコシステムの厚みは`maplibre_gl`に劣る。
4. **両パッケージとも0.27.0 / 次期リリースが未公開**のタイミングで検証することになるため、実機検証では「pub.dev安定版で試す」と「必要なら git 依存でmainブランチを直接参照して試す」の両方を選択肢に入れておくとよい。

**この推奨は机上情報のみに基づく暫定であり、確定ではない。** R1（MBTiles読込・動的API疎通）とR2（fog of war性能）の実機結果次第で、`maplibre` への切り替えやPMTilesフォールバックへの転換もあり得る。

---

## 6. 実機検証の結果（2026-08-13 実施）

> **実施済み。** 代表が Pixel 7a（Android 17 / API 37）で `spikes/map_spike_gl` 検証ハーネスを実行して計測した。
> 計測の生ログと経緯は [Issue #24 のコメント](https://github.com/rokusoudo-product/terra-town/issues/24) に記録している。

### 6.0 【重要な訂正】0.27.0 の所在（本書 §3.2・§4 の誤り）

本書は当初「feature-state の Android 対応（#889）と Issue #366 の修正が **`main` にマージ済み**」と記述していたが、**これは誤りであった**。実地確認の結果は次のとおり。

| ブランチ | 最新コミット | feature-state Android | #366 エンコードオフロード |
|---|---|---|---|
| `main` | `eae2129c` / 2026-08-04 | ✗ 未収録 | ✗ 未収録 |
| `release-0.27.0` | `0024af65` / 2026-08-07 | ✓ 収録 | ✓ 収録 |

0.27.0 の作業は上流の**リリースブランチ**（PR #956・open）にある。`main` の最新コミットは #889 のクローズ日（2026-08-07）より前の 08-04 であり、そもそも入りようがなかった。

確認方法（一次情報）:

- `MapLibreMapController.java`（`release-0.27.0`）に `source#setFeatureState` / `source#removeFeatureState` の実装を確認。`main` の同ファイルには `featureState` の文字列が0件
- `method_channel_maplibre_gl.dart`（`release-0.27.0`）の `_encodeGeoJson` が閾値超過時に `compute(jsonEncode, geojson)` を呼ぶことを確認

**`ref: main` で計測すると「0.27.0 でも直らない」という誤った結論に至る。** 検証は必ず `ref: release-0.27.0` で行うこと。

### 6.1 T011: プラグイン選定（実機での最終判断）

- [x] `maplibre_gl` を実機Android端末で動作確認 → **起動・地図ビュー表示とも問題なし**（0.26.2 / release-0.27.0 の両方）
- [ ] `maplibre` 0.3.5（josxha版）での確認 → **未実施**
- [x] 実機検証時点で 0.27.0 が pub.dev に公開されているか → **未公開**（2026-08-13 時点で最新は 0.26.2 / 2026-06-19）。上流 PR #956 が open
- [x] **最終選定結果: `maplibre_gl`（`release-0.27.0` 相当）を推奨**
- [x] **選定理由**: fog of war の合格基準（§6.4）を満たす唯一の構成が「`maplibre_gl` 0.27.0 の feature-state を使う第二案」であったため。0.26.2 では feature-state が Android 未実装で、第二案自体が成立しない。josxha 版は feature-state の実装根拠が見つかっておらず（§3.2）、同じ方式を取れる見込みがない

> **未リリース版への依存という制約が残る。** pub.dev 版では合格構成を組めないため、当面は git 依存（`ref: release-0.27.0`）で固定するか、0.27.0 のリリースを待つ判断が必要。

### 6.2 T012 / R1: ローカルMBTiles読込

- [ ] `mbtiles://` 方式の実機動作 → **未検証（ハーネス側の不具合により判定不能）**
- [ ] `maplibre`（josxha版）でのMBTiles参照 → **未実施**（参照構文が特定できず、ハーネスの該当ボタンは無効化してある）
- [ ] PMTiles フォールバックの実測 → **未実施**

**判定できなかった理由**: 検証用フィクスチャ（MapLibre 公式デモの `maplibre.mbtiles`）は**ベクタタイル**だが、ハーネスは `RasterSourceProperties` で読み込む実装になっていた（`spikes/map_spike_gl/lib/map_probe_page.dart`）。この不一致のままでは、失敗してもプラグインの能力の問題かハーネスの作りの問題か切り分けられない。**ハーネスをベクタソース対応に修正してからの再検証が必要。**

### 6.3 T013 / R1: 動的 addSource/addLayer/feature-state

- [x] `addGeoJsonSource` / `addLayer` の動作確認 → **動作する**（§6.4 の第二案ベンチマークが10,000ヘクスのソース追加とレイヤ追加に成功している）
- [x] `feature-state` が実機で動作するか → **`release-0.27.0` で動作する**（§6.4 の第二案が `setFeatureState` を10,000回成功させ、例外なし）。**0.26.2 では Android 未実装**
- [x] feature-state が使えない場合の fog of war への影響 → **当初の想定と逆の結論になった。** 本書は「第一案は feature-state 非依存のため影響は限定的」と書いていたが、実測の結果**第一案が基準未達・第二案のみ合格**となったため、**feature-state は fog of war の成否を左右する必須機能**である

**Android 固有の制約（実装で判明）**: `promoteId` は Web 専用で Android では機能しない（上流 `controller.dart` に明記）。したがって `properties` 内の値を feature id に昇格させる方式は取れず、**各 Feature の直下に整数 `id` を持たせる必要がある**。
→ **地域パック生成（`tools/pack-builder/` ・ Issue #38）は、この id を埋め込む前提で設計する必要がある。**

### 6.4 T014 / R2: fog of war 性能計測

計測条件: Pixel 7a / Android 17、ヘクス数 10,000、開示回数 n=10,000。基盤地図タイルは HTTP 429（`demotiles.maplibre.org` のレート制限）のため未読込＝**実際より軽い条件**。3計測とも同条件のため相互比較は妥当。

| 指標 | 第一案 0.26.2 | 第一案 0.27.0 | **第二案 0.27.0** |
|---|---|---|---|
| 更新レイテンシ min | 3.2ms | 3.4ms | 0.2ms |
| 更新レイテンシ median | 310.4ms | 341.3ms | **0.3ms** |
| 更新レイテンシ max | 7,911.0ms | 6,875.8ms | **37.7ms** |
| 更新レイテンシ avg | 621.0ms | 1,408.8ms | **0.9ms** |
| frames | 5,231 | 10,292 | 524 |
| jank率 | 99.6% | 70.3% | 59.7% |
| fps | 0.8 | 0.7 | **56.6** |
| avgFrame | 305.7ms | 82.9ms | **19.8ms** |
| maxFrame | 2,472.6ms | 680.7ms | 1,077.3ms |
| **判定** | **FAIL** | **FAIL** | **PASS** |

- [x] 開示1ヘクス追加時の更新時間（基準200ms以内） → **第二案 PASS**（max 37.7ms）／第一案は両版とも FAIL
- [x] Issue #366 のメインアイソレートブロッキングが再現するか → **0.26.2 で再現**（avgFrame 305.7ms・jank 99.6%）。**0.27.0 で緩和**（avgFrame 82.9ms・jank 70.3%）するが、**総スループットは悪化**（avg 621ms → 1,408.8ms）。上流の実装コメントが明言するとおり "This buys a responsive UI, not speed"
- [x] ヘクス1万個開示状態での fps（基準55fps以上） → **第二案の更新ループ中 56.6fps で基準充足**。ただし手動パン・ズーム時の計測は未実施
- [ ] スタイル再読み込み時のちらつきの有無 → **未実施**
- [x] 基準未達時のフォールバック（第二案）が選択可能か → **選択可能であるだけでなく、第二案が唯一の合格構成であった**

#### ⚠️ 第一案の FAIL 判定に関する重要な但し書き

**計測した第一案は、plan.md §8 が規定していた第一案の完全形ではない。** plan.md §8 は第一案に次の最適化を含めていたが、ハーネスは**いずれも実装していない**:

1. 開示済みヘクスの **boolean union によるマージ**（隣接結合で頂点数を激減させる）
2. union 演算の **isolate 実行**
3. **ビューポート近傍に限定した再計算**

ハーネスが計測したのは「n個の穴を持つポリゴンを毎回まるごと再エンコードする」素朴な実装であり、**上記3つの最適化を入れた第一案であれば基準を満たせた可能性は否定できない**。

ただし本書は、それでも第二案の採用を推奨する。理由:

- 第二案は最適化を一切行わない素朴な実装のまま、基準を **2桁以上の余裕**で満たしている（max 37.7ms vs 基準200ms）
- 第二案は union アルゴリズムもビューポート管理も不要で、**実装が単純**
- 第一案は最適化を入れても、更新のたびに再エンコードが走る以上コストが開示済み数に依存する。第二案は `setFeatureState` 1回で済み、開示済み数に依存しない

すなわち「第一案を最適化すれば救えるか」は未検証だが、**救えたとしても第二案より複雑で遅い**ため、検証の実益が乏しいと判断した。

#### 残る未計測事項

- **ソース構築の一回コスト**（本計測では対象外）。`maxFrame=1,077.3ms` は10,000ヘクスのソース追加直後の初回描画と推測される。実際の地域パックはヘクス数がこれを上回りうるため、**起動時・エリア切替時の待ち時間**として別途計測が必要
- jank率 59.7%（avgFrame 19.8ms）。60Hz の閾値16.67msをわずかに超えるフレームが多い。体感上は問題にならない水準と考えられるが、**基盤地図タイルを重ねた状態での再計測が望ましい**
- 手動パン・ズーム時の fps（plan.md §8 の「1万ヘクス開示状態でのパン/ズーム55fps」の厳密な検証）

---

## 6-旧. 実機で検証すべき項目チェックリスト（原本・記録として保持）

> 以下は机上調査時点で用意した空欄のチェックリスト。実際の結果は上の §6 に記載した。

### 6.1 T011: プラグイン選定（実機での最終判断）

- [ ] `maplibre_gl` 0.26.2（または実機検証時点の最新安定版）で基本的な地図表示・操作を実機Android端末で確認
- [ ] `maplibre` 0.3.5（または実機検証時点の最新安定版）で同様に確認
- [ ] 実機検証時点で `maplibre_gl` 0.27.0 が pub.dev に公開されているか確認（公開されていれば feature-state Android対応とGeoJSONエンコード性能改善を含む版で検証できる）
- [ ] 最終選定結果: （　　　　　　　　）
- [ ] 選定理由: （　　　　　　　　）

### 6.2 T012 / R1: ローカルMBTiles読込

- [ ] `maplibre_gl` で `mbtiles://<書き込み可能ディレクトリのパス>` 方式が実機で動作するか（Issue #318 の手順を再現）
- [ ] `maplibre` でMBTilesの参照方法を特定し、実機で動作するか（構文が公式に見つからなかったため、まずソースコード調査が必要になる可能性がある）
- [ ] 動作しない場合: PMTiles変換フォールバック（`pmtiles convert`）を試し、`tools/pack-builder/` パイプラインへの追加コストを見積もる
- [ ] 再現手順: （　　　　　　　　）
- [ ] 結果: （　　　　　　　　）

### 6.3 T013 / R1: 動的 addSource/addLayer/feature-state

- [ ] `addSource`/`addLayer` の動作確認（両パッケージとも公式APIとして存在することは机上確認済みのため、実機では地域パックのベクタタイルを使った実データでの疎通を優先）
- [ ] `feature-state` が選定プラグインの実機バージョンで動作するか（`maplibre_gl` の場合は0.27.0以降が必要な可能性）
- [ ] feature-stateが使えない場合、fog of war方式にどの程度影響するか（plan.md §8の第一案＝GeoJSON差分更新は feature-state 非依存のため、影響は限定的なはず。要確認）

### 6.4 T014 / R2: fog of war 性能計測

- [ ] 開示1ヘクス追加時の `setGeoJSON` 更新時間（基準: 200ms以内）
- [ ] Issue #366 のメインアイソレートブロッキング問題が選定プラグインの実機バージョンで再現するか（同一4万点規模ではなくとも、テスト用の合成データで大きめのポリゴンを用意して確認）
- [ ] ヘクス1万個開示状態でのパン・ズームfps（基準: 55fps以上）
- [ ] スタイル再読み込み時のちらつきの有無
- [ ] 基準未達の場合のフォールバック（第二案: ローカルタイルプロバイダ＋feature-state）が実機で選択可能な状態か（§3.2の状況次第）

---

## 7. 未確定・情報が得られなかった事項

- `maplibre`（josxha版）における MBTiles の具体的な参照構文・ファイル配置要件（機能マトリクス上は対応と明記されているが、一次情報未発見）。
- `maplibre`（josxha版）における feature-state APIの有無（コード検索・issue検索とも根拠が見つからなかった。実装されているが検索でヒットしなかった可能性は排除できない）。
- `maplibre_gl` 0.27.0（feature-state Android対応・GeoJSONエンコード性能改善を含む）の pub.dev 公開時期。本調査時点（2026-08-11）では未公開。
- fog of war（穴あきポリゴン1枚のGeoJSON差分更新）そのものの、MapLibre系プラグインでの実装事例・性能報告。両リポジトリのIssueには見当たらなかった。
- ネイティブビュー埋め込み（plan.md §3.3のもう一つのフォールバック候補）の実現可能性。本調査ではスコープ外として扱い、調査していない。
- `maplibre_gl` Issue #889で言及された「1,000ポリゴン毎フレーム再彩色」の詳細な計測値（ms/fps）。issue本文冒頭の要旨のみ確認し、コメント全文の数値は取得していない。
- 週間ダウンロード数について、`maplibre`（josxha版）のpub.dev上の数値は本調査では確認できなかった。

---

## 出典

[^gl-release]: [maplibre/flutter-maplibre-gl リリース一覧](https://github.com/maplibre/flutter-maplibre-gl/releases)（`gh release list` で確認。v0.26.2 = 2026-06-19公開）
[^gl-repo]: [maplibre/flutter-maplibre-gl リポジトリ](https://github.com/maplibre/flutter-maplibre-gl)（`gh api repos/maplibre/flutter-maplibre-gl` で確認。stars 356・open issues 84・pushed_at 2026-08-10）
[^gl-pubdev]: [maplibre_gl | pub.dev](https://pub.dev/packages/maplibre_gl)
[^gl-pubspec]: [maplibre_gl/pubspec.yaml（mainブランチ）](https://github.com/maplibre/flutter-maplibre-gl/blob/main/maplibre_gl/pubspec.yaml)
[^gl-minsdk]: [maplibre_gl/android/build.gradle（mainブランチ）](https://github.com/maplibre/flutter-maplibre-gl/blob/main/maplibre_gl/android/build.gradle)
[^gl-pmtiles-doc]: [website/docs/advanced/pmtiles.md（mainブランチ）](https://github.com/maplibre/flutter-maplibre-gl/blob/main/website/docs/advanced/pmtiles.md)
[^gl-318]: [Issue #318: How to load an mbtiles file](https://github.com/maplibre/flutter-maplibre-gl/issues/318)
[^gl-346]: [PR #346: Readme: add documentation about referencing assets (mbtiles/sprites etc.)](https://github.com/maplibre/flutter-maplibre-gl/pull/346)
[^gl-featurestate-code]: [maplibre_gl_platform_interface/lib/src/method_channel_maplibre_gl.dart（mainブランチ）](https://github.com/maplibre/flutter-maplibre-gl/blob/main/maplibre_gl_platform_interface/lib/src/method_channel_maplibre_gl.dart)
[^gl-889]: [Issue #889: Support feature-state (setFeatureState / removeFeatureState) on Android & iOS](https://github.com/maplibre/flutter-maplibre-gl/issues/889)（2026-08-07クローズ）
[^gl-873]: [Issue #873: Roadmap: maplibre_gl 0.27.0](https://github.com/maplibre/flutter-maplibre-gl/issues/873)
[^gl-366]: [Issue #366: Performance issue - Main isolate is blocked when encoding geojsonFeature](https://github.com/maplibre/flutter-maplibre-gl/issues/366)
[^maplibre-largedata]: [Optimising MapLibre Performance: Tips for Large GeoJSON Datasets（MapLibre GL JS公式ガイド）](https://maplibre.org/maplibre-gl-js/docs/guides/large-data/)
[^new-release]: [josxha/flutter-maplibre リリース一覧](https://github.com/josxha/flutter-maplibre/releases)（`gh release list` で確認。v0.3.5 = 2026-04-11公開）
[^new-repo]: [josxha/flutter-maplibre リポジトリ](https://github.com/josxha/flutter-maplibre)（`gh api repos/josxha/flutter-maplibre` で確認。stars 150・open issues 30・pushed_at 2026-08-09）
[^new-pubdev]: [maplibre | pub.dev](https://pub.dev/packages/maplibre)
[^new-pubspec]: [packages/maplibre/pubspec.yaml（mainブランチ）](https://github.com/josxha/flutter-maplibre/blob/main/packages/maplibre/pubspec.yaml)
[^new-minsdk]: [packages/maplibre_android/android/build.gradle.kts（mainブランチ）](https://github.com/josxha/flutter-maplibre/blob/main/packages/maplibre_android/android/build.gradle.kts)
[^new-features]: [website/features/index.md（機能対応マトリクス・mainブランチ）](https://github.com/josxha/flutter-maplibre/blob/main/website/features/index.md)
[^new-sources]: [website/docs/sources.md（mainブランチ）](https://github.com/josxha/flutter-maplibre/blob/main/website/docs/sources.md)
[^new-sources-layers]: [website/docs/style-layers/（各レイヤーのサンプルコード・mainブランチ）](https://github.com/josxha/flutter-maplibre/tree/main/website/docs/style-layers)
[^new-migrate]: [website/docs/migrate/maplibre_gl.md（mainブランチ）](https://github.com/josxha/flutter-maplibre/blob/main/website/docs/migrate/maplibre_gl.md)
[^new-featurestate-search]: `gh search code 'feature-state' --repo josxha/flutter-maplibre` / `gh search code 'setFeatureState' --repo josxha/flutter-maplibre`（2026-08-11実行、後者は0件）
[^new-parity]: [`maplibre_gl parity` ラベルのIssue一覧](https://github.com/josxha/flutter-maplibre/labels/maplibre_gl%20parity)
[^fogofwar-fluttermap]: [mazenodd/fog-of-war（flutter_map向け・参考）](https://github.com/mazenodd/fog-of-war)
