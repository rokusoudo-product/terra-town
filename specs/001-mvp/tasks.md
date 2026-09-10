---
project: terra-town
doc: tasks.md (実装タスク分解)
feature: 001-mvp
status: in-progress          # Phase 1（T001〜T010）完了・Phase 2以降は未完了（frontmatter status の値そのものの規約はIssue #35で未確定のまま残置。要確認）
created: 2026-07-29
updated: 2026-09-08
related:
  - specs/001-mvp/spec.md
  - specs/001-mvp/plan.md
  - docs/terrain.md
  - docs/buildings.md
  - docs/opening_points.md
  - docs/landmark_objects.md
  - docs/architecture.md
  - DESIGN.md
gate: "ゲート② plan.md 承認済み（2026-07-25）→ 本 tasks.md → 実装"
---

# Tasks: terra-town MVP（001-mvp）

**Input**: `specs/001-mvp/` の設計ドキュメント（spec.md / plan.md）＋ `docs/`（terrain / buildings / opening_points / landmark_objects / architecture）＋ `DESIGN.md`

**Prerequisites**: plan.md（ゲート②承認済み・Flutter＋MapLibre＋地域パック方式）、spec.md（ゲート①承認済み・US-1〜US-4）

**Tests**: 本プロジェクトはテストを**含める**。理由 = plan.md §10 が `PositionProvider` のフェイク実装＋**録画済み歩行ルートのリプレイテスト**を設計の柱に据えており（GPS_ARCHITECTURE の core/location 分離が活きる場所）、資材判定の**決定論**（plan.md §4）も自動テストでしか担保できないため。

**Organization**: タスクはユーザーストーリー単位に整理し、各ストーリーを独立して実装・テスト可能にする。

## Format: `[ID] [P?] [Story] Description`

- **[P]**: 並列実行可（別ファイル・依存なし）
- **[Story]**: 対応ユーザーストーリー（US1〜US4）
- 各タスクに具体的なファイルパスを含める

## Path Conventions（plan.md §2 準拠）

- `app/` — Flutter アプリ（composition root・画面・状態管理）
- `packages/core/` — 【純粋】開示判定・資材・建設・経済・区画集計。**GPS/地図を import しない**
- `packages/location/` — GPS・地図・測位（`location → core` の一方向依存）
- `app/android/` — Kotlin ネイティブ（foreground service・モック検出・歩数・Health Connect）
- `tools/pack-builder/` — 地域パック生成パイプライン（ビルド時のみ・実行時サーバではない）

> ✅ **plan.md §2 との差異は解消済み**（2026-09-08・Issue #35）: plan.md §2 のツリーは `android/` `ios/` をリポジトリルートに置く記述だったが、`flutter create` の標準どおり実際は `app/android/`（`app/ios/` は未着手）。T002 で確定した実態に合わせて plan.md §2 のツリーを修正済み。詳細は `docs/dev-setup.md` §6。

---

## Phase 1: Setup（開発環境・プロジェクト土台）

**Purpose**: ビルドできる空のプロジェクトを用意し、依存方向を仕組みで強制する

> ✅ **完了（2026-09-08 実態反映・Issue #35）**: 旧ブロッカー（SDK 未導入）は解消済み。Flutter 3.44.8 を WSL 側に導入し、`docs/dev-setup.md`（status: approved）に導入手順・実測バージョンを記録済み。Phase 1（T001〜T010）は全項目完了。

- [x] T001 Flutter SDK（stable）と Android SDK/cmdline-tools を導入し、`flutter doctor` が Android toolchain で green になる状態にする（インストール先OS＝Windows/WSL の選択は代表判断。決定を `docs/dev-setup.md` に記録）→ WSL に導入（`docs/dev-setup.md` §1・§2、Flutter 3.44.8）
- [x] T002 `flutter create` で `app/` を生成し、リポジトリ構成を plan.md §2 に合わせる（`app/`・`app/android/`）→ `app/`・`app/android/` を確認（`app/ios/` は未着手）。plan.md §2 は Issue #35 で実態に合わせて修正済み
- [x] T003 [P] `packages/core/` を**純粋 Dart パッケージ**として作成（`packages/core/pubspec.yaml`・Flutter に依存させない）→ `packages/core/pubspec.yaml`（`name: terra_town_core`）に Flutter 依存なしを確認
- [x] T004 [P] `packages/location/` を Flutter パッケージとして作成し、`pubspec.yaml` の dependencies に `core` のみを追加（逆向き依存を作らない）→ `packages/location/pubspec.yaml`（`name: terra_town_location`）の dependencies が `flutter`・`terra_town_core` のみであることを確認
- [x] T005 `app/pubspec.yaml` に `core`・`location` を path 依存で追加し、`flutter build apk --debug` が通ることを確認 → `app/pubspec.yaml` に path 依存あり。`flutter build apk --debug` は CI（`.github/workflows/ci.yml`、PR #45）で実行・green
- [x] T006 [P] `analysis_options.yaml` を**各パッケージ（`app/`・`packages/core/`・`packages/location/`）配下**に配置し、lint ルール（`flutter_lints`/`lints` ベース）を適用する → **実態に合わせて記述を修正（2026-09-08）**。当初案の「リポジトリルートに1つ配置」ではなく、パッケージ単位配置を正とする（ルート集約は現時点でコード変更を伴うため対象外。Issue #35 の未解決の質問を参照）
- [x] T007 **依存方向の機械的強制**: `packages/core/` から `location`・`flutter`・地図SDK を import できないことを検査する仕組みを導入（`import_lint` 等）し、`tools/check_import_direction.sh` として実行可能にする → `tools/check_import_direction.sh` と自己テスト `tools/check_import_direction_test.sh`（Issue #50）が CI に組み込み済み
- [x] T008 [P] GitHub Actions ワークフロー `.github/workflows/ci.yml` を作成（`dart analyze`・`flutter test`・T007 の import 方向チェックを実行）→ 作成済み（import方向チェック・デザイントークンチェック・analyze・testを実行）
- [x] T009 [P] `.gitignore` を Flutter/Android/Dart 向けに整備（`build/`・`.dart_tool/`・`local.properties`・APK 等）→ 整備済み
- [x] T010 [P] `docs/dev-setup.md` を新規作成し、開発環境構築手順（SDK バージョン・Android SDK パス・実機/エミュレータ接続方法）を記録 → 作成済み（status: approved）

**Checkpoint**: 空の Flutter アプリが実機/エミュレータで起動し、CI が green → CI green は確認済み（2026-09-08 時点で main の直近 CI 実行が success）。実機起動は Phase 2 のスパイク（research.md §6.4・Pixel 7a 実機計測）で間接的に裏付けられているが、Phase 1 完了時点そのものでの実機起動確認記録は見当たらないため「要確認」として残す。

---

## Phase 2: 技術検証スパイク（R1〜R6・ブロッキング）

**Purpose**: plan.md §14 のリスクを潰す。**R1 が落ちたら技術スタックの再検討（plan.md 差し戻し）が必要**なため、本フェーズはすべてのユーザーストーリーに先行する

**⚠️ CRITICAL**: 使い捨てコード可（`prototype/spike-*` ブランチ）。合格基準は plan.md §8・§14 の数値を用いる

