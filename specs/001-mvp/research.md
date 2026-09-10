---
type: spec
project: terra-town
doc: research.md（Flutter 地図プラグイン選定スパイク・机上調査）
feature: 001-mvp
status: review               # 机上調査＋R2実機計測が完了。R1（MBTiles読込）は未検証
created: 2026-08-11
updated: 2026-09-08
related:
  - specs/001-mvp/plan.md
  - specs/001-mvp/tasks.md
  - docs/dev-setup.md
  - docs/terrain.md
  - https://github.com/rokusoudo-product/terra-town/issues/24
---

# terra-town — Flutter 地図プラグイン選定スパイク（Issue #24・R1・R2）研究ノート

> **本ドキュメントの現在の状態（2026-09-08 更新）: 机上調査に加え、R2（fog of war 性能）の実機計測が完了。R1（ローカルMBTiles読込）は未検証。**
>
> - **R2 の結論**: plan.md §8 の**第二案（feature-state によるヘクス単位の開示トグル）が合格**。第一案（GeoJSON 全体の再エンコード）は不合格。詳細と数値は §6.4。ただし第一案の計測には但し書きがある（§6.4 の⚠️を必ず読むこと）
> - **2026-08-14 追加計測（§6.4）**: 第二案のスケール検証（50,000／100,000ヘクス）が完了し、ソース構築の一回コストが判明した（100,000ヘクスで `addGeoJsonSource` 6,535.2ms・OOM）。これを根拠に `plan.md` §3 へ暫定上限（30,000ヘクス／1ソース）を明記済み（代表決定 2026-09-07・Issue #49）
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

> **【2026-09-09 訂正】本節が当初 `RasterSourceProperties` を前提として書いていたのは誤りだった。**
> terra-town の地域パックは `plan.md` §3.2 のとおり**ベクタタイル MBTiles**（Planetiler生成）である。
> ところが本節はIssue #318のコミュニティ報告のうち「ラスタ・ベクタタイル双方の報告あり」の
> 部分から `RasterSourceProperties` の使用例だけを本文に採用してしまい、`addSource` に渡す
> プロパティ型としてラスタ用のクラスを案内していた（下記「`RasterSourceProperties(tiles: [...])`
> を `addSource` に渡す方式で動作」の記述）。
>
> この誤りは机上調査だけでは表面化せず、`spikes/map_spike_gl/lib/map_probe_page.dart`
> の実装がこの記述に忠実に従ったことで**そのままハーネスに伝播した**。その結果、§6.2
> （T012 実機検証）で「フィクスチャ（ベクタタイル）を `RasterSourceProperties` で読もうとして
> いた」という不一致が発覚し、**プラグインの能力の問題かハーネスの作りの問題かを切り分け
> られず、判定不能に終わった**（詳細は §6.2「判定できなかった理由」）。
>
> **訂正後の結論**: terra-town の用途（ベクタタイルMBTiles）では `addSource` に渡すべきは
> `VectorSourceProperties` であり、ベクタソースは**レイヤー（fill/line等）を別途追加しないと
> 何も描画されない**点も当時の記述には無かった注意点である。一方、**`VectorSourceProperties`
> の `url` パラメータと `tiles` パラメータのどちらで `mbtiles://<パス>` を渡すべきかは、
> Issue #318のコメントも含め一次情報で確定できていない。これは推測で断定せず、実機で
> 両方試して切り分ける**（`spikes/map_spike_gl` のハーネスに両方のボタンを用意した。
> 別PR・Issue #24参照）。
>
> なお、下記の「アセット/外部ストレージのファイルを書き込み可能ディレクトリへ事前コピーする
> 必要がある」という結論（ソース種別に依存しない、MapLibre Nativeの `mbtiles://` スキームの
> 制約）自体は誤りではなく、そのまま有効である。

- 公式ドキュメントには **MBTiles 専用ページが存在しない**。`website/docs/advanced/` 配下にあるのは `pmtiles.md` のみで、PMTiles が第一級（公式ドキュメント化された）機能として案内されている。同ドキュメントは「MBTiles を PMTiles に変換して使う」ことを推奨している（`pmtiles convert input.mbtiles output.pmtiles`）[^gl-pmtiles-doc]。
- 一方で、コミュニティの実地検証は存在する。Issue #318「How to load an mbtiles file」（2023-10 open、直近コメント2023-11、**未クローズ**）で、`mbtiles://` スキームは **maplibre-native 自体には実装されている**ことが示唆され、実際に動作報告が複数ある [^gl-318]:
  - ~~`RasterSourceProperties(tiles: ['mbtiles:///<絶対パス>/map.mbtiles'])` を `addSource` に渡す方式で動作（ラスタ・ベクタタイル双方の報告あり）。~~ **【誤り・上記2026-09-09訂正参照】** 同Issueの報告はラスタ・ベクタタイル双方を含んでいたが、本節はラスタ用のプロパティクラスのみを案内していた。terra-townの用途（ベクタタイルMBTiles）では `VectorSourceProperties` を使うこと。`url`/`tiles`のどちらのパラメータで渡すかは未確定（実機で切り分け）。
  - **Flutter の asset バンドルから直接は読めない**。`assets/` 同梱ファイルはアプリの署名パッケージ内に封じ込まれており、ネイティブSQLiteが直接開けない。`rootBundle.load()` で読み出し、`getApplicationCacheDirectory()`（や `getExternalStorageDirectory()`）配下の**書き込み可能なファイルシステムパスにコピーしてから** `mbtiles://` で参照する、という2段階の実装が必要（同Issueの `venomwine` 氏のコードで確認）。この結論は訂正の対象ではない。
  - 既知の不具合報告（`timautin` 氏）: ズームイン時とズームアウト時でタイルの表示/非表示が切り替わる閾値がずれる、80MB程度の大きめのmbtilesでは min/max zoom を明示しないと一部タイルが表示されないことがある。
  - この経路は**公式サポートではなくコミュニティが発見した挙動**であり、READMEには「アセット参照方法のドキュメント化」を目的とした PR #346（2023-12 マージ済）はあるが、これは主にPMTiles/一般的なアセット参照に関する追記で、MBTilesの正式サポート表明ではない [^gl-346]。
- **結論（机上・2026-09-09訂正済み）**: `maplibre_gl` でも `mbtiles://` は**動く可能性が高いが非公式扱い**。terra-townの用途ではベクタソース（`VectorSourceProperties`）＋レイヤー追加が必要で、`url`/`tiles`のどちらのパラメータを使うべきかは一次情報で確定できていない（実機検証が必要）。実装には「アプリ書き込み可能ディレクトリへの事前コピー」という一手間も必須で、公式に文書化された安定機能ではない。

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