- [x] T011 Flutter 地図プラグインの候補比較（`maplibre_gl` 系 vs 新 `maplibre`）を実機で行い、選定結果と根拠を `specs/001-mvp/research.md` に記録（plan.md §16 の未確定事項①）→ **完了（2026-09-08・Issue #56 追随、実測は2026-08-13）**: `maplibre_gl`（`release-0.27.0` 相当）を採用。fog of war の合格基準（§6.4）を満たす唯一の構成であるため（research.md §6.1）
- [x] T012 **R1**: 選定プラグインで**ローカル MBTiles 読込**（`mbtiles://`）が動作することを検証し、結果を `specs/001-mvp/research.md` に追記（不可なら PMTiles → ネイティブビュー埋め込みへフォールバック検討）→ **完了（2026-09-09実測・Pixel 7a）**: ハーネスをベクタソース対応に修正（別PR #78）したうえで実機検証し、`VectorSourceProperties(url:)`・`(tiles:)` とも `addSource`/`addLayer` 成功かつ描画も目視確認済み（PASS）。PMTilesフォールバックは不要と判断し未実施（research.md §6.2）。**精度の限界**: url方式追加後にリセットせずtiles方式を重ねたため、最終描画がどちらの方式単独の寄与かは厳密には分離できていない（url方式単独での成立は強い傍証だが断定はしない。詳細はresearch.md §6.2）
- [x] T013 **R1**: 動的 `addSource`/`addLayer` と `feature-state` 操作が API 経由で可能なことを検証し `specs/001-mvp/research.md` に追記 → **完了（2026-09-08・Issue #56 追随、実測は2026-08-13）**: `addGeoJsonSource`/`addLayer` は動作し、`feature-state`（`setFeatureState`）は `release-0.27.0` で Android 実機動作を確認（0.26.2 は Android 未実装）。research.md §6.3
- [ ] T014 **R2**: fog of war の feature-state 方式（plan.md §8 採用方式）で性能基準を計測し、結果を `specs/001-mvp/research.md` §6.4 に記録済み（実測は2026-08-13〜14、追加実測2026-09-09・2026-09-10・2026-09-11）。**完了項目**: 開示1ヘクス追加の更新 **200ms以内** → ✅達成（2026-08-13: max 37.7ms／2026-09-09に10,000ヘクス・4回の再計測でも再現しPASS維持）／ヘクス1万個開示状態での**更新ループ中**fps（基準55fps以上） → ✅達成（56.6fps）／**手動パン・ズーム時のfps（基準55fps以上） → ✅ 2026-09-10に解消・PASS**（`activeFps` 58.3 ≥ 55。2026-09-09は無操作区間を分母に含む計測方法の欠陥により判定不能だったが、PR #78 で `activeFps`〔無操作区間を分母から除く指標〕を導入した結果判定可能になった。従来の `naiveFps` 52.4 では「未達」に見えていた。パン操作は `adb shell input swipe` の連続実行であり人間の手による操作ではない点、**基盤地図タイルを重ねていない**〔合成ヘクスのみ〕点に注意）／ソース構築コスト（10,000ヘクス・2026-09-09に3回計測） → ✅「2秒以内」基準を満たす（②addGeoJsonSourceが約830msでほぼ線形）／**実データ13,106ヘクスでのソース構築コスト（terra-townアプリ本体・PR #109ブランチ・2026-09-10計測） → ✅「2秒以内」基準を満たす（①+②+③=1,808ms。ただし余裕は約10%＝192msのみ）**（2026-09-11に同一条件で5回連続再計測し、1,121〜1,204msで再現。ばらつきは同一セッション内では小さく〔±3.6%〕、セッションをまたぐと約1.6倍〔1,121ms→1,808ms〕になることを確認。原因は未特定・推測の域を出ない）／スタイル再読み込み時のちらつきの有無（2026-09-09実施） → ✅ちらつきなし・基準達成（ただしフォグ再構築に約2.9秒かかる点・`setStyle`で開示状態が失われる点の2つを新たな設計論点としてresearch.md §6.4に記録。plan.md/docs/terrain.mdへの反映は別途代表判断）。**残る未計測項目（research.md §6.4「残る未計測事項」・未チェックのまま残す）**: **基盤地図を重ねた状態での再計測（未実施のまま）**。上記の手動fps PASS・jank率59.7%等の計測は、いずれも基盤地図タイルを重ねていない条件で行われている。※代表決定（2026-09-07）により、部分完了タスクはチェックを入れず注記で完了/残を併記する（全項目完了時のみチェックする）
- [ ] T015 **R3**: Kotlin foreground service で1時間の実歩行（都市部マルチパス含む）を記録し、電池消費と測位品質を計測。距離しきい値の初期値を決定して `specs/001-mvp/research.md` に記録（plan.md §16 の未確定事項②の一部）
- [x] T016 **R4**: `tools/pack-builder/` の試作で OSM 抽出 → 地形事前計算 → SQLite 出力を1エリア分通し、`docs/terrain.md` §5 の判定ルールどおりの分類が出ることを検証（Issue #38・2026-09-08完了。ヘクスID体系にH3を採用し docs/terrain.md §3.1/§4.2-4.4 に確定。検証結果は specs/001-mvp/research.md §8 参照）
- [ ] T017 **R5**: モック位置検出と速度判定（移動平均/カルマン平滑後）を試作し、**正規歩行で報酬没収が起きない**ことを実歩行データで確認
- [ ] T018 [P] **R6**: Health Connect の歩数読み取り疎通とオプトイン UX を検証し、Google Play のヘルスデータ申告要件を `specs/001-mvp/research.md` に記録
- [ ] T019 スパイク結果を `specs/001-mvp/plan.md` に反映（プラグイン最終選定・距離しきい値・fog of war 方式の確定）。**plan.md に差分が出る場合は代表承認を得る**（ドキュメントが常に正）

**Checkpoint**: 技術スタックが実機で成立することを確認。R1 が不合格なら plan.md ゲート②に差し戻し

---

## Phase 3: Foundational（基盤・ブロッキング前提）

**Purpose**: 全ユーザーストーリーが依存する core 抽象・データモデル・地域パック・位置記録パイプラインを構築

**⚠️ CRITICAL**: 本フェーズ完了までユーザーストーリーの実装を開始しない

### core の抽象と値オブジェクト（plan.md §5・§2）

- [x] T020 [P] `packages/core/lib/src/geo/hex_id.dart` に `HexId`（決定論的な緯度経度→ID変換の**結果**を保持する値オブジェクト）を実装。ヘクス幾何や地図SDKには依存しない（Issue #33・整数表現・`toInt()` を実装済み — Issue #33 2026-08-13コメントの制約に対応）
- [x] T021 [P] `packages/core/lib/src/geo/tile_id.dart` に `TileId`、`packages/core/lib/src/geo/distance.dart` に `Distance` を実装（Issue #33: `TileId` を `docs/terrain.md` §4 の矩形細分グリッドセルの識別子として実装し、別名の `CellId` 型は追加不要と判断 — ただし Issue 本文は「HexId/TileId/Distance しかなく細分グリッドセルの型が挙がっていない」としており、この解釈自体は要確認。PR参照のうえ結論が覆れば本行を更新すること。`Distance` は単位メートル固定・型に単位情報を持たせない）
- [x] T022 [P] `packages/core/lib/src/terrain/terrain_type.dart` に `TerrainType`（空き地/森/山/水辺/海 — `docs/terrain.md` §2。Issue #70〔2026-09-08〕により農地/市街を除外し7種から5種に改訂）を実装
- [x] T023 [P] `packages/core/lib/src/position/position_provider.dart` に `PositionProvider` 抽象インターフェースを定義（実装は `location/`。テストではフェイクを注入 — plan.md §10）
- [x] T024 [P] `packages/core/lib/src/pack/region_pack.dart` に `RegionPack` 抽象（地形属性・区画・POI の読み取り口）と `pack_version` を定義
- [x] T025 [P] `packages/core/test/geo/hex_id_test.dart` に `HexId` の決定論テスト（同一入力→同一ID）を作成

### 資材・経済のドメインモデル（spec.md §6・buildings.md §6）

- [x] T026 [P] `packages/core/lib/src/economy/resource.dart` に資材種別を実装（建設系: 木・石・鉄 / 食料系: 塩・水・野菜・フルーツ・**肉**）
- [x] T027 [P] `packages/core/lib/src/economy/inventory.dart` に `Inventory`（資材の加算・消費・上限）を実装
- [x] T028 [P] `packages/core/lib/src/terrain/terrain_yield.dart` に地形→資材の一次産出マッピング（森→木、山→石/鉄、水辺→水、海→塩、空き地→産出なし）を実装（Issue #70〔2026-09-08〕により農地・市街を地形タイプから除外。野菜/フルーツ/肉は建物産出専用〔`docs/buildings.md` §6〕）
- [x] T029 [P] `packages/core/test/economy/terrain_yield_test.dart` に地形→資材マッピングのテーブル駆動テストを作成

### データ永続化（plan.md §6）

- [x] T030 SQLite（Drift）を `packages/location/` または `app/` 側に導入し、**ゲーム状態DB**と**地域パックDB（読み取り専用）**を別接続として分離する構成を作る（Issue #83。`packages/location/lib/src/db/game_database.dart` の `GameDatabase`〔読み書き〕と `region_pack_connection.dart` の `RegionPackConnection`〔`OpenMode.readOnly` で構造的に書き込みを防止〕に分離。`app/pubspec.yaml` は未編集）
- [x] T031 [P] `disclosed_hex` テーブル（開示済みヘクス・`pack_version`）のスキーマとマイグレーションを作成（Issue #83。不変性ルール自体の実装は別 Issue #84・T035〜T037）
- [x] T032 [P] `inventory` テーブルのスキーマとマイグレーションを作成（Issue #83。`core` の `Resource` 型〔T026・PR #89 未マージ〕には依存させず、資材キーは生の文字列列に留めた）
- [x] T033 [P] `building` テーブル（建物種別・レベル・建築状態軸・ヘクス座標・区画）のスキーマを作成（`docs/buildings.md` §2）（Issue #83。採石場を含む8種〔`BuildingType`〕を表現）
- [x] T034 [P] `district_progress`（制覇率・発展度）・`collection`（名所図鑑）・`quest_daily`・`settings` のスキーマを作成（Issue #83）
- [x] T035 **開示ヘクス集合の圧縮表現**を実装（Roaring Bitmap / ビットセット・plan.md §6）。GeoJSON 保持はしない（Issue #84。`packages/core/lib/src/pack/disclosed_hex_set.dart` の `DisclosedHexSet` として実装。H3由来の疎な整数値を上位ビット〔コンテナキー〕・下位16bit〔コンテナ内位置〕に分割し、コンテナごとに疎なら配列・要素数が閾値〔4096〕を超えたらビットマップへ適応的に昇格する Roaring Bitmap 方式。`disclosed_hex` テーブル〔T031〕はこの圧縮表現の生成元であり、テーブル自体は1行1ヘクスのまま変更していない。30,000ヘクス規模のテストあり）
- [x] T036 **パック更新の不変性ルール**を実装: 一度開示したヘクスの資材分類は、パック更新後も過去分を不変とする（plan.md §3.3）（Issue #84 で実装し、**Issue #96（2026-09-10 代表決定）で実現方法を変更**。**現在の正**: `packages/core/lib/src/pack/disclosed_hex.dart` の `DisclosedHex.terrainType`（`disclosed_hex.terrain_type` 列）に**開示時点の地形分類をスナップショット**として保存し、以後パックを引かない。〔**廃止**: Issue #84 当時の `pack_version_resolver.dart` の `PackVersionResolver`〔当時のバージョンのパックを引く方式〕は、MVP がパックをアプリ同梱するため旧パックが端末に残らず原理的に成立しないことが判明し、Issue #96 で削除した〕。`pack_version` 列は監査・移行判断の記録として保持する）
- [x] T037 [P] `packages/core/test/pack/disclosed_hex_snapshot_test.dart` にパック更新後も過去の開示・獲得が変わらないことのテストを作成（Issue #84 で作成し **Issue #96 で置き換え**。パック更新をまたいでヘクスごとに開示当時の地形分類が独立して保たれることを検証する。〔**廃止**: Issue #84 当時の `pack_version_immutability_test.dart` は `PackVersionResolver` の削除に伴い Issue #96 で削除した〕）
- [x] T038 Repository 層の抽象を `packages/core` に定義し、実装を `location`/`app` 側に置く（将来のサーバ同期 #16 に備えた抽象化 — #10 代表回答）

### 地域パック生成パイプライン（plan.md §3・§4）