> **【2026-09-08 更新】未リリース版依存の制約は解消した。** `maplibre_gl` 0.27.0 は 2026-08-19 に pub.dev へ公開済み（`latest=0.27.0`）。`packages/location/pubspec.yaml` は git 依存（`ref: release-0.27.0`）ではなく pub.dev 版 `maplibre_gl: ^0.27.0` を採用する（代表決定 2026-09-07・Issue #55）。
>
> 上流リリースノート（[v0.27.0](https://github.com/maplibre/flutter-maplibre-gl/releases/tag/v0.27.0)）で、本節が前提とする2点がいずれも0.27.0に含まれることを確認した。
> - Android の feature-state 対応（上流 #889）: 「**Android**: feature state (`setFeatureState`, `getFeatureState`, `removeFeatureState`) works on Android as well as web ... `promoteId` stays web-only, so Android features need a top-level `id` in the GeoJSON (#889)」
> - GeoJSON エンコードのバックグラウンド化（上流 #366）: 「**Android, iOS**: adding or updating a GeoJSON source with a large payload no longer blocks the UI for the whole encode ... encoded in the background, cutting the blocking time by a factor of two to three (#366)」
>
> また同リリースで Android の MapLibre Native が 13.3.0 → 13.5.0 に上がっている。**Android ビルド統合を実際に確認した結果、`flutter build apk --debug` が失敗することが判明した**（実機でのR1/R2再計測は行わない。地図表示・fog of war の実装本体は T055・T056 のスコープ）。
>
> **【ビルド統合の検証結果（2026-09-08・Issue #55）】** Flutter 3.44.8 の既定テンプレート（AGP 9.0.1・`android.builtInKotlin=false`）で `flutter build apk --debug` を実行すると、`:maplibre_gl` の評価で `Could not find method kotlin() for arguments [...] on project ':maplibre_gl'`（`maplibre_gl-0.27.0/android/build.gradle` L77）で失敗する。原因は上流の `build.gradle` が Kotlin Gradle Plugin（KGP）の適用を `agpMajor < 9` で分岐しており、AGP 9 以降は「AGP 自身が Kotlin を提供する」前提で KGP を適用しないため。しかし Flutter 3.44.8 は `android.builtInKotlin` を既定で `false` にする移行を行っており（[migrate-to-built-in-kotlin](https://docs.flutter.dev/release/breaking-changes/migrate-to-built-in-kotlin)）、この既定のままでは AGP 側の Kotlin 提供も KGP 適用もどちらも起きず、`kotlin {}` 拡張が存在しない。
> 診断のため `app/android/gradle.properties` の `android.builtInKotlin` を一時的に `true` に切り替えると、**ローカル環境（後述するがJDK21が実際に使われていた環境）では** `flutter build apk --debug` が成功する（`flutter pub deps` 解決バージョンは 0.27.0 系）。ただし Flutter はこのとき次の警告を出す: 「Applying the Kotlin Android Plugin (KGP) was unsuccessful... Future versions of Flutter will fail to build if your app uses plugins that apply KGP.」つまりこれは Flutter が非推奨として扱っている互換シムであり、恒久対応ではない。`minSdk` は今回変更不要（Flutter 既定 `minSdkVersion=24` が `maplibre_gl` の要求 `minSdkVersion=21` を上回るため）。
>
> **【代表決定・2026-09-08】** 暫定対応として `android.builtInKotlin=true` を採用し、コミットした（Blocker A への対応）。他案を採らなかった理由: (1) 上流 `maplibre/flutter-maplibre-gl` の対応を待つ案は不採用——`builtInKotlin`／AGP 9／KGP で検索して該当 Issue が0件（open PR も dependabot の依存バンプのみ、調査日 2026-09-08）で、待っても直る見込みがない。(2) AGP を9未満へ戻す案も不採用——Flutter既定から外れツールチェーンの方向（AGP 9）に逆行し、いずれAGP 9へ戻す移行コストが二重になる（**なお本案が実際に動くかは未検証**）。(1)を選んだ根拠は、1行・可逆・現時点でアプリ側のKotlinコードが `MainActivity.kt` のみのため影響範囲が最小な点。Kotlinの本番実装（T046 foreground service・Pigeon）着手時に再評価する。撤去条件・追跡は **Issue #67**。
>
> **【Blocker B（未解決・2026-09-08発見）: `maplibre_gl` 0.27.0 は JDK 21 を要求する。CIは依然red。】** `android.builtInKotlin=true` をコミットして CI（`ci.yml` の `java-version: "17"`）で実行したところ、Blocker A（`kotlin()` メソッド未検出）は解消したが、別のエラーで `flutter build apk --debug` が失敗した: `Execution failed for task ':maplibre_gl:compileDebugJavaWithJavac'. > Java compilation initialization error: error: invalid source release: 21`。原因は `maplibre_gl-0.27.0/android/build.gradle` が `compileOptions { sourceCompatibility JavaVersion.VERSION_21; targetCompatibility JavaVersion.VERSION_21 }` と `kotlin { compilerOptions { jvmTarget = ...JVM_21 } }` を**AGPのバージョンに関係なく無条件で**指定していること（`agpMajor < 9` 分岐の対象は KGP 適用可否のみで、Java/Kotlinのターゲットバージョンはこの分岐の外にある）。つまり `maplibre_gl` 0.27.0 を組み込むには、Blocker A への対応（本コミットの `builtInKotlin=true`）に加えて **JDK 21 でのビルドが別途必須**であり、これは Issue #67（Blocker A の暫定対応の撤去）とは独立した制約で、上流がBuilt-in Kotlinに対応しても解消しない。
>
> ローカルで最初に「成功」と報告した検証（上記パラグラフ）は、このWSL環境の `java` が `update-alternatives` 経由でシステムJDK 21（`update-alternatives`のデフォルト）に解決されていたために偶然通っていたことが判明した。`docs/dev-setup.md` §2が正本として記載する sdkman管理のJDK 17.0.11（`~/.sdkman/candidates/java/17.0.11-tem`）を明示的に使って再現したところ、CIと同じ `invalid source release: 21` で失敗することを確認した（2026-09-08）。**したがって本PRの時点でCIはBlocker Bにより依然redであり、「ビルドが通った」と言えるのはJDK 21環境に限られる。** JDK をプロジェクト既定として21へ上げる（`ci.yml` と `docs/dev-setup.md` §2 を同一PRで更新し `tools/check_toolchain_versions.sh` の対象を21に更新）べきかどうかは、Issue #67の暫定対応の範囲を超える別のトレードオフ判断であり、代表判断が必要（PR #66参照）。
>
> **【代表決定・2026-09-08、追記】JDK を 17 → 21 に引き上げることを決定した。** 根拠: ゲート②承認済みの feature-state 方式の fog of war（`plan.md` §8）には `maplibre_gl` 0.27.0 以降の `setFeatureState`（Android実装）が必須で、その 0.27.0 が JDK 21 を無条件で要求する以上、JDK 21 を採らない選択肢は事実上「ゲート②の fog of war 方式の決定を開き直す」ことを意味し割に合わない。JDK 21 は LTS で AGP 9.0.1 / Kotlin 2.3.20 とも対応関係があり、ローカル環境（システムJDK 21）で `flutter build apk --debug` の成功も実証済み。`ci.yml` の `java-version` を `"21"` に、`docs/dev-setup.md` §2 の JDK 行を実態（21.0.12・Ubuntu システムパッケージ）に更新し、`tools/check_toolchain_versions.sh` の PASS を確認した（同一PR＝#66）。
>
> **本件が明らかにした `tools/check_toolchain_versions.sh`（Issue #59）の限界**: このチェックは `ci.yml` と `docs/dev-setup.md` §2 という**2つの文書間の一致**を検査するものであり、**文書と実環境のズレは検出できない**。今回は両文書とも JDK 17 の記述で一致していたためチェックはPASSしていたが、実際にビルドを壊していたのは「両文書は17で揃っているが、（非対話シェルの）実環境は21である」というズレそのものだった。文書間整合チェックは「ドキュメントの自己矛盾」は防げても「ドキュメントと現実の乖離」までは防げない、という限界として記録する。

> **【2026-09-10 追記・Issue #67 対応（案A採用）】** `android.builtInKotlin=true`（Blocker A の暫定対応）は「1行・可逆・影響範囲が最小」という前提で採用したが、この前提は誤りだったことが Issue #83（PR #90、SQLite/Drift 導入）で `path_provider` を追加した際の CI 失敗により判明した。秘書セッションが実機ビルドを4回実施して次を実測で確定した（2026-09-10）。
>
> | `android.builtInKotlin` の設定 | 結果 |
> |---|---|
> | `true`（Issue #67 の暫定対応時点の状態） | `path_provider` の組み込みが失敗（`kotlin-android` を適用するため）。`path_provider_android` を 2.2.23 に下げても同じ |
> | `false`（Flutter 既定） | `maplibre_gl` 0.27.0 が失敗（`Could not find method kotlin()` — 本節冒頭で述べた問題そのもの） |
>
> つまり `builtInKotlin=true` と `false` は相互排他であり、`true` を採用している限り **KGP（kotlin-android）を適用するあらゆる Flutter プラグインが `maplibre_gl` と共存できない**。`path_provider` は最も一般的なプラグインの一つであり、今後 `geolocator` や `permission_handler` を追加しても同じ壁に当たる。すなわち Issue #67 は「暫定対応の後片付け」ではなく、**プラグインを追加できないブロッカー**だった。
>
> 上流 `maplibre/flutter-maplibre-gl` を確認したところ、我々が報告した Issue #1018 に対する修正 PR **#1020「fix(android): apply KGP when AGP does not compile Kotlin itself」が 2026-09-08 に main へマージ済み**（commit `2dff788c650f0d49677397aae55423774aecb8f2`）であることを確認した。ただし pub.dev は 0.27.0（2026-08-19）のままで、この修正を含む版は未リリースである。
>
> 次の git 依存構成で `flutter build apk --debug` の成功を実測した（2026-09-10、`android.builtInKotlin=false` の状態）。
>
> ```yaml
>   maplibre_gl:
>     git:
>       url: https://github.com/maplibre/flutter-maplibre-gl.git
>       ref: 2dff788c650f0d49677397aae55423774aecb8f2
>       path: maplibre_gl
> ```
>
> 上流はワークスペース構成（ルートの pubspec は `name: maplibre_gl_workspace`）になっているため、`path: maplibre_gl` の指定が必須である。`flutter clean` 後のクリーンビルドで確認したところ、Flutter が以前出していた「Your app uses the following plugins that apply Kotlin Gradle Plugin (KGP): maplibre_gl」という非推奨警告は**出力に現れなかった**（Issue #67 の未解決の質問への回答: 警告は誤検知ではなく、`builtInKotlin=true` の状態には `path_provider` 等を壊す実害があった。ただし `maplibre_gl` 自身については上流 #1020 の修正により AGP 9 環境で KGP を適用しなくなったため、警告の直接の指摘対象は解消したと考えられる）。
>
> **【代表決定・2026-09-10】この git 依存への切り替え（案A）を採用する。** これは Issue #55（2026-09-07 代表決定・pub.dev 版 `maplibre_gl: ^0.27.0` の採用）の一時的な差し戻しである。上流が 0.27.1 以降を pub.dev にリリースし次第、pub.dev 版へ戻し Issue #55 の決定に復帰する（追跡 Issue は秘書セッションが別途起票）。詳細・実施は Issue #67 / PR「fix/issue-67-remove-builtinkotlin-workaround」を参照。

### 6.2 T012 / R1: ローカルMBTiles読込

> **【2026-09-09 実施・判定確定】** 以下は代表が Pixel 7a で `spikes/map_spike_gl`
> （ベクタソース対応後のハーネス。§2.1訂正・本節末尾の「判定不能に至った経緯」参照）を
> 使って実機検証した結果。旧記述（「未検証・ハーネス側の不具合により判定不能」）は
> この実測結果で置き換える。

- [x] `mbtiles://` 方式の実機動作 → **成功（PASS）**。ログ:
  ```
  21:40:29  同梱フィクスチャをコピー完了 -> /data/user/0/com.rokusoudo.spike.map_spike_gl/code_cache/bundled_sample.mbtiles (5083136 bytes)
  21:40:30  MBTiles(vector/url):      addSource/addLayer(fill+line)成功（例外なし）
  21:40:51  MBTiles(vector/tiles配列): addSource/addLayer(fill+line)成功（例外なし）
  ```
  例外が出なかっただけでなく、**描画も目視で確認済み**（スクリーンショットに青い塗り
  (`countries`)と赤い線(`geolines`)が実際に描画されていた）。**したがって `mbtiles://`
  によるローカルMBTiles読込は成立し、PMTilesへのフォールバックは不要。`plan.md` §14
  のR1差し戻しも回避された。**
  - **⚠️ 精度の限界（url方式単独の成立は強い傍証だが厳密な分離検証ではない）**:
    url方式（`VectorSourceProperties(url:)`）を追加した後、**ソース/レイヤーをリセットせずに**
    tiles配列方式（`VectorSourceProperties(tiles:)`）を重ねて追加しているため、
    実機で最終的に確認された描画がどちらの方式の寄与かは厳密には分離できていない。
    ただし tiles方式のボタンを押す前（21:40:30〜21:40:51の間）に撮られたスクリーンショットで
    既に描画が確認できているため、**url方式単独で成立していると読める。これは強い傍証では
    あるが厳密な分離検証ではなく、断定はしない。** ハーネス側にはリセットボタンを追加した
    （別PR #78）ため、次回検証時は1方式ずつ分離して確認できる。
- [ ] `maplibre`（josxha版）でのMBTiles参照 → **未実施**（参照構文が特定できず、ハーネスの該当ボタンは無効化してある）
- [x] PMTiles フォールバックの実測 → **未実施のまま（実施不要と判断）**。ログ
  `21:41:27 PMTiles: パスが空です` のとおり試されていない。MBTilesが成立したため、
  フォールバックとしてのPMTiles検証自体が不要になった。

**判定不能に至った経緯（旧・2026-09-08時点の記述）**: 検証用フィクスチャ（MapLibre 公式デモの `maplibre.mbtiles`）は**ベクタタイル**だが、ハーネスは `RasterSourceProperties` で読み込む実装になっていた（`spikes/map_spike_gl/lib/map_probe_page.dart`）。この不一致のままでは、失敗してもプラグインの能力の問題かハーネスの作りの問題か切り分けられなかった。この誤りの出所は本書 §2.1 の机上調査記述（2026-09-09訂正済み）であり、ハーネス側の独自の不具合ではなかった。**この問題はハーネスをベクタソース対応に修正（別PR #78）したうえで上記の実機検証を行い解消済み。**

### 6.3 T013 / R1: 動的 addSource/addLayer/feature-state

- [x] `addGeoJsonSource` / `addLayer` の動作確認 → **動作する**（§6.4 の第二案ベンチマークが10,000ヘクスのソース追加とレイヤ追加に成功している）
- [x] `feature-state` が実機で動作するか → **`release-0.27.0` で動作する**（§6.4 の第二案が `setFeatureState` を10,000回成功させ、例外なし）。**0.26.2 では Android 未実装**
- [x] feature-state が使えない場合の fog of war への影響 → **当初の想定と逆の結論になった。** 本書は「第一案は feature-state 非依存のため影響は限定的」と書いていたが、実測の結果**第一案が基準未達・第二案のみ合格**となったため、**feature-state は fog of war の成否を左右する必須機能**である

**Android 固有の制約（実装で判明）**: `promoteId` は Web 専用で Android では機能しない（上流 `controller.dart` に明記）。したがって `properties` 内の値を feature id に昇格させる方式は取れず、**各 Feature の直下に整数 `id` を持たせる必要がある**。
→ **地域パック生成（`tools/pack-builder/` ・ Issue #38）は、この id を埋め込む前提で設計する必要がある。**

#### feature_id（H3由来の大きい整数）の実機疎通（2026-09-09実施）

- [x] `feature_id`（H3由来の52bitマスク後の大きい整数）が実機で正しく往復するか →
  **成功（PASS）**。ログ:
  ```
  21:57:12.931891  feature_id疎通: setFeatureState 成功（例外なし）。id=833108588584959
  21:57:12.942696  feature_id疎通: getFeatureStateで読み戻し成功 -> {probed: true}（idが途中で丸められていないことの傍証）
  ```
  52bitマスク後の `feature_id`（833,108,588,584,959）が Dart → MethodChannel → Java →
  MapLibre を往復し、`getFeatureState` での読み戻しまで一致した。どこかで double を
  経由していれば 2^53 の壁で静かに丸められていたはずで、それが起きていないことが実測で
  確認された。**T056（fog of war）の未検証リスクが解消された。**
  - この検証は `tools/pack-builder/verify_feature_id.py` によるオフライン・静的な検証
    （§8.4参照）を補完するもので、§8.4が「H3 index から計算したfeature_idの値そのものの
    性質」（一意性・可逆性・JSON safe integer範囲内か等）を検証しているのに対し、
    こちらは「その値が実際にDart→ネイティブのランタイム経路を実機で往復するか」を
    確認したもの。両者は独立した検証であり、相互参照のため §8.4 側にも本節への参照を
    記載している。

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
- [x] ヘクス1万個開示状態での fps（基準55fps以上） → **第二案の更新ループ中 56.6fps で基準充足**。手動パン・ズーム時の計測は2026-09-09に実施したが、**計測方法の欠陥により判定不能だった**（「未達」ではない。詳細は下記「2026-09-09 追加計測」）
- [x] スタイル再読み込み時のちらつきの有無 → **2026-09-09実施・ちらつきなし（基準達成）**。詳細は下記「2026-09-09 追加計測」
- [x] 基準未達時のフォールバック（第二案）が選択可能か → **選択可能であるだけでなく、第二案が唯一の合格構成であった**

#### 2026-08-14 追加計測: スケール検証（第二案・50,000／100,000ヘクス）

上記は10,000ヘクスでの計測。**地域パックのヘクス数はこれを上回りうる**ため、第二案（feature-state）のスケール限界を追加計測した。計測端末は同じく Pixel 7a。出典: [Issue #24 のコメント（2026-08-14T02:11 / 02:13）](https://github.com/rokusoudo-product/terra-town/issues/24)。

| ヘクス数 | 開示トグル（`setFeatureState`） | ソース構築（`addGeoJsonSource` 等） | 判定 |
|---|---|---|---|
| 10,000 | median 0.3ms / max 37.7ms | 未計測 | PASS |
| 50,000 | median 0.2ms / max 80.2ms / avg 0.5ms | **未計測** | PASS（⚠️開示トグルのみの結果。ソース構築コストは計測されておらず、この PASS を上限の根拠にはできない） |
| 100,000 | — | ①ジオメトリ生成 442.0ms／②`addGeoJsonSource` **6,535.2ms（全体の74%）**／③`addLayer` 7.4ms／④観測ウィンドウ10秒中の maxFrame 1,900.9ms（frames=19・jank=4、ソース追加後の初回描画スパイク）／⑤合計 8,885.5ms | **`OutOfMemoryError` でクラッシュ**（Java ヒープ上限256MBを使い切り）。成功する試行もあるが非決定的であり、上限を超えていると扱うべき |

- **ボトルネックは `addGeoJsonSource`**。Android 側で受け取った GeoJSON を Gson が `FeatureCollection` に展開する処理で、**メインスレッドで実行される**。`maplibre_gl` 0.27.0 の `compute` オフロード（Dart 側エンコードの改善）は Dart 側の処理を対象とするため、**このボトルネックは縮まらない**（Issue #24 コメントの分析）。
- 50,000ヘクスは開示トグルの計測しかしておらず、100,000ヘクスで初めてソース構築コスト（起動時・エリア切替時コスト）を計測した。したがって「50,000で PASS」を「ソース構築を含めて安全」の根拠として扱ってはならない。
- この実測を根拠に、**1ソース（＝1エリア）あたりのヘクス数上限**を `plan.md` §3 に明記した（代表決定 2026-09-07・Issue #49）。詳細は `plan.md` §3 を参照。

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

**ソース構築の一回コストは計測済み**（2026-08-14・上記の「2026-08-14 追加計測」参照）: 100,000ヘクスで `addGeoJsonSource` 6,535.2ms（合計8,885.5ms）・OOMで非決定的。この実測から線形外挿した**暫定上限 30,000ヘクス／1ソース**（起動時・エリア切替時のソース構築2秒以内が主基準）を `plan.md` §3 に明記した。確定は `tools/pack-builder/`（#38）着手時の実機計測で行う（代表決定 2026-09-07・Issue #49）。

#### 2026-09-09 追加計測

Pixel 7a・代表実施。ハーネスは §6.2 の実測に使ったものと同一（`spikes/map_spike_gl`、別PR #78）。

**ソース構築コスト（10,000ヘクス・3回計測）**

| 回 | ①geometry | ②addGeoJsonSource | ③addLayer | ④観測窓2000ms中のmaxFrame | ⑤合計 |
|---|---|---|---|---|---|
| 1 | 49.8ms | 835.2ms | 6.9ms | 629.4ms (frames=61 jank=4) | 1,521.3ms |
| 2 | 66.6ms | 816.9ms | 9.8ms | 604.4ms (frames=60 jank=4) | 1,497.6ms |
| 3 | 51.6ms | 866.7ms | 8.6ms | 590.6ms (frames=60 jank=3) | 1,517.5ms |

上記「2026-08-14 追加計測」に記録済みの 100,000ヘクス時（②=6,535.2ms）と比べ、10,000ヘクスでは②が約830msでほぼ線形。**「ソース構築2秒以内」の基準を10,000ヘクスでは満たす。**

**更新レイテンシ（計測A）の再現 → PASS維持**

| 回 | min | median | max | avg | n | 更新ループ中のフレーム統計 |
|---|---|---|---|---|---|---|
| 1 | 0.2ms | 0.3ms | 50.1ms | 0.9ms | 10000 | frames=505 jank=174 (34.5%) fps=56.4 avgFrame=16.1ms maxFrame=63.3ms |
| 2 | 0.2ms | 0.2ms | 87.9ms | 0.6ms | 10000 | frames=322 jank=34 (10.6%) fps=57.0 avgFrame=14.1ms maxFrame=94.9ms |
| 3 | 0.2ms | 0.2ms | 19.0ms | 0.5ms | 10000 | frames=295 jank=67 (22.7%) fps=59.5 avgFrame=15.5ms maxFrame=95.8ms |
| 4 | 0.2ms | 0.2ms | 59.0ms | 0.4ms | 10000 | frames=262 jank=32 (12.2%) fps=57.9 avgFrame=15.4ms maxFrame=69.4ms |

2026-08-14の記録（median 0.3ms / max 37.7ms）と整合し、**基準「200ms以内」を満たす。**

**手動パン・ズーム時のfps → 判定不能（計測方法の欠陥。「未達」ではない）**

```
21:51:45.888  手動fps計測: 開始
21:52:07.905  手動fps計測: 停止。frames=716 jank=51 (7.1%) fps=32.5 avgFrame=11.5ms maxFrame=115.8ms
```

**この32.5fpsは「基準55fps未達＝FAIL」を意味しない。** 計測方法の欠陥である:

- 経過時間は22.0秒、`frames=716` → `frames ÷ 経過秒 = 32.5`
- しかし `avgFrame=11.5ms` は**約87fps相当**であり、`jank`率も7.1%しかない
- **指を止めている間はフレームが生成されない**ため、当時の「frames ÷ 経過秒」という定義では**「描画が遅い」と「操作していない」が区別できない**（716×11.5ms≒8.2秒で、22秒中およそ14秒が無操作だった計算になる）

**したがって「未達」ではなく「この指標では判定できない」として記録する。** 性能問題があるとは読めない（むしろavgFrameからは基準を満たす可能性が高いことが伺える）。ハーネス側の判定指標を修正（別PR #78・`activeFps`という無操作区間を除いた指標を追加）したうえでの再計測が必要。

**スタイル再読み込み時のちらつき → ちらつきなし（基準を満たす）。ただし別の設計論点2件が判明**

```
22:13:51.965  スタイル再読み込み開始: setStyleを呼び出しました
22:13:52.105  onStyleLoadedCallback発火（setStyleから141.0ms経過）
22:13:54.883  フォグ再構築完了（例外なし）。setStyleから合計2915.0ms。
              frames=60 jank=4 (6.7%) fps=20.6 avgFrame=22.8ms maxFrame=559.2ms。
              開示状態はリセットされ全面フォグに戻っている（既知の制約）
```

代表の目視所見: 「画面の切り替えタイミングは分かるが、霧が消えて出直すように見えたり、画面が点滅するような感じはしなかった」。**判定: `plan.md` §8の「スタイル再読み込み時のちらつきなし」という基準は満たしている。**

ただし、ちらつきとは別に次の2点が設計上の論点として新たに判明した（実装方針は本書のスコープ外。`plan.md`・`docs/terrain.md`側の検討が必要）:

1. **フォグ再構築に約2.9秒かかり、その間 maxFrame 559.2ms（fps 20.6）。** 「ちらつき」ではないが体感としては一時停止に近い。製品でスタイル再読み込みが起きる場面（例: テーマ切替・昼夜切替）を作る場合、この2.9秒をどう扱うかの設計が要る。
2. **`setStyle` で開示状態（feature-state）が失われる。** したがって開示状態は地図側の状態ではなく永続ストレージを正とし、スタイル再読み込み後に復元する必要がある。`docs/terrain.md` / `plan.md` §8 の実装方針に影響しうる（本PRでは`plan.md`は変更していない。代表判断のうえ別途反映）。

**基盤地図を重ねての再計測 → 未実施のまま**

タブ③は合成データの1万ヘクスが画面全体を覆うため、代表から「地図が表示されていない」という報告があった。これは下記「残る未計測事項」に既記載の残課題「基盤地図重ね再計測」と同じ事象であり、**引き続き未実施**（ハーネス側にはこの見た目が既知の事象である旨をREADMEに追記した。別PR #78）。

#### 残る未計測事項

- jank率 59.7%（avgFrame 19.8ms）。60Hz の閾値16.67msをわずかに超えるフレームが多い。体感上は問題にならない水準と考えられるが、**基盤地図タイルを重ねた状態での再計測が望ましい**（2026-09-09時点でも未実施。上記「2026-09-09 追加計測」参照）
- 手動パン・ズーム時の fps（plan.md §8 の「1万ヘクス開示状態でのパン/ズーム55fps」の厳密な検証）→ **2026-09-09に計測を試みたが計測方法の欠陥により判定不能。ハーネス側の判定指標修正（別PR #78）後の再計測が必要**

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

## 8. `tools/pack-builder/` 最小プロトタイプ（R4・Issue #38・2026-09-08 実施）

本節は Issue #38「[Spike] pack-builder 最小プロトタイプで地形属性の事前計算を1エリア分検証する」の実施記録。上記§1〜§7が地図の**表示側**（R1・R2）の検証であるのに対し、本節はパックの**生成側**（R4）の検証であり対象・合格基準は独立している。

### 8.0 実施環境・対象エリア

- 実施日: 2026-09-08
- 実施環境: WSL2 (Ubuntu-24.04) / Python 3.12.3
- 対象エリア（**仮座標**。2026-08-11 代表回答「代表の生活圏の確定を待たず、他の代替地域を仮座標として先に通してよい」に基づく）: 埼玉県狭山市〜東京都瑞穂町にまたがる狭山湖（山口貯水池）周辺、約5.05km×5.00km（`tools/pack-builder/config.py` の bbox）。
  - 選定理由: plan.md §15「水辺・緑地・農地・市街が混在する範囲」を満たす。実データ確認の結果、水辺（狭山湖・ため池）、森（狭山丘陵の樹林地）、農地（狭山茶の茶畑ほか）、市街（工場・小売店舗・住宅地周辺）が実在することを確認済み（§8.5）。
  - **本番のバーティカルスライス対象エリア（代表の生活圏）とは異なる**。確定後に差し替えて再生成すること。

### 8.1 パイプライン構成・使用ツール・所要時間・出力サイズ

パイプライン: `Geofabrik日本(関東)抽出 → osmium extractでbbox切り出し → pyosmiumでタグ別ジオメトリ抽出 → 優先順位判定 → 細分グリッドセルに投影 → H3ヘクスへ多数決集約 → SQLite出力`

| ステップ | ツール/バージョン | 所要時間 | 入出力サイズ |
|---|---|---|---|
| 1. 関東地方OSM抽出のダウンロード | `curl` ← Geofabrik `asia/japan/kanto-latest.osm.pbf` | 2分8.7秒（回線依存・約3.9MB/s） | 499,988,747 bytes（約477MiB） |
| 2. bboxでの切り出し | `osmium-tool` 1.16.0（libosmium 2.20.0）・`-s smart` 戦略 | 4.9秒 | 出力 1,104,661 bytes（約1.05MiB）。node=173,257 way=25,650 relation=204 |
| 3. 地形分類（cell_terrain生成〜hex_terrain集約〜SQLite書き出し） | `classify_terrain.py`（pyosmium 4.3.1・h3 4.5.0・shapely 2.1.2・numpy 2.5.3、すべてPython 3.12.3） | 6.3〜6.6秒（3回実行の範囲） | 出力 `pack.sqlite` 65,945,600 bytes（約62.9MiB）。内訳: `cell_terrain` 1,012,011行（5m四方セル）・`hex_terrain` 13,106行 |

- **`hex_terrain` テーブルだけを残した場合のサイズ**（`cell_terrain` を落として `VACUUM`）: **761,856 bytes（約744KiB）**。`cell_terrain` は生成過程の中間データであり、実際に地域パックへ同梱する必要があるのは `hex_terrain`（＋行政区域・POI等の他テーブル）である可能性が高い。同梱可否は plan.md §3.2 のパック内容物設計で改めて判断すること。
- **参考値（plan.md §3.5 のヘクス数上限との関係）**: 今回の解像度11・約25.3km²のエリアで13,106ヘクス。単純比例すると、暫定上限30,000ヘクス/ソース（plan.md §3.5）に達するのは約57.9km²相当のエリア。実際の密度は地形の混み具合（ヘクス境界の扱い等）で変動するため参考値に留める。§3.5 の30,000ヘクス規模での実機計測（Android実機でのソース構築時間）自体は本Issueのスコープ外（`app`/`location`のビルド・実機計測は#24系のスコープ）のため未実施。必要であれば別Issueで対応すること。

### 8.2 H3 解像度の実測選定（docs/terrain.md §3.1 に反映済み）

docs/terrain.md §3 の「対辺 約50m」に最も近い H3 解像度を、`h3` (Python) 4.5.0 の `average_hexagon_edge_length` と、対象エリア（bbox中心座標: 緯度35.79, 経度139.38）の実セルの実際の境界（`cell_to_boundary`）から算出した対辺距離（対辺中点間の測地距離、WGS84半径6,371,008.8mで算出）の両方で比較した。再現用スクリプト: `tools/pack-builder/h3_resolution_survey.py`（実行結果は下表と完全一致することを確認済み）。

| 解像度 | 平均辺長(m) | 平均対辺(m)=辺長×√3 | 実測対辺(m) | \|実測-50m\| |
|---:|---:|---:|---:|---:|
| 0 | 1,281,256.0110 | 2,219,200.5086 | 2,176,903.0633 | 2,176,853.0633 |
| 1 | 483,056.8391 | 836,678.9883 | （五角形セル・N/A注1） | — |
| 2 | 182,512.9565 | 316,121.7137 | 303,724.1341 | 303,674.1341 |
| 3 | 68,979.2218 | 119,475.5168 | 114,015.6960 | 113,965.6960 |
| 4 | 26,071.7597 | 45,157.6124 | 43,214.0030 | 43,164.0030 |
| 5 | 9,854.0910 | 17,067.7863 | 16,350.3050 | 16,300.3050 |
| 6 | 3,724.5327 | 6,451.0798 | 6,179.8391 | 6,129.8391 |
| 7 | 1,406.4758 | 2,436.0875 | 2,336.2928 | 2,286.2928 |
| 8 | 531.4140 | 920.4361 | 883.1121 | 833.1121 |
| 9 | 200.7861 | 347.7718 | 333.7810 | 283.7810 |
| 10 | 75.8638 | 131.3999 | 126.1564 | 76.1564 |
| **11** | **28.6639** | **49.6473** | **47.6828** | **2.3172** |
| 12 | 10.8302 | 18.7584 | 18.0224 | 31.9776 |
| 13 | 4.0920 | 7.0876 | 6.8118 | 43.1882 |
| 14 | 1.5461 | 2.6779 | 2.5746 | 47.4254 |
| 15 | 0.5842 | 1.0118 | 0.9731 | 49.0269 |

注1: 解像度1でこの代表点が属するセルはH3全体で12個だけ存在する五角形セル（H3は各解像度に必ず12個の五角形を持つ）に当たり、本スクリプトの「対辺中点間距離」の算出方法（6頂点前提）が使えないため計測をスキップしている（解像度選定の結論には影響しない。他の解像度はいずれも六角形セルで計測できている）。

**解像度11を採用**。理由と差の許容については docs/terrain.md §3.1 に記載済み。

### 8.3 H3 ライブラリのバージョンと Python/Dart 互換性

| 言語 | パッケージ | バージョン | H3コアAPI世代 | 確認方法 |
|---|---|---|---|---|
| Python | `h3` (h3-py) | **4.5.0** | v4（`latlng_to_cell`/`cell_to_latlng`/`polygon_to_cells`等） | `pip show h3`・実際のAPI呼び出しで確認 |
| Dart | `h3_dart` | **0.7.0**（`festelo/h3_dart`） | v4相当（`geoToCell`/`cellToGeo`/`polygonToCells`等。関数名はv4体系、`H3Index`型は`BigInt`） | GitHub `festelo/h3_dart` の `h3_common/lib/src/h3.dart` を参照。バンドルするH3 C コアのgit submodule（`h3_ffi/c/h3`）は commit `4d22db7`を指しており、`gh api repos/uber/h3/compare/...`で確認したところ **H3公式 `v4.2.1` より後・`v4.3.0` より前**（`v4.2.1...4d22db7`が ahead 11 commits、`v4.3.0...4d22db7`が behind 7 commits）で、H3 v4世代のAPI・挙動を持つバージョンである |

- **重要な確認事項**: H3 は v3→v4 でAPIの命名・一部挙動が変わっている（例: v3の`geoToH3`/`h3ToGeo`/`polyfill` → v4の`latLngToCell`/`cellToLatLng`/`polygonToCells`）。今回確認したPython `h3` 4.5.0・Dart `h3_dart` 0.7.0 は**いずれもv4世代のAPI**であり、関数名の体系が一致していることをソースコードレベルで確認した（Pythonは実行確認、Dartはリポジトリのソース確認）。
- H3インデックスの値そのものはアルゴリズム仕様（H3公式仕様）に基づく決定論的な計算であり、同一世代（v4）の実装であれば言語が異なっても同じ緯度経度・同じ解像度から同じインデックス値になる設計。今回はPython側での生成・検証のみを行っており、**Dart側（`location/`）での実装時に、実際に同じ緯度経度から同じ整数が得られることをユニットテストで確認すること**を推奨する（本Issueのスコープ外。`location/`実装時のTODOとして残す）。
- Dart側の `H3Index` は `BigInt`（Dartは任意精度整数のため、64bit H3 indexをそのまま保持でき、JSON化しない限り精度の問題は発生しない）。JSON化（GeoJSON feature id）が必要になる境界でのみ§8.4の52bitマスクが必要になる。
- `h3_dart` の `geoToCell(GeoCoord geoCoord, int resolution)` の引数 `GeoCoord` はソースコード（`h3_common/lib/src/models/geo_coord.dart`）を確認済み。`const GeoCoord({required double lon, required double lat})` という名前付き引数のコンストラクタであり、docs/terrain.md §4.3 に記載した `GeoCoord(lat: lat, lon: lon)` という呼び出し例はこの定義と一致する（名前付き引数のため順序は問わない）。

### 8.4 H3 index → 地図 Feature `id` の橋渡し方式の検証（docs/terrain.md §4.4 に反映済み）

採用方式（下位52bitマスク）・退けた3案とその理由は docs/terrain.md §4.4 に記載した。ここでは実測による検証結果を記録する。検証は `tools/pack-builder/verify_feature_id.py` として実装し、実際に生成したパック（狭山湖周辺・解像度11・13,106ヘクス）の `hex_terrain` に対して実行した。

> **本節は「feature_idの値そのものの性質」（一意性・可逆性・JSON safe integer範囲内か）を
> オフラインで静的に検証したもの。実際にこの値がDart→MethodChannel→Java→MapLibreの
> ランタイム経路を実機で往復するかは別途 §6.3「feature_id（H3由来の大きい整数）の実機疎通
> （2026-09-09実施）」で確認済み（PASS）。両者は相互補完の関係にある。**

| 検証項目 | 結果 |
|---|---|
| `hex_id`（H3 index）が2^63未満か（SQLite INTEGER(64bit符号付き)にそのまま格納可能か） | OK（最大値 626,833,456,793,083,903） |
| 全ヘクスの上位12bit（reserved+mode+resolution）が単一の定数か | OK（`139` の1種類のみ。解像度11・cellモードで固定） |
| SQLite保存済み`feature_id`と`hex_bridge.h3_to_feature_id()`の再計算が一致するか | OK |
| `feature_id`（下位52bitマスク後）が2^53-1未満か（JSON safe integer） | OK（最大値 833,108,588,584,959 < 9,007,199,254,740,991） |
| `feature_id` の衝突（13,106ヘクス中） | OK（**0件**。全ヘクスで一意） |
| `(header << 52) \| feature_id` による `hex_id` への復元（可逆性） | OK（全件一致） |

- **書き込み時点でも二重に保証**: `classify_terrain.py` が `hex_terrain.feature_id` に `UNIQUE INDEX`（`idx_hex_terrain_feature_id`）を張っており、万一衝突するデータが生じた場合はSQLiteの制約違反でパック生成自体が失敗する（実行時の静かな上書き・データ欠落を防ぐ）。
- 上記の再現は `./.venv/bin/python verify_feature_id.py` で誰でも実行できる。

### 8.5 抜き取り検証（地形タイプ別・実地図との突き合わせ）

生成した `hex_terrain`（狭山湖周辺・cell_size=5m・解像度11）から、地形タイプごとにセル数最大（＝ヘクス内で最も支配的）のヘクスを抽出し、そのヘクス中心の緯度経度を OpenStreetMap（`https://www.openstreetmap.org/`）で実際に目視確認した。

| 地形タイプ | 該当ヘクス数 | サンプル座標 | OSM実地図での確認内容 | 判定 |
|---|---:|---|---|---|
| 海 | 0 | — | 対象エリアが内陸のため該当なし（想定どおり。§8.7の既知の簡略化参照） | 対象外 |
| 水辺 | 518 | 35.777175, 139.407368 | 狭山湖（山口貯水池）の水面。画面全体が水域 | ✅ 期待どおり |
| 水辺 | 518 | 35.775607, 139.404223 | 同上、湖の別地点。画面全体が水域 | ✅ 期待どおり |
| 山 | 3 | 35.778478, 139.357573 | 「愛石山 131m」の山頂ノード周辺。地図上は森（樹林）に囲まれた一地点 | △ タグ上は`natural=peak`で正しく判定しているが、実態は森の中の一地点（§8.7で詳述） |
| 山 | 3 | 35.775775, 139.368121 | 「六道山 192m」の山頂ノード周辺。地図上は公園・樹林の緑地内 | △ 同上 |
| 森 | 4,203 | 35.779426, 139.356479 | 樹木記号が密集した緑地（狭山丘陵の樹林） | ✅ 期待どおり |
| 農地 | 1,846 | 35.797119, 139.352769 | 淡黄色・点線区画（OSM標準スタイルの農地表現）の区画地 | ✅ 期待どおり |
| 市街 | 701 | 35.802152, 139.356865 | 「中村屋武蔵工場」の敷地（`landuse=industrial`、紫色表示） | ✅ 期待どおり |
| 空き地 | 5,835 | 35.792228, 139.355939 | 幹線道路交差点付近。コンビニ等はあるが landuse ポリゴンなし（未分類地としてフォールバック） | ✅ ルールどおり（§5「道路・未分類地含む」のフォールバック仕様に合致。体感は「街」に見えるが OSM 上のタグ被覆がないため空き地判定になる点は既知の限界） |

- **合格基準の判定**: docs/terrain.md §2 の7地形タイプのうち、対象エリアに実在する6タイプ（海を除く）すべてで抜き取り検証を実施し、いずれも§5の優先順位ルールどおりに分類されていることを確認した（「山」については判定ロジック自体は正しく動作しているが、§8.7・docs/terrain.md §5.1のとおり、実用上の妥当性に検討の余地があることが判明した）。「海」は対象エリアに実在しないため検証対象外（§8.7）。

### 8.6 決定論の検証（plan.md §4 の前提）

`tools/pack-builder/verify_determinism.py` で、同一入力（同一 `area.osm.pbf`・同一設定）から `classify_terrain.py` を2回実行し、`hex_terrain` テーブルの `(hex_id, terrain_type, feature_id, cell_count)` の集合を比較した。

- 1回目: 13,106行・生成6.463秒・出力65,945,600 bytes
- 2回目: 13,106行・生成6.327秒・出力65,945,600 bytes
- **対称差分: 0件（完全一致）→ PASS**

決定論が成り立つ理由: (1) OSM入力ファイルが同一、(2) `shapely.union_all`によるジオメトリ合成はGEOSの決定論的な演算、(3) H3インデックス計算は緯度経度・解像度のみに依存する純関数、(4) 多数決のタイブレークは優先度番号という決定論的な規則、(5) SQLiteへの書き込みを`hex_id`昇順にソートしている。乱数は一切使用していない。

### 8.7 既知の簡略化・スコープ外事項・未解決の質問（要確認）

**判定ルールを修正した事項（docs/terrain.md §5に反映済み）**:
- `landuse=retail` を市街（優先度6）に追加した（§8.5・docs/terrain.md §5.1参照）。

**本プロトタイプでの意図的な簡略化（コード側コメントに記載済み。`tools/pack-builder/terrain_rules.py`）**:
- 「海」の`natural=coastline`（海岸線）からの海面ポリゴン合成は未実装。明示タグ（`natural=water`&`water=sea`・`place=sea`・`natural=bay`）のみで判定している。対象エリアが内陸のため今回の検証結果には影響していないが、**沿岸部を含むエリアでの本番実装（T039）では別途の設計が必要**（osmcoastline等の専用処理、またはPlanetiler内蔵の海岸線処理に委ねる想定）。
- `waterway=river`/`stream`/`canal`（線）は固定5mバッファで面近似している。実際の川幅は反映していない。
- `building=*`の密度による市街判定（§5表の「一定密度以上」）は未実装（具体的なしきい値がdocs/terrain.md上も未定義のため）。`landuse=residential`等のポリゴンタグのみで判定。
- `natural=peak`（山頂の点）は半径30mのバッファで面近似している。

**要確認（代表確認事項として残す。docs/terrain.md §5.1にも記載）**:
- **「山」判定の実用上の妥当性**: §8.5のとおり、実データでは樹林に覆われた山（丘陵）の大部分が「森」に分類され、「山」になるのは山頂ノード（点）の周辺だけという結果になった。OSMのタグ体系上、樹林に覆われた山体全体を面として「山」にタグ付けする慣行がないため、この結果は§5のルール自体の欠陥というより構造的な制約に近い。石・鉄の産出地形として「山」を独立させたい場合、将来的に標高・傾斜データ（DEM）の導入を検討する必要があるかもしれない。**本プロトタイプではルールを変更せず、代表確認事項として残す。**
- **plan.md §3.5（1ソースあたり30,000ヘクス上限）の実機確定**: plan.md §3.5は「確定は`tools/pack-builder/`（Issue #38）着手時に30,000ヘクス規模で実機計測して行う」としているが、これはAndroid実機でのMapLibreソース構築時間の計測（#24系のスコープ）であり、本Issue（Pythonでの地形属性事前計算パイプライン）の範囲外の作業である。§8.1の参考値（25.3km²で13,106ヘクス）は算出したが、実機計測そのものは別途実施が必要。
- **plan.md §3.5「分割方式の詳細設計は`tools/pack-builder/`（#38）で決定する」は未着手**: 1エリアのヘクス数が上限を超えた場合の「エリア分割」または「ビューポート単位の分割ロード」の詳細設計は、本プロトタイプでは対象エリアが上限（30,000ヘクス）を大きく下回った（13,106ヘクス）ため検討していない。T039（Planetiler本体実装）で対象エリアが拡大する際に改めて設計が必要。
- **bboxの矩形境界でヘクスが欠けるデータ品質上の注意**: 本プロトタイプは対象エリアを単純な緯度経度矩形（bbox）でグリッド化しているため、bbox境界をまたぐヘクスは境界内側のセルしか投票に参加できず、`cell_count`が内側のヘクス（本プロトタイプでは典型的に82セル）より少なくなる。境界ヘクスは`terrain_type`が本来より不確からしい状態で確定してしまう可能性があるため、本番実装では対象エリアをH3セル集合（またはbboxをヘクス1個分以上拡張した範囲）から生成し、境界での多数決精度を担保する設計にすること。**`feature_id`/`hex_id`自体は座標のみで決まる純関数のため、この問題は不変性（§4.4）には影響しない**（あくまで境界ヘクスの地形タイプ判定精度の問題）。
- **`HexId`（`packages/core/lib/src/geo/hex_id.dart`）のdocstringが本Issueの決定と食い違っている**: 本Issueは`tools/pack-builder/`のみが対象で`core`のコード変更は意図的にスコープ外としたため、`hex_id.dart`自体は未修正のまま残している。ただし`toInt()`のdocstring「地図 Feature の整数 `id` に渡すための明示的な取り出し。現状は`value`と同一」は、本Issueの決定（`feature_id`は`value`の下位52bitマスクであり同一ではない。docs/terrain.md §4.4）と矛盾する記述になった。`location/`実装（#33系のフォローアップIssue）で`HexId`にfeature_id導出のヘルパーを追加する際に、このdocstringも合わせて修正すること。
- **Dart側でのfeature_id伝搬経路は未検証**: Issue #24のfeature-state性能計測は連番の小さい整数（1,2,3,...）で行われており、`feature_id`（本Issueの実測で最大8.33×10^14程度）のような大きな整数が Dart → MethodChannel → Java（Android native）→ MapLibreの経路で精度・型変換上の問題なく伝わるかは未検証。`location/`実装時に確認すること。

### 8.8 地形タイプ7種→5種化後の再生成結果（Issue #70・2026-09-08 実施）

[Issue #70](https://github.com/rokusoudo-product/terra-town/issues/70)「地形タイプから農地・市街を除外し、文明はプレイヤーが建設する形に整理する」（2026-09-08 代表決定）に伴い、`tools/pack-builder/terrain_rules.py` から農地（旧優先度5）・市街（旧優先度6）の判定を削除し、これらのタグをフォールバックの空き地に統合した。**§8.0〜§8.7 は7種時点（Issue #38）の記録としてそのまま残し、本節に5種化後の再生成結果を追記する。**

#### 8.8.1 再生成条件（§8.0〜§8.1と同一入力）

- 入力: `tools/pack-builder/data_cache/area.osm.pbf`（PR #69 で生成・保存済みのキャッシュをそのまま再利用。**§8.0の対象エリア・§8.1のosmium extract結果と同一ファイル**）
  - SHA256: `9a66e066b0d4299932768ee06ba474262179d94e1ae11990d0431a327ad527a3`
- 変更点: `terrain_rules.py` のみ（優先度5=農地・優先度6=市街の`TagRule`と`classify_area_tags`の分岐を削除。優先度番号は 1=海・2=水辺・3=山・4=森・5=空き地〔フォールバック〕に振り直し）。`config.py`・グリッド生成・H3集約ロジック（`classify_terrain.py`）は無変更。
- 実行環境: WSL2 (Ubuntu-24.04) / Python 3.12.3（§8.0と同一。`osmium` 4.3.1・`h3` 4.5.0・`shapely` 2.1.2・`numpy` 2.5.3）
- 実行コマンド: `./.venv/bin/python classify_terrain.py`（`tools/pack-builder/README.md` の手順どおり。ステップ1・2〔ダウンロード・extract〕はキャッシュ済みのためスキップ）
- 生成結果: cells=1,012,011・hexes=13,106（旧・7種時点と同数。入力・グリッド・H3解像度が同一のため当然の一致）・生成時間 5.79秒・出力サイズ 66,600,960 bytes

#### 8.8.2 新・地形分布（5種）と旧分布（7種・§8.0-§8.1）の比較

対象エリア: 埼玉県狭山市〜東京都瑞穂町・狭山湖周辺、約25.3km²・H3解像度11・13,106ヘクス（§8.0と同一エリア・同一ヘクス集合）。

| 地形 | 旧ヘクス数（7種・PR #69） | 旧割合 | 新ヘクス数（5種・Issue #70） | 新割合 | 増減 |
|---|---:|---:|---:|---:|---:|
| 空き地 | 5,835 | 44.5% | **8,407** | **64.1%** | +2,572 |
| 森 | 4,203 | 32.1% | 4,180 | 31.9% | −23 |
| 農地 | 1,846 | 14.1% | （廃止・空き地に統合） | — | −1,846 |
| 市街 | 701 | 5.3% | （廃止・空き地に統合） | — | −701 |
| 水辺 | 518 | 4.0% | 516 | 3.9% | −2 |
| 山 | 3 | 0.02% | 3 | 0.02% | 0 |
| 海 | 0 | 0% | 0 | 0% | 0 |
| **合計** | **13,106** | **100%** | **13,106** | **100%** | 0 |

- **空き地の増分（+2,572）が旧・農地（1,846）＋旧・市街（701）＝2,547 と一致しない理由**: `classify_cells` はセル単位で農地/市街の判定を行わなくなっただけで、他の地形（森・水辺・山・海）の判定ロジックは変更していない。そのため、あるヘクス内の森・水辺・山・海それぞれの得票数は旧集計と新集計で**変化しない**（森が新たに票を得ることはない）。変化するのは、旧集計で農地/市街に入っていた票が新集計ではすべて空き地に加算される点のみである。したがって、旧集計で森または水辺がヘクス内の最多得票だったが、農地/市街の票を吸収した空き地票がそれを上回った場合にのみ、そのヘクスの多数決結果が森/水辺→空き地に切り替わる（逆方向、すなわち森/水辺が新たに勝つケースは構造上発生しない）。実測では森が4,203→4,180（−23ヘクス）、水辺が518→516（−2ヘクス）とこの逆転が計25ヘクスで発生しており、空き地の増分2,572から差し引くと 2,572−25=2,547 となり、旧・農地+市街のヘクス数 1,846+701=2,547 と一致する（合計の整合が取れている）。
- **森・水辺・山・海の増減方向は「減少または不変」のみ**（上記のとおり、判定ロジック上これらの地形が新たに票を獲得することはなく、農地/市街の票を吸収した空き地票に逆転されて減る方向にしか動かない）。これは事前の期待どおりの挙動であり、逆方向（自然地形が増加）が起きていないことをもって、ルール変更が意図どおりであることの確認とする。
- **合格基準の判定**: 事前の想定「農地・市街を除外すると19.4%が空き地に回り、建設可能地が44.5%→約64%に増える」（Issue #70本文）に対し、実測は **44.5% → 64.1%** となり、想定どおりの結果が得られた。

#### 8.8.3 検証スクリプトの再実行結果

- `verify_determinism.py`: 2回生成の対称差分 **0件（PASS）**。5種化後も決定論は維持されている（1回目 5.788秒、2回目 5.700秒。いずれも13,106行・66,600,960 bytes）。
- `verify_feature_id.py`: `hex_id`最大値 626,833,456,793,083,903（2^63未満）・ヘッダビット単一定数(139)・`feature_id`再計算一致・`feature_id`最大値 833,108,588,584,959（2^53-1未満）・衝突0件・可逆性OK。すべて§8.4と同じ結果（`hex_id`/`feature_id`は座標のみで決まる純関数であり、地形タイプの判定ルール変更の影響を受けないため、7種時点と同じ検証結果になることは期待どおり）。
- `spot_check_samples.py`: 検出された地形タイプは `['forest', 'mountain', 'vacant_lot', 'waterside']`（`sea`は該当ヘクス0で未検出、想定どおり）。旧・農地サンプル座標（35.797119, 139.352769）が新集計では `vacant_lot` として抽出されており、§5の設計どおり農地タグが空き地にフォールバックしていることを実データで確認した。

#### 8.8.4 塩の供給源（内陸スタート）について

§8.5で確認したとおり対象エリアは内陸のため海ヘクスは0件（旧・新とも変わらず）。地形タイプが5種になったことで**海が唯一の塩の供給源**になるが、対象エリアのように内陸スタートでは徒歩到達可能な範囲に海ヘクスが存在しない可能性が高い。この論点は本Issue（#70）のスコープではなく、**[Issue #72](https://github.com/rokusoudo-product/terra-town/issues/72)（石・鉄・塩の供給源）に統合して扱う**（2026-09-08 代表決定。`docs/terrain.md` §6.1参照）。

### 8.9 山の判定タグ拡張（Issue #71・2026-09-08 実施）

[Issue #71](https://github.com/rokusoudo-product/terra-town/issues/71)「山の判定ルールを拡張して実データでの出現率を確保する」の実施記録。§8.5・§8.7・§8.8で判明した「山の出現率が13,106ヘクス中3ヘクス（0.02%）のまま」という問題に対応する。

**2026-09-08 代表決定（Issue #71コメント）に基づく本節の位置づけ**: 目標出現率は設けず、**OSMタグ拡張だけで到達できる山の出現率を実測すること**が本Issueの成否基準である。不足分の対応は[Issue #72](https://github.com/rokusoudo-product/terra-town/issues/72)に委ねる。DEM導入は投機的に行わず、タグ拡張の実測結果を踏まえて要否を結論として記録する。検証エリアはPR #69・#73と同じ狭山湖周辺とし、`tools/pack-builder/data_cache/area.osm.pbf`（SHA256: `9a66e066b0d4299932768ee06ba474262179d94e1ae11990d0431a327ad527a3`。§8.8.1と同一ファイル）を再利用して前後比較する。

#### 8.9.1 追加した判定タグと、検証エリアでの実データ調査

`docs/terrain.md` §5・`tools/pack-builder/terrain_rules.py` に以下を追加した。

| 追加タグ | ジオメトリ種別（OSM wiki準拠） | 扱い | バッファ半径 |
|---|---|---|---|
| `natural=hill` | 点のみ | `MOUNTAIN_SUMMIT_POINT_RULES`（`natural=peak`と同枠） | 30m（`MOUNTAIN_PEAK_BUFFER_M`。既存の`natural=peak`用の値をそのまま流用。§8.9.3参照） |
| `natural=cliff` | 点・線・面いずれも可 | 面: `MOUNTAIN_AREA_RULES`にそのまま追加。点: `MOUNTAIN_FEATURE_POINT_RULES`。線: `MOUNTAIN_LINE_RULES` | 点・線とも10m（`MOUNTAIN_SMALL_FEATURE_BUFFER_M`。新設） |
| `natural=rock` | 点・面 | 面: `MOUNTAIN_AREA_RULES`にそのまま追加。点: `MOUNTAIN_FEATURE_POINT_RULES` | 点10m |
| `natural=ridge` | 線のみ | `MOUNTAIN_LINE_RULES` | 10m |

- ジオメトリ種別はOSM wikiの `Key:natural` を参照して確認した（`natural=hill`は点のみ、`natural=ridge`は線のみ、`natural=cliff`は点/線/面、`natural=rock`は点/面）。
- **バッファ半径の使い分けの根拠**: `natural=peak`/`natural=hill`（summit系）は山・丘の**頂上**を表す点であり、既存の30mバッファ（§8.7・docs/terrain.md §5.1）をそのまま踏襲する。一方 `natural=cliff`（点表記）・`natural=rock` は単体の岩・短い崖面という**局所的でsummitより小さい地物**であるため、既存のwaterway線バッファ（5m）より大きく、summitバッファ（30m）よりは明確に小さい値として **10m** を新設した（`MOUNTAIN_SMALL_FEATURE_BUFFER_M`）。これは実測データに基づく値ではなく、地物の性質から見た相対的な大小関係のみに基づくオーダー感の判断である（後述のとおり、検証エリアには該当データがなく実測での裏付け自体ができていない）。線表記の`natural=ridge`・`natural=cliff`も同じ理由で同じ10mバッファとした。
- **検証エリアでの実データ調査（`tools/pack-builder/data_cache/area.osm.pbf`をpyosmiumで直接スキャン）**: node・way・relationの3種別すべてについて `natural=*`・`landuse=*` タグの値ごとの出現数を集計した結果、以下の通りだった。

  | タグ | node | way（開いた線） | relation |
  |---|---:|---:|---:|
  | `natural=peak` | 2 | 0 | 0 |
  | `natural=hill` | 0 | 0 | 0 |
  | `natural=ridge` | 0 | 0 | 0 |
  | `natural=cliff` | 0 | 0 | 0 |
  | `natural=rock` | 0 | 0 | 0 |
  | `natural=bare_rock` | 0 | 0 | 0 |
  | `natural=scree` | 0 | 0 | 0 |
  | `landuse=quarry` | 0 | 0 | 0 |

  **検証エリア（狭山湖周辺）には、既存の`natural=peak`（2件）を除き、山判定に使えるどのタグも1件も存在しない。** これは今回追加した4タグ（`hill`/`ridge`/`cliff`/`rock`）に限らず、Issue #38時点で既にルールに含まれていた`bare_rock`/`scree`/`quarry`も含めた結果である。

#### 8.9.2 再生成結果：タグ拡張の前後比較

`tools/pack-builder/classify_terrain.py`を変更後のコードで再実行した（入力・グリッド・H3解像度は§8.8.1と同一。`natural=peak`のバッファ半径も30mのまま、§8.9.3参照）。

| 地形 | 拡張前（Issue #70・§8.8） | 拡張後（Issue #71・本節） | 増減 |
|---|---:|---:|---:|
| 空き地 | 8,407（64.15%） | 8,407（64.15%） | 0 |
| 森 | 4,180（31.89%） | 4,180（31.89%） | 0 |
| 水辺 | 516（3.94%） | 516（3.94%） | 0 |
| 山 | 3（0.02%） | 3（0.02%） | 0 |
| 海 | 0（0%） | 0（0%） | 0 |
| **合計** | **13,106（100%）** | **13,106（100%）** | 0 |

- **山の出現率はタグ拡張後も0.02%のまま、1ヘクスも変化しなかった。** §8.9.1の実データ調査のとおり、追加した4タグに該当するOSMデータが検証エリアに存在しないため、この結果は事前の予測どおりである（推測ではなく、実際に再生成して確認した）。
- **他の地形タイプへの侵食も0件**（森・水辺・空き地・海のいずれも1ヘクスも変化していない）。これは「タグ拡張の効果がなかった」ことの裏返しでもあり、当然の結果ではあるが、**「タグを広げた結果、意図せず森を侵食した」という事態が起きていないこと**を実測で確認した、という受け入れ基準への回答でもある。
- **カウントの一致だけでなく行単位でも完全一致を確認した**: `git stash`で変更前のコード（Issue #70時点）に戻し、同一入力から`out/pre71.sqlite`を再生成した上で、変更後の`out/pack.sqlite`と`hex_terrain`テーブルの`(hex_id, terrain_type, feature_id, cell_count)`の集合を比較したところ、**対称差分0件（13,106行完全一致）**だった。地形タイプ別の集計値が偶然一致しただけでなく、個々のヘクスの判定結果も一つも変わっていないことを確認済み。
- 生成時間5.67秒・出力サイズ66,600,960 bytes（§8.8.1の5.79秒・66,600,960 bytesとほぼ同等。コード変更が軽微なタグ追加であるため所要時間に有意な変化はない）。

#### 8.9.3 `natural=peak`バッファ半径の感度分析と「30m据え置き」の判断根拠

`natural=peak`のバッファ半径を拡大すれば、既存の2つの山頂ノードだけからでも山ヘクス数を人為的に増やすことは可能である。この操作が妥当かどうかを判断するため、`tools/pack-builder/peak_radius_sensitivity.py`（再現用スクリプトとして`tools/pack-builder/`に追加）で半径を30〜200mまで変えて再生成し、山ヘクスの増分と森ヘクスの侵食数を実測した。

| 半径 | 山ヘクス数（割合） | 森ヘクス数 | 森からの侵食（30m比） |
|---:|---:|---:|---:|
| 30m（現行） | 3（0.02%） | 4,180 | — |
| 50m | 7（0.05%） | 4,179 | −1 |
| 75m | 20（0.15%） | 4,166 | −14 |
| 100m | 32（0.24%） | 4,155 | −25 |
| 150m | 71（0.54%） | 4,118 | −62 |
| 200m | 128（0.98%） | 4,067 | −113 |

- **半径を6.7倍（30m→200m）にしても、山の出現率は0.98%までしか上がらない**。かつその代償として森113ヘクス（森全体の約2.7%）を侵食する。
- **30m据え置きと結論した理由**:
  1. `natural=peak`ノードにはOSM上、山体の水平方向の広がり（裾野の大きさ）を示す情報が一切付随しない（`ele`タグで標高は分かっても、麓までの距離・傾斜は分からない）。DEM等の傾斜データなしにこの半径を拡大する行為は、実データに基づく判断ではなく**推測**に等しい。
  2. 代表決定（2026-09-08）は「DEMは投機的に導入しない」「目標出現率は先に決めない」の2点を明確にしている。実測不可能な根拠で半径だけを恣意的に拡大し出現率を作ることは、この2つの決定の趣旨（実測に基づかない数値操作をしない）に反する。
  3. 上表のとおり、半径拡大は「山を増やす」効果より「森を侵食する」副作用の方が構造的に避けられない（山の優先度が森より高いため、拡大した円は必ず周囲の森ヘクスから侵食する形になる。§5「優先順位は上が優先」参照）。効果に対して代償が見合う具体的な半径を実データから導出する方法がない以上、現状維持が最も説明可能な選択である。
- 上記の理由により、`MOUNTAIN_PEAK_BUFFER_M`は**30mのまま変更しない**（`tools/pack-builder/terrain_rules.py`のコメント参照）。

#### 8.9.4 DEM（標高・傾斜データ）導入の要否 — 結論: 本Issueでは導入しない

**結論: 導入しない。** 理由と、判断材料として検討した内容は以下のとおり。

- **理由1（代表決定との整合）**: 2026-09-08代表決定は「DEMは投機的に導入しない。まずタグ拡張のみで再生成し、結果を踏まえて要否を判断する」としている。§8.9.1〜§8.9.3の実測により、**タグ拡張自体は実装したが検証エリアには該当データがなく効果を測定できなかった**。これは「タグ拡張を尽くしたが不十分だった」ではなく「この検証エリアの地形（樹林に覆われた低山地）ではOSMタグによる山の表現に構造的な限界があり、これはDEMを持ち込んでも別の問題（後述）が残る」ことを意味する。少なくとも本Issueの実測だけでは「DEMがあれば解決する」という因果関係を実証できておらず、投機的導入を避けるという代表決定の方針に従い見送る。
- **理由2（代替供給源のほうが同じ問題に対して確実に効く）**: §6.1・研究記録§8.8.4のとおり、既に「特定の地形タイプに依存すると内陸スタート等で詰む」という同型の問題が塩（海）についても存在し、その解決は[Issue #72](https://github.com/rokusoudo-product/terra-town/issues/72)（供給源を建物・加工で代替する案B）に委ねられている。石・鉄についても同じ枠組みで解決できる見込みが立っており（本Issueの代表決定コメントが前提としている順序）、DEM導入という重いパイプライン変更を先に行う必然性は低い。
- **判断材料（代表決定コメントの指示に基づく概算）**:
  - **データソース候補**: 国土地理院（GSI）の「基盤地図情報 数値標高モデル」（5mメッシュ、JGD2011）または「標高タイル」（Web用に加工済みのPNG/PNGXタイル、ズームレベル別）。国内エリア限定であれば無料・オープンデータで取得可能（Geofabrik OSMのような単一ファイル一括ダウンロードではなく、対象エリアのタイル/メッシュ単位で個別取得・結合する処理が別途必要）。
  - **パイプライン所要時間への影響（概算）**: 現行パイプラインはOSM抽出〜SQLite出力まで約5.7〜6.5秒（§8.1・§8.8.1・§8.9.2）。DEM導入では追加で (1) 標高タイル/メッシュのダウンロード・キャッシュ、(2) 対象bboxに対応するタイルの結合・座標変換、(3) グリッドセルごとの標高値サンプリングと傾斜（隣接セルとの高低差）の計算、(4) 傾斜しきい値による山判定の追加、という4ステップが増える。(3)は現行の`classify_cells`と同様セル単位の処理（今回1,012,011セル）であり、標高ラスタのサンプリング自体はnumpyベクトル化で数秒程度に収まる見込みだが、(1)(2)のタイル取得・結合はネットワーク帯域・タイル数に依存し数十秒〜数分オーダーになる可能性がある（Kanto PBFダウンロード2分8秒と同程度かそれ以上を見込む）。
  - **実装コスト（概算）**: 新規依存追加（ラスタ処理には`rasterio`等が一般的）、bbox→タイル座標変換・タイル結合ロジックの新規実装、傾斜計算とその判定しきい値の設計・検証（しきい値自体もバランス調整が必要になり、本Issueで扱わない「数値バランスの確定」という別の論点を新たに生む）、決定論の再検証（§8.6の前提はOSM入力のみに依存しているため、DEMソースの版・タイル境界の扱いも決定論に影響しうる）が必要になる。**「山でも茂った森は森のまま」という現在の判定（傾斜のみで判定すると、なだらかで木が生い茂った丘陵地の広い範囲が一律「山」になり、逆に森が過小になる可能性がある）との整合を新たに設計する必要もあり、単純な追加では済まない。**
  - 以上を踏まえ、費用対効果（実装コスト・パイプライン増加時間 対 得られる出現率の改善見込み）の観点からも、現時点でDEM導入を正当化する実測的根拠がないため、**見送る**。将来、山地寄りのエリア（本検証エリアより起伏が大きく、露岩・崖等のOSMタグが実在する地域）を本番対象にする場合や、[Issue #72](https://github.com/rokusoudo-product/terra-town/issues/72)側の対応でも石・鉄の供給が不足すると判明した場合に、改めて検討する。

**山地寄りエリアでの追加検証について（代表決定コメント「必要と判断した場合のみ実施」への回答）**: 本Issueでは追加検証を**実施しない**。理由は、本Issueの成否基準が「同一入力（狭山湖周辺）での前後比較によりタグ拡張の効果を実測すること」（2026-09-08代表決定）であり、その基準に対する結論（§8.9.2: 効果ゼロ）は本検証エリア内で完結して得られているため。ただし、これは**追加したタグ（`hill`/`ridge`/`cliff`/`rock`）が他のどのエリアでも無効という意味ではない**点に注意。§8.9.1の調査はあくまで本検証エリア（樹林に覆われた低山地）の結果であり、露岩・崖が実際に露出するような山がちな地形であれば、これらのタグが実データに存在し、判定に寄与する可能性は残る。この「タグ拡張自体は他地域では効く可能性がある」という主張は未検証の仮説であり、**推測として記録するに留め、本Issueの結論（0.02%据え置き・DEM導入見送り）には影響させていない**。

#### 8.9.5 抜き取り検証（実地図での目視確認）

タグ拡張後も山ヘクスの集合が変化していない（§8.9.2）ため、`spot_check_samples.py`が出力する3件の山サンプルは、地物としては§8.5で確認済みの2つの山頂（愛石山・六道山）に由来する。今回はOpenStreetMap上で改めて3件すべてを目視確認した（PR #69と同じ手法）。

| サンプル座標 | OSM実地図での確認内容 | 判定 |
|---|---|---|
| 35.778478, 139.357573 | 「愛石山 131m」の山頂ノード。周囲は樹木記号が密集した樹林（トレイルの交差点そばの一地点） | △ タグ上は正しく`natural=peak`だが、実態は森の中の一地点（§8.5・§8.7と同じ結論） |
| 35.778595, 139.358057 | 同じ「愛石山」ピークの30mバッファが隣接ヘクスにもまたがった結果の2件目のヘクス。地図上の見た目は上記とほぼ同じ樹林地 | △ 同上（同一地物由来） |
| 35.775775, 139.368121 | 「六道山 192m」の山頂ノード。地図上は「六道広場」という公園（明緑色ポリゴン）の一角で、周囲には樹木記号も点在 | △ 同上。公園として整備された緑地であり、山というより丘陵地の展望スポットに近い |

- **結論**: タグ拡張後も、実地図で見る限り「山」として分類されたヘクスの実態は変わっていない（山頂ノード周辺の樹林・公園緑地）。§8.9.1のとおりデータが存在しない以上これは当然の結果だが、「タグは拡張したが実態の見た目は改善していない」ことを実地図で確認した。

#### 8.9.6 検証スクリプトの再実行結果

- `verify_determinism.py`: 2回生成の対称差分 **0件（PASS）**。タグ拡張後も決定論は維持されている。
- `verify_feature_id.py`: `hex_id`最大値626,833,456,793,083,903（2^63未満）・ヘッダビット単一定数(139)・`feature_id`再計算一致・`feature_id`最大値833,108,588,584,959（2^53-1未満）・衝突0件・可逆性OK。山の分類結果自体が変化していないため、§8.4・§8.8.3と同じ結果になることは期待どおり。
- `spot_check_samples.py`: 検出された地形タイプは`['forest', 'mountain', 'vacant_lot', 'waterside']`（§8.8.3と同一）。

#### 8.9.7 受け入れ基準の充足状況

- [x] `docs/terrain.md` §5の山の判定ルールが拡張され、追加したタグとその根拠が記載されている（§8.9.1、`docs/terrain.md` §5）
- [x] `natural=peak`のバッファ半径について、現行30mを維持するか変更するかが根拠つきで判断されている（§8.9.3。維持と結論）
- [x] DEM導入の要否が結論として記録されている（§8.9.4。導入しないと結論）
- [x] `tools/pack-builder`で再生成し、変更後の山の出現率が実測値として記録されている（§8.9.2。0.02%のまま変化なし）
- [x] 山として分類されたヘクスの実地図での抜き取り確認結果が記録されている（§8.9.5）
- [x] 変更が他の地形タイプの分類を意図せず侵食していないこと（§8.9.2。他地形は1ヘクスも変化なし。行単位の完全一致も確認済み）
- [x] 既存6スクリプト（import direction×2・design tokens×2・toolchain versions×2）がPASS（ローカルで確認済み。CIのgreenはPR作成後にCI実行結果で確認すること）

**【要確認・代表確認事項】`MOUNTAIN_SMALL_FEATURE_BUFFER_M`（10m）について**: `natural=cliff`（点）・`natural=rock`用に新設したこの値は、実測データではなく「summitバッファ(30m)より小さく、waterway線バッファ(5m)より大きい」という地物の相対的な大小関係のみに基づくオーダー感の判断である（§8.9.1参照）。検証エリアに該当データが存在しないため実測での裏付けができておらず、他の値（例: 5m・15m・20m）でも同程度に説明可能である。代表の確認を要する事項として残す。

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