- [x] T039 `tools/pack-builder/` に Planetiler/osmium ベースの生成スクリプトを実装（OSM日本抽出 → ベクタタイル MBTiles）。1エリアのヘクス数が暫定上限 **30,000**（plan.md §3.5・fog of war ソース構築2秒以内が主基準）を超える場合はエリア分割を行うこと → **完了（2026-09-10・Issue #85）**: `build_vector_tiles.sh` を実装。Planetiler v0.10.2（JDK 21必須）標準プロファイル（OpenMapTiles互換スキーマ）をそのまま使用（T055が既存スタイルを流用できるようにするため、自前スキーマは不採用）。狭山湖周辺エリアで実測: 出力696,320 bytes・生成時間約39秒〜1分20秒・タイル数73（zoom 0-14）・feature数53,308・レイヤ13種。同一入力から同一出力になることを `verify_tiles_determinism.py` で検証しPASS（tools/pack-builder/README.md参照）。ヘクス数13,106（上限30,000の44%）のためエリア分割は不要
- [x] T040 `tools/pack-builder/` に **地形属性の事前計算**を実装（`docs/terrain.md` §5 の OSMタグ→地形タイプ判定ルールを細分グリッドセルに適用 → §4 の多数決でヘクスに集約 → SQLite `cell_terrain`/`hex_terrain`）。**要件追記（2026-09-08・Issue #56）**: fog of war の fill レイヤに載せる各ヘクス Feature は、GeoJSON 出力時に**直下に整数 `id`** を持たせること。`promoteId` は Web 専用で Android では機能しないため、`properties` からの昇格では代用できない（plan.md §8・research.md §6.3）。Issue #38 着手前に本要件を満たす設計にすること → **完了と判定（2026-09-10・Issue #86で現状調査を実施）**: 実体はIssue #38（PR #69）で既に実装済みだったが、tasks.md上のチェックが未反映のまま放置されていたため、本Issueで現状調査のうえ完了と確定した。調査結果（詳細・根拠は`tools/pack-builder/README.md`「T040の完了状態の調査結果」参照）: (1) **満たされている要件**: `terrain_rules.py`（§5判定ルール）・`classify_terrain.py`（§4多数決集約・決定論的タイブレーク）・`cell_terrain`/`hex_terrain`両テーブル出力が実装済み。本Issueで実際に再実行し`cells=1,012,011 hexes=13,106`を確認（research.md §8.1・§8.8.1と一致）。`verify_determinism.py`（2回生成の対称差分0件）・`verify_feature_id.py`（衝突0件・可逆性OK）も再実行しPASS。整数`id`要件は`hex_bridge.py`の`feature_id`（T043で完了記録済みと同一実装）で充足。(2) **満たされていないもの**: 海岸線からの海面合成未実装（対象エリアが内陸のため無影響）・building密度による市街判定未実装（Issue #70で市街自体が地形タイプから廃止され要件が消滅）・bbox境界ヘクスの多数決精度（データ品質上の注意点でid不変性には無関係）。research.md §8.7に記録済みの既知の簡略化であり新規の欠落ではない。(3) **結論**: 上記はいずれもT040の受け入れ基準を妨げないため完了と判定した
- [x] T041 [P] `tools/pack-builder/` に行政区域ポリゴン（国土数値情報 N03・トポロジ保持簡略化）の取り込みを実装 → **完了（2026-09-10・Issue #86）**: `download_n03.sh`（N03第3.1版・埼玉県/東京都をダウンロード。既存data_cacheを活用し再ダウンロードを回避する設計）・`extract_districts.py`（bboxと交差する市区町村を抽出→`topojson`パッケージでトポロジ保持簡略化→ヘクス重心の区画帰属判定〔plan.md §5〕→SQLite `district`/`hex_district`出力）を実装。**実測**: 狭山湖周辺で5市区町村（所沢市・入間市・東大和市・武蔵村山市・瑞穂町）を抽出、頂点数7,291→1,524（20.9%）に削減、簡略化後も隣接ポリゴン間の隙間・重なりなし（`verify_topology`で自動検証）、全13,106ヘクスを区画に帰属判定（未帰属0件）、生成時間約1.4秒。`verify_districts_determinism.py`で2回生成し`district`/`hex_district`とも完全一致（PASS）。データソース: 国土数値情報N03（国土交通省。利用規約はオープンデータだが複製承認表示の要否は代表確認事項として`tools/pack-builder/README.md`に記録）。`district`/`hex_district`テーブルは`region_pack.sqlite`への同梱統合は行っていない（スコープ外。README「既知の簡略化・未解決事項」参照）
- [x] T042 [P] `tools/pack-builder/` に名所 POI 抽出（OSM 観光POI → SQLite `poi`）を実装 → **完了（2026-09-10・Issue #86）**: `poi_rules.py`（`docs/landmark_objects.md` §2.1 Tier 1タグの判定ルール）・`extract_poi.py`（`area.osm.pbf`からTier 1タグに該当するNode/Areaを抽出→名称なし・`leisure=park`の面積不足〔`config.POI_PARK_MIN_AREA_M2`=1ha仮値〕を除外→SQLite `poi(id, lat, lon, kind, name)`出力）を実装。**実測**: 狭山湖周辺で16件（`tourism=viewpoint`×2・`museum`×4・`artwork`×2・`attraction`×1・`historic=memorial`×5・`leisure=park`×2）、生成時間約2.3秒。`verify_poi_determinism.py`で2回生成し完全一致（PASS）。Tier 2（補完層）・ボーナスオブジェクト（allowlist照合）は目標密度・allowlistとも仮値のため未実装（README「既知の簡略化・未解決事項」に記録。密度の妥当性は代表確認事項）。データソース: OSM（ODbL。詳細適合検証はIssue #37）。`poi`テーブルは`region_pack.sqlite`への同梱統合は行っていない（スコープ外）
- [x] T043 [P] `tools/pack-builder/` にパックメタ（`pack_version`）の付与を実装。**要件追記（2026-09-08・Issue #56）**: fog of war の fill レイヤに載せる各ヘクス Feature の**直下に整数 `id`** を付与すること（`promoteId` は Android 非対応 — plan.md §8・research.md §6.3）。Issue #38 着手前に落としておく → **完了（2026-09-10・Issue #85）**: `classify_terrain.py` が `pack_meta` に `pack_version`（形式 `{area_slug}-v{schema_version}-{入力sha256先頭12桁}`。生成時刻に依存しない純関数。実測例: `sayamako-v1-9a66e066b0d4`）を付与。`id`要件はIssue #38で実装済みの `hex_terrain.feature_id`（下位52bitマスク方式・`hex_bridge.py`）がこれに当たり、`export_hex_geojson.py` で実データ13,106件全件について「Feature直下に整数`id`（重複なし）」を検証しPASS（tools/pack-builder/README.md参照）
- [x] T044 バーティカルスライス対象エリア（**代表の生活圏を含む約5km四方**・水辺/緑地/農地/市街が混在 — plan.md §15）のパックを生成し、`app/assets/` に**同梱**する。ヘクス数が暫定上限 **30,000**（plan.md §3.5）を超える場合はエリア分割して同梱すること → **完了（2026-09-10・Issue #85）**: 対象エリアは狭山湖周辺で本番確定（2026-09-10代表決定。Issue #38以来の検証エリアをそのまま採用。plan.md §15の定義自体は変更せず、本エリアが実測でそれに該当するという整理。判断根拠・面積検算は `tools/pack-builder/config.py` 冒頭コメントとIssue #85コメント参照）。`bundle_region_pack.sh` が地形属性事前計算→軽量化→ベクタタイル生成を一括実行し `app/assets/pack/`（`region_pack.sqlite`・`tiles.mbtiles`）へ同梱する仕組みを実装（生成物自体はコミットしない。`spikes/fixtures/`と同じ「生成スクリプト+`.gitignore`」方式。`app/pubspec.yaml`はディレクトリ単位で宣言）。**実測**: ヘクス数 **13,106**（上限30,000の44%。分割不要）、`region_pack.sqlite` 約750KB、`tiles.mbtiles` 約680KB、`pack_version`=`sayamako-v1-9a66e066b0d4`。plan.md §3.5の「30,000ヘクス規模の実機計測で確定」という宿題は未解消（実機を持たないため。代表向けの計測手順を `tools/pack-builder/README.md` に用意した）
- [x] T045 [P] パック生成を CI で再現可能にする（`.github/workflows/pack-build.yml`） → **完了（2026-09-10・Issue #85）**: `.github/workflows/pack-build.yml` を作成（JDK 21セットアップ含む）。関東OSM抽出・Planetiler補助データセット計約1.9GBの初回取得を伴うため通常のPR CI（ci.yml）には含めず `workflow_dispatch`（手動トリガー）のみとした（Issue #85の指示により実際にGitHub Actionsで実行することまではスコープ外）。ローカルで同等の手順が通ることを確認済み: `classify_terrain.py`→`verify_determinism.py`（PASS）・`build_vector_tiles.sh`→`verify_tiles_determinism.py`（2026-09-10実施・73/73タイル完全一致でPASS）

### 位置記録パイプライン（plan.md §7・#10）

- [ ] T046 `app/android/` に Kotlin **foreground service** を実装（fused location provider・距離ベースサンプリング・停止中は省電力）
- [ ] T047 位置記録の保存を Kotlin 側からローカルDBへ直接書き込む形で実装し、**Dart は読むだけ**にする（plan.md §2・将来のバックグラウンド対応で作り直さないため）
- [ ] T048 時刻に**単調時計 `elapsedRealtime`** を使用する（端末時刻改竄への耐性 — plan.md §7）
- [ ] T049 **Pigeon** で platform channel の型定義を作成（`pigeons/location_api.dart`）し、生成コードを Dart/Kotlin 双方に組み込む（iOS 移植の正 — plan.md §1-C）
- [ ] T050 [P] `packages/location/lib/src/position/native_position_provider.dart` に `PositionProvider` の実装（Kotlin 側の記録を読む）を作成
- [x] T051 [P] `packages/core/test/position/fake_position_provider.dart` にフェイク実装と、**録画済み歩行ルートのリプレイテスト基盤**を作成（plan.md §10） → **完了（2026-09-10・Issue #101）**: `FakePositionProvider`（固定の `GeoPosition` 列を `positionUpdates` から流すだけの実装）を、既存の `position_provider_test.dart` 内定義から独立ファイルへ抽出した。`test/disclosure/disclosure_test.dart`・`test/disclosure/replay_walk_test.dart`（T052・T053）から共有フィクスチャとして再利用し、「録画済み歩行ルートのリプレイテスト基盤」として機能することを実証した

**Checkpoint**: 基盤完成。ここからユーザーストーリーを並列着手できる

---

## Phase 4: US1 — 散歩ユーザー（Priority: P1）🎯 MVP

**Goal**: 通勤・散歩で歩いた場所の**実地図**が開拓され、霧が晴れていく。歩くこと自体がゲーム進行になる

**Independent Test**: 実機で30分歩き、通過した経路のヘクスの霧が晴れ、アプリ再起動後も開示状態が残ること

### Tests for US1

- [x] T052 [P] [US1] `packages/core/test/disclosure/disclosure_test.dart` に開示判定のテスト（グリッドセル通過→ヘクス開示）を作成 → **完了（2026-09-10・Issue #101）**: テスト専用の `_GridHexLocator`（緯度経度→細分グリッドセル→ヘクスの量子化をH3非依存で模したフェイク）と呼び出し回数を記録する `_CountingFakeRegionPack` で、(1) 未開示ヘクスへの通過で開示され地形・パックバージョンがスナップショットされること、(2) 同一ヘクス内の複数グリッドセル通過は開示1回だけ（`terrainOf`も1回だけ）、(3) ヘクス境界をまたぐと2件開示、(4) パック範囲外は開示されず保存もされない、(5) 起動時に既知（`DisclosedHexSet`に事前登録済み）のヘクスは`terrainOf`が一度も呼ばれない、(6) `Stream<GeoPosition>`をそのまま`disclose`に渡せる、を検証
- [x] T053 [P] [US1] `packages/core/test/disclosure/replay_walk_test.dart` に録画歩行ルートのリプレイで期待どおりのヘクス集合が開示されるテストを作成 → **完了（2026-09-10・Issue #101）**: T051の`FakePositionProvider`を使い、空き地→森（同一ヘクス内を3点で往復）→山→海→森（再訪問）という録画ルートをリプレイし、4ヘクスがそれぞれ1回ずつ・訪問順に開示されることを検証。同じルートを2回リプレイして`DisclosedHex`の列（hexId・terrainType・discoveredAtVersionすべて）が完全一致することで決定論を検証

### Implementation for US1

- [x] T054 [US1] `packages/core/lib/src/disclosure/disclosure_service.dart` に開示判定ロジック（通過グリッドセル→ヘクス多数決集約→`disclosed_hex` 更新）を実装。**GPS/地図に依存しない純粋ロジック**。**2026-09-10 追記（Issue #96）**: 新規ヘクスを開示する瞬間に、その時点の `RegionPack.terrainOf` の結果を `DisclosedHex.terrainType`（`disclosed_hex.terrain_type` 列）としてスナップショット保存すること。開示済みヘクスの地形分類の正はこのスナップショット列であり、`RegionPack.terrainOf` を再度引く経路は存在しない（`PackVersionResolver` は Issue #96 で削除済み） → **完了（2026-09-10・Issue #101）**: `DisclosureService`（`recordPosition`・`disclose(Stream<GeoPosition>)`）を実装。開示済みヘクスの高速判定は既存の`DisclosedHexSet`（作り直さず再利用）、永続化は`Repository<DisclosedHex, HexId>`（抽象）を注入する設計。緯度経度→ヘクスIDの変換は本Issueで新規定義した`HexLocator`抽象（`core/src/disclosure/hex_locator.dart`）経由でのみ行い、`core`はH3等の変換ロジックを一切持たない（`location/`側の実装は本Issueのスコープ外）。**「多数決」の解釈（要確認・設計判断として明記）**: `docs/terrain.md`§4.1を精査した結果、「多数決」がかかるのは地形タイプの確定（地形タグの多数決）のみで、続く「開示判定もヘクス単位で集約する」という一文には多数決という語がかかっていない（`docs/terrain.md`・`plan.md`・`research.md`全体をgrepし他に定義なしを確認）。開示は真偽値のため、集約関数は多数決（プラリティ投票）ではなく論理和（同一ヘクス内のいずれかのグリッドセルを1回でも通過すれば開示）として実装した。GPSジッタ抑制のための時間窓多数決等を意図していた場合は仕様上の根拠が見つからなかったため未実装とし、必要であれば別途`location/`側の位置平滑化として検討を要する
- [x] T055 [US1] `packages/location/lib/src/map/map_view.dart` に MapLibre 地図表示（同梱 MBTiles をローカル読込）を実装 → **完了（2026-09-10・Issue #99）**: `MapView`（`packages/location/lib/src/map/map_view.dart`）を実装。`mbtiles://` の読込構文は `VectorSourceProperties(url:)` を採用（research.md §6.2 の実機検証で url 方式単独成立の強い傍証があり、API 表面も単純なため。`tiles:` は不採用。根拠は `mbtiles_source.dart` のコメントに記録）。アセットバンドル内の MBTiles を書き込み可能な領域へコピーする `resolveBundledMbtilesPath`（`mbtiles_asset.dart`）を用意し、パック未取得時は `PackAssetMissingException` を送出する（T057 側でエラー状態として処理）。`location` は配色・カメラSDK型（`CameraPosition`/`LatLng`）を app に露出しない（`MapCameraPosition` を独自定義）。fog of war（T056）は `_addRegionPackLayers` 末尾のコメントで拡張ポイントを明記し、ベースレイヤーの後に追加できる構造にした（`MapLibreMapController` は app には公開しない）。実際の地域パック（`tiles.mbtiles`・53,308 feature・z0-14・13レイヤ）での読込確認は実機が必要なため代表が実施する（PR本文の確認手順を参照。「実機で確認した」とは記載しない）
- [x] T056 [US1] `packages/location/lib/src/map/fog_of_war_layer.dart` に fog of war を実装（**採用方式・2026-09-08 Issue #56 追随**: 全ヘクスを起動時／エリア切替時に**1回だけ** `addGeoJsonSource` でソースに追加し、開示は fill レイヤの `fill-opacity` を `feature-state`（`setFeatureState`）のトグルで切り替える。各 Feature は直下に整数 `id` を持たせる（`promoteId` は Android 非対応）。`maplibre_gl` 0.27.0 以降が必要（0.26.2 は Android で `setFeatureState` が `UnimplementedError`）— plan.md §8。**不採用（経緯）**: 「穴あきポリゴン1枚」の GeoJSON 差分更新は実機計測で性能基準未達（FAIL）のため不採用 — plan.md §8・research.md §6.4）→ **完了（2026-09-10・Issue #100）**: `FogOfWarController`（`fog_of_war_layer.dart`）を実装。`install()` が呼び出し側の用意した GeoJSON FeatureCollection を1回だけ `addGeoJsonSource` し、`fill-opacity` を `['case', ['boolean', ['feature-state','revealed'], false], 0.0, layer.fillOpacity]` で切り替える fill レイヤーを追加する（plan.md §8 の式をそのまま採用）。各 Feature が直下に整数 `id` を持つことを `validateFogHexFeatureCollectionIds`（純粋関数・単体テスト済み）で実行時検証し、`promoteId` 由来の誤実装を弾く。開示は `revealHex(int featureId)` の `setFeatureState` 1回のみ（O(1)）。**開示状態の正が `disclosed_hex` であり feature-state は派生であることをクラスdocコメントに明記**（`setStyle` で feature-state が全消失する実機知見・plan.md §8 を再掲）。色は Issue #57 の注入方式を継続（`app/lib/map/fog_of_war_layer_factory.dart` の `FogOfWarLayer` をそのまま使用。`location` は独自の色リテラルを持たない）。`MapView`（`map_view.dart`）は `fogOfWarLayer`/`fogHexFeatureCollection` が両方渡された場合のみ、地域パックの基盤レイヤー追加の直後に fog を追加し、`onFogLayerReady` で `FogOfWarController` を呼び出し側へ渡す（`MapLibreMapController` 自体は非公開のまま）。**本Issueのスコープ外（明記のうえ未実装）**: どのヘクスを開示するかの判定（T054・Issue #101）／実際のヘクス境界ジオメトリの組み立て（地域パックの `hex_terrain` から算出する処理。`RegionPackRepository`＝T069 が本Issue時点で未実装のため、`MapView` は呼び出し側が用意した FeatureCollection を受け取るだけに留めた）／開示状態の永続化・復元（T060・Issue #102）。**代表が実機で確認する手段**: `app/lib/map/debug/`（`fog_debug_hex_grid.dart`・`fog_of_war_debug_panel.dart`）に `kDebugMode` 配下限定のデバッグ機能を実装。合成（プログラム生成・本物のヘクスではない）ヘクス61件を初期カメラ位置に重ね、「1マス開示」「すべて開示」「霧に戻す」ボタンでトグルを確認できるほか、「本番相当(13,106件)で計測」ボタンで本番パックの実測ヘクス数（tasks.md T044・2026-09-10実測）と同数の合成グリッドを一時ソースとして追加し、geometry生成／`addGeoJsonSource`／`addLayer`の各所要時間をその場に表示する（**実測手順の提供までがスコープであり、実測の実施自体は代表が行う**。research.md §6.4「2026-09-09追加計測」の「合計」はフレームジャンク計測④も含むため、本パネルの「合計」〔①〜③のみ〕はそれよりやや小さく出うる旨をコメント・表示文言に明記）。release ビルドでは上記デバッグ機能は一切現れず、`fogOfWarLayer`/`fogHexFeatureCollection` は渡されない（Issue #99時点と同一挙動。製品UIを汚さない）。`flutter build apk --debug`・パック未取得状態でのビルド/テスト・ガードスクリプト6本・`flutter analyze`・`flutter test -j 1`（location 28件・app 30件）は全てPASS/成功を確認済み（詳細はPR本文参照。「実機で霧が晴れることを確認した」とは記載しない） → **2026-09-10・Issue #105 で「実際のヘクス境界ジオメトリの組み立て」を解決**: 上記「本Issueのスコープ外」に挙げていた項目のうち、ヘクス境界ジオメトリの組み立ては`RegionPackRepository`（T069）の実装を待たずに解決した。`tools/pack-builder/`（`hex_geometry.py`・`classify_terrain.py`）がH3セル境界を**パック生成時に事前計算**し`hex_terrain.boundary_geojson`列に格納する方式（2026-09-10代表決定・案A）を採用し、`packages/location`の`buildFogHexFeatureCollectionFromRegionPack`（`fog_hex_source.dart`・新規）が`RegionPackConnection`（T030）経由でこれを読み、`FogOfWarController.install`にそのまま渡せるGeoJSON FeatureCollectionを組み立てる。**本責務はT056（fog of war描画に必要な入力の組み立て）に属し、T069（`core`の`RegionPack`抽象の実装）には属さない**——`RegionPack`（`core`）はGPS_ARCHITECTURE準拠で地図SDK・幾何表現に依存できず構造的にGeoJSONのような幾何を返すメソッドを持てないため（`fog_hex_source.dart`のdocstring参照）。実データ13,106件で`FogOfWarController`に載せられることを`app/test/map/region_pack_fog_geometry_test.dart`（同梱`region_pack.sqlite`が存在する場合のみ実行）で検証済み。デバッグパネルの「本番相当…で計測」ボタンも合成データではなく実データ（`region_pack.sqlite`読込）を使うよう変更した（詳細はIssue #105のPR本文参照）
- [x] T057 [US1] `app/lib/features/map/map_screen.dart` にマップ画面を実装（`DESIGN.md` のトークンに準拠。色・サイズの直書きをしない）→ **完了（2026-09-10・Issue #99）**: `MapScreen` を実装。ローディング（パック解決中）/エラー（パック未取得・その他失敗）/成功（地図表示）の3状態を実装（fog未実装のため「空=未開示」は本Issueでは到達しない。DESIGN.md からの逸脱ではなく、ローディング=地域パック読込の失敗系としてエラー状態を扱う）。色は `app/lib/map/map_style_factory.dart` が `ColorTokens`（水面=secondary・土地被覆=primary・建物footprint/道路=text-secondary。根拠は同ファイルのコメントに実測メタデータ引用つきで記録）から導出し、`MapView` へ `#RRGGBB` 文字列で注入する（Issue #57 と同じ役割分担）。余白・アイコンサイズは `AppSpacing` トークンを使用。`tools/check_design_tokens.sh` PASS 済み。`MapView`（MapLibre の実プラットフォームビュー）は widget テスト環境で不安定なため、`resolveMbtilesPath`/`mapBuilder` の差し替えフックで実描画を経由せずに状態遷移をテストしている（`test/features/map/map_screen_test.dart` 冒頭コメント参照）
- [ ] T058 [US1] 現在地表示と地図追従を実装（`app/lib/features/map/`）
- [ ] T059 [US1] 位置記録サービスの起動/停止と権限リクエスト（フォアグラウンド位置のみ）を実装（`app/lib/features/permissions/`）
- [ ] T060 [US1] 開示状態の永続化と復元を実装し、アプリ再起動後も霧の状態が残ることを確認。**2026-09-09 追記（plan.md §8・research.md §6.4）**: 復元対象は「アプリ再起動後」だけでなく**任意の `setStyle`（スタイル再読み込み）後**も含める。実測で `setStyle` は地図側の feature-state を全て消すことが確認されており、地図の feature-state は開示状態の正ではなく永続ストレージ（T031・T035）が正であるため、素直に実装するとテーマ切替等で霧が全部消える事故になる。**2026-09-10 追記（Issue #96）**: 復元時の地形分類（資材産出・建築可否判定に使う値）は `disclosed_hex.terrain_type` のスナップショットから読むこと。地域パックを引き直して復元してはならない（パック更新後は旧パックが端末に存在しないため）
- [ ] T061 [US1] オフライン蓄積→前景復帰時の状態反映を実装（FR-7・MVP は端末内完結）
- [ ] T062 [P] [US1] 歩行距離・歩数の表示（HUD）を実装（`app/lib/features/map/widgets/`・`DESIGN.md` の HUD 方針に準拠）
- [ ] T063 [US1] **開放ポイント**の入手を実装（自然回復 **1P/日** ＋ GPS移動距離ベースの付与・上限 **50** — `docs/opening_points.md`）
- [ ] T064 [US1] `packages/core/lib/src/opening/opening_point_service.dart` にポイント消費による未踏破ヘクス開放を実装（**1pt/メッシュ**・**開放済みヘクスに隣接するもののみ**・海は開放可・**実在の立入禁止エリアは黒塗りで対象外**）
- [ ] T065 [P] [US1] `packages/core/test/opening/opening_point_test.dart` にポイント経済のテスト（歩行優位が保たれること・隣接制約・上限）を作成

**Checkpoint**: US1 単独で「歩く→霧が晴れる→再起動後も残る」が成立（Fog of World 相当として遊べる）

---

## Phase 5: US2 — 収集ユーザー（Priority: P2）

**Goal**: その土地の地形に応じた資材が手に入り、実在の名所が地図上に現れて「行ってみたい」と思える

**Independent Test**: 森・水辺・山を含む経路を歩き、地形に応じた資材が付与され、名所オブジェクトが図鑑に記録されること（Issue #70〔2026-09-08〕により地形タイプから市街を除外したため、例示を5種の地形に更新）

### Tests for US2

- [ ] T066 [P] [US2] `packages/core/test/economy/resource_grant_test.dart` に開示ヘクスの地形属性→資材付与の決定論テストを作成
- [ ] T067 [P] [US2] `packages/core/test/collection/collection_test.dart` に名所の図鑑登録テスト（現地訪問と遠隔開放の差分ボーナス）を作成

### Implementation for US2

- [ ] T068 [US2] `packages/core/lib/src/economy/resource_grant_service.dart` に資材付与を実装（**地域パックの事前計算済み地形属性を読む純粋関数**・実行時のタイルクエリはしない — plan.md §4）
- [ ] T069 [US2] `packages/location/lib/src/pack/region_pack_repository.dart` に地域パック（SQLite・読み取り専用）へのアクセスを実装。**2026-09-10 追記（Issue #96）**: 本リポジトリが返す `RegionPack`（`terrainOf` 含む）は新規開示時のスナップショット作成にのみ使うこと。既に開示済みのヘクスの地形分類を問い合わせる経路として使わない（正は `disclosed_hex.terrain_type`）。一方、区画（`districtOf`）・名所POI（`pointsOfInterest`）は開示状態に関わらず常に本リポジトリ経由で現行パックから解決してよい（スナップショットしない設計・理由は `disclosed_hex` テーブル・`RegionPack` のドキュメント参照）。**2026-09-10 追記（Issue #105・責務の切り分け）**: fog of war 用のヘクス境界ジオメトリ（GeoJSON FeatureCollectionの組み立て）は**本タスクの責務ではない**。Issue #105 により、`core` の `RegionPack` 抽象（本タスクが実装する対象）は GPS_ARCHITECTURE 準拠で地図SDK・幾何表現に依存できないため、そもそも幾何を返すメソッドを持てないと判明した（`terrainOf`/`districtOf`/`districts`/`pointsOfInterest` はいずれも座標に依存しない値・識別子のみを返す）。ヘクス境界の組み立ては T056 側（`packages/location/lib/src/map/fog_hex_source.dart`・`buildFogHexFeatureCollectionFromRegionPack`）で解決済み。本タスク（T069）が今後実装する `RegionPackRepository`／`RegionPack` 実装は、地形属性・区画・POI の読み取り（`terrainOf`/`districtOf`/`districts`/`pointsOfInterest`）に専念すればよく、ヘクス境界を扱う必要はない
- [ ] T070 [US2] `packages/core/lib/src/landmark/landmark_service.dart` に名所・固有オブジェクトの出現判定を実装（`docs/landmark_objects.md`）
- [ ] T071 [US2] 名所オブジェクトの地図表示を実装（`packages/location/lib/src/map/landmark_layer.dart`）。**ポイント開放したマスでも表示する**
- [ ] T072 [US2] **現地訪問時の追加ボーナス**を実装（遠隔開放でも取得可だが、実際に歩いて訪問するとプラス — #6 代表回答）
- [ ] T073 [US2] ボーナスオブジェクト（著名スポット）の効果を実装（**コレクション＋軽い産出/ポイントボーナス**・歩行優位を崩さない範囲）
- [ ] T074 [P] [US2] 著名スポットの**独自キュレーション**データを `tools/pack-builder/data/curated_landmarks.*` として定義し、パック生成に取り込む
- [ ] T075 [US2] `app/lib/features/collection/collection_screen.dart` に**名所図鑑**を実装（**個別POI単位**で記録＋カテゴリ集計表示 — #12 代表回答）
- [ ] T076 [P] [US2] 資材インベントリ画面を実装（`app/lib/features/inventory/inventory_screen.dart`）
- [ ] T077 [US2] **近接通知**（フォアグラウンドのみ・未開放の名所/レア地形が近いと通知・自前距離計算で判定し OS geofence は使わない — plan.md §10）を実装
- [ ] T078 [P] [US2] 通知のオプトイン設定と頻度制御を実装（`app/lib/features/settings/`）

**Checkpoint**: US1＋US2 が独立に成立。「その土地ならでは」の価値（V-B）が体験できる

---

## Phase 6: US3 — 育成ユーザー（Priority: P3）

**Goal**: 集めた資材で実地図の上に街を建て、人口を育て、区画の制覇率を伸ばせる

**Independent Test**: 資材を消費して空き地に建物を1つ建て、時間経過で人口が増え、産出ボーナスと区画制覇率が反映されること

### Tests for US3

- [ ] T079 [P] [US3] `packages/core/test/building/build_rule_test.dart` に建築ルールのテスト（空き地のみ・1マス1建物・娯楽系の隣接制約）を作成
- [ ] T080 [P] [US3] `packages/core/test/population/population_test.dart` に人口の成長・上限・産出ボーナス閾値のテストを作成
- [ ] T081 [P] [US3] `packages/core/test/district/district_progress_test.dart` に制覇率算出のテスト（**分母は到達可能ヘクスのみ**・立入禁止は除外）を作成

### Implementation for US3

- [ ] T082 [US3] `packages/core/lib/src/building/building_type.dart` に建物3系統8種を実装（住宅・マンション / 畑・農場・工場・**採石場**〔2026-09-09 代表決定・Issue #72〕 / リゾート・ミュージアム — `docs/buildings.md` §2）
- [ ] T083 [US3] `packages/core/lib/src/building/build_rule_service.dart` に建築可否判定を実装（**開示済みかつ空き地**・1マス1建物・**リゾートは海に隣接**・**ミュージアムはプレイヤーが建設した住宅系建物〔住宅・マンション〕に隣接**〔2026-09-08 代表決定・Issue #70。`docs/buildings.md` §2参照〕・**採石場は空き地であれば山への隣接なしで建築可（山隣接は産出倍率のみに影響）**〔2026-09-09 代表決定・Issue #72。`docs/buildings.md` §2・§6.3参照〕）
- [ ] T084 [US3] `packages/core/lib/src/building/build_cost_service.dart` に建設コスト（建設系資材のみ消費）とアップグレード（Lv.1〜3）を実装（`docs/buildings.md` §4。**採石場は木のみを消費し石・鉄を含めないこと〔設計要件・balance調整の対象外、§4.1参照〕**）
- [ ] T085 [US3] `packages/core/lib/src/population/population_service.dart` に人口メカニクスを実装（建物ごとの人口上限・時間経過で漸増・総人口の閾値到達で産出倍率ボーナス・**生活系資材は成長速度への加算的ボーナス〔1種欠けても停止しない、2026-09-09 Issue #72・`docs/buildings.md` §5.2参照〕** — `docs/buildings.md` §5）
- [ ] T086 [US3] 生産系建物の産出を実装（畑→野菜/フルーツ、農場→**肉**、工場→街全体の産出効率UP、**採石場→石・鉄〔山に隣接する場合は産出倍率あり〕**〔2026-09-09 代表決定・Issue #72。`docs/buildings.md` §6.3参照〕）
- [ ] T087 [US3] 娯楽系建物の効果を実装（人口が増えやすくなる＋産出効率が少し上がる）
- [ ] T088 [US3] **地形一次産出と建物定常産出の合算ルール**を実装（spec.md §6 の2層構造。数値は `balance.csv` に委譲）
- [ ] T089 [US3] `app/lib/features/build/build_screen.dart` に建設UIを実装（建築可能ヘクスのハイライト・コスト表示・`DESIGN.md` 準拠）
- [ ] T090 [US3] 建物の地図表示を実装（`packages/location/lib/src/map/building_layer.dart`・1マス1建物）
- [ ] T091 [US3] `packages/core/lib/src/district/district_progress_service.dart` に区画帰属判定（**ヘクス重心が区画ポリゴン内か** — plan.md §5）と制覇率集計を実装
- [ ] T092 [US3] 区画の発展度を実装（**制覇率×人口規模の複合** — #7 代表回答）。※MVP は集計・表示まで。発展度ボーナスは将来
- [ ] T093 [P] [US3] `app/lib/features/district/district_screen.dart` に区画一覧・制覇率表示を実装
- [ ] T094 [P] [US3] 区画境界の地図重畳レイヤーを実装（`packages/location/lib/src/map/district_layer.dart`）

**Checkpoint**: US1〜US3 が成立。コアループ（歩く→資材→建設→街が育つ）が一周する

---

## Phase 7: US4 — プライバシー懸念ユーザー（Priority: P4）

**Goal**: 自宅など開始位置が他人に分からない形で安心して遊べる。位置偽装で経済が壊れない

**Independent Test**: プライバシーゾーン内の位置が保存/表示対象から除外され、モック位置アプリ使用時に開拓・資材付与が無効化されること

### Tests for US4

- [ ] T095 [P] [US4] `packages/core/test/privacy/privacy_zone_test.dart` にプライバシーゾーン（半径500m）除外のテストを作成
- [ ] T096 [P] [US4] `packages/core/test/antispoof/speed_check_test.dart` に速度判定のテストを作成（**都市部マルチパスのスパイクで誤検出しない**・時速10km超は当該区間のみ報酬なし）

### Implementation for US4

- [ ] T097 [US4] `packages/core/lib/src/privacy/privacy_zone_service.dart` に**プライバシーゾーン（既定半径500m）**を実装。初回起動地点を自動ゾーン化
- [ ] T098 [US4] **公開レイヤー分離**の設計思想を実装で担保（経路・開拓メッシュは本人のみ。MVP は自分専用で外部送信経路を持たない — plan.md §10）
- [ ] T099 [US4] `app/android/` に**モック位置検出**（`isFromMockProvider` 等）を実装し、検出時は開拓・資材付与を**無効化**
- [ ] T100 [US4] `packages/core/lib/src/antispoof/speed_filter.dart` に**移動平均/カルマン平滑後の速度**による判定を実装。**時速10km超はその区間だけ報酬なし・罰しない**（電車内は「報酬なしで正常動作」）
- [ ] T101 [US4] **歩数センサー突合**を実装（歩いていないのに移動している場合は付与レートを低下）
- [ ] T102 [P] [US4] **Health Connect** 連携を実装（オプトイン・歩数プロバイダを抽象化して将来 iOS=HealthKit に差し替え可能に — #13 代表回答）
- [ ] T103 [P] [US4] `app/lib/features/settings/privacy_screen.dart` にプライバシー設定画面（ゾーン確認・Health連携のオプトイン）を実装
- [ ] T104 [P] [US4] Google Play の**ヘルスデータ申告**と**データセーフティ**用に「通信が発生する箇所一覧」を `docs/data-safety.md` として作成（MVP は地域パックDLのみ）

**Checkpoint**: US1〜US4 すべてが独立に成立。ストア審査に必要な申告材料が揃う

---

## Phase 8: Polish & Cross-Cutting Concerns

**Purpose**: 複数ストーリーに跨る仕上げ。**T105 と T110 は MVP 必須**

- [ ] T105 🔴 **セーブデータのエクスポート/インポート**を実装（plan.md §6 で MVP 要件に昇格。機種変更・故障での全ロスト対策。端末内ファイル/共有シート経由で**サーバに送らない**）
- [ ] T106 [P] `specs/001-mvp/balance.csv` を作成し、数値パラメータ（建設コスト・人口成長・産出量・ポイント換算・閾値）の**正本**とする。コードから数値の直書きを排除
- [ ] T107 [P] **デイリークエスト**を薄く実装（端末内生成・報酬は資材/コレクション中心でポイントは少量 — #11 代表回答）
- [ ] T108 🔴 **ライセンス表記**を実装（「© OpenStreetMap contributors」を**地図上に常時表示**＋ライセンス画面。OpenMapTiles 系スキーマ利用時は「© OpenMapTiles」追加。国土数値情報の出典表示 — plan.md §11）
- [ ] T109 **OSM/ODbL の派生データ・キャッシュ再配布条件**を確認し、地域パック同梱/配信が条件を満たすことを `docs/licenses.md` に記録（#6 のクローズ時に plan 工程へ持ち越した宿題）
- [ ] T110 🔴 **バーティカルスライスの完了判定**（plan.md §15）: 「実際に30分歩いて、霧が晴れ、資材が貯まり、建物が1つ建ち、アプリ再起動後も状態が残る」を実機で確認し、結果を代表に報告
- [ ] T111 [P] `docs/architecture.md` と `README.md` の構成図を実装後の実態に合わせて更新（構成が変わったらコードと同じコミットで更新する）
- [ ] T112 [P] エラーハンドリングとログ基盤を整備（`app/lib/core/logging/`）
- [ ] T113 [P] 電池消費の実測と省電力チューニング（NFR-1・距離しきい値の最終調整）
- [ ] T114 パフォーマンス最適化（fog of war の union 演算・大量ヘクス時の描画）
- [ ] T115 [P] `specs/001-mvp/spec.md` の受け入れ基準チェックボックスを実装状況に合わせて更新

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1（Setup）**: 依存なし。ただし **T001（Flutter SDK 導入）が全体のブロッカー**
- **Phase 2（技術検証スパイク）**: Phase 1 完了後。**R1 不合格なら plan.md ゲート②へ差し戻し**
- **Phase 3（Foundational）**: Phase 2 完了後。全ユーザーストーリーをブロック
- **Phase 4〜7（US1〜US4）**: Phase 3 完了後。P1 → P2 → P3 → P4 の順を標準とする（一人開発のため並列化はしない）
- **Phase 8（Polish）**: 対象ストーリーの完了後

### User Story Dependencies

- **US1（P1）**: Phase 3 完了後に着手可。他ストーリーに依存しない（**これ単独で MVP として遊べる**）
- **US2（P2）**: Phase 3 完了後に着手可。US1 の開示ヘクスを前提にするが、資材付与・名所は独立にテスト可能
- **US3（P3）**: Phase 3 完了後に着手可。US2 の資材を前提にするが、資材を手動投入すれば独立にテスト可能
- **US4（P4）**: Phase 3 完了後に着手可。US1 の位置記録に被せる形で独立にテスト可能

### 一人開発での並列機会

- Phase 1 の [P] タスク（T003・T004・T006・T008・T009・T010）はまとめて処理できる
- Phase 3 の core 値オブジェクト（T020〜T025）とデータモデル（T031〜T034）は独立
- Phase 3 のパイプライン（T039〜T045）は Dart 実装と独立に進められる
- 各ストーリーのテストタスク（[P] 付き）は実装前にまとめて書ける

---

## Implementation Strategy

### MVP First（US1 のみ）

1. Phase 1 Setup（**T001 Flutter SDK 導入が最初の関門**）
2. Phase 2 技術検証スパイク（**R1 が通らなければ技術選定をやり直す**）
3. Phase 3 Foundational
4. Phase 4 US1
5. **STOP して検証**: 実機で30分歩き、US1 単独の体験を評価
6. plan.md §15 のバーティカルスライス完了判定（T110）へ

### Incremental Delivery

1. Setup + スパイク + Foundational → 土台完成
2. US1 追加 → 単独検証 → **MVP（Fog of World 相当として遊べる）**
3. US2 追加 → 単独検証 → 「その土地ならでは」の価値が乗る
4. US3 追加 → 単独検証 → コアループが一周する
5. US4 追加 → 単独検証 → 一般公開の前提が揃う
6. Phase 8 で仕上げ（エクスポート/インポート・ライセンス表記は MVP 必須）

---

## Notes

- [P] タスク = 別ファイル・依存なし
- テストは実装前に書き、**失敗することを確認**してから実装する
- 数値は `balance.csv` を正本とし、コードに直書きしない
- 色・サイズは `DESIGN.md` のトークンを使い、直書きしない
- `packages/core/` は `location/`・`flutter`・地図SDK を import しない（T007 の CI チェックで機械的に強制）
- 各タスクまたは論理的なまとまりごとにコミットする
- 仕様と実装がずれたら、**実装を仕様に合わせるか、理由付きで spec/plan を先に更新**してから実装する（ドキュメントが常に正）

## 未確定・要確認（実装中に確定させる）

1. ~~**Flutter SDK のインストール先OS**（Windows / WSL）— T001~~ → **解決済み（2026-07-30 代表判断）**: WSL に導入。詳細は `docs/dev-setup.md` §1
2. ~~**plan.md §2 の `android/` 配置** — ルート直下 vs `app/android/`（T002 で確定し plan.md を追記修正）~~ → **解決済み（2026-09-08・Issue #35）**: `app/android/`（Flutter 標準）を正とし、plan.md §2 のツリーを修正済み。経緯は `docs/dev-setup.md` §6
3. ~~**plan.md §1・§14 の「Issue #1」参照**~~ → **解決済み**: PR #31（`a8b4787`）で実在する Issue への参照に修正済み。Phase 2 スパイクに対応する Issue は #24 として起票済み
4. Flutter 地図プラグインの最終選定（T011・plan.md §16）
5. 距離しきい値・`balance.csv` の数値（T015・T106）
6. 地域パックの静的ホスティング先（MVP は同梱のため拡張時に決定）
7. `DESIGN.md` のカラートークン確定値
