---
project: terra-town
doc: tasks.md (実装タスク分解)
feature: 001-mvp
status: draft
created: 2026-07-29
updated: 2026-07-29
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

> ⚠️ **plan.md §2 との差異（要確認）**: plan.md §2 のツリーは `android/` `ios/` をリポジトリ**ルート**に置いているが、`flutter create` は `app/android/` `app/ios/` に生成する。本 tasks.md は Flutter 標準（`app/android/`）を採用する。T004 で確定し、必要なら plan.md §2 を追記修正する（ドキュメントが常に正）。

---

## Phase 1: Setup（開発環境・プロジェクト土台）

**Purpose**: ビルドできる空のプロジェクトを用意し、依存方向を仕組みで強制する

> 🔴 **前提ブロッカー**: Flutter SDK が未インストール（WSL・Windows いずれにも無し。Android SDK は Windows 側に存在）。T001 の完了が Phase 1 以降すべての前提。

- [ ] T001 Flutter SDK（stable）と Android SDK/cmdline-tools を導入し、`flutter doctor` が Android toolchain で green になる状態にする（インストール先OS＝Windows/WSL の選択は代表判断。決定を `docs/dev-setup.md` に記録）
- [ ] T002 `flutter create` で `app/` を生成し、リポジトリ構成を plan.md §2 に合わせる（`app/`・`app/android/`）
- [ ] T003 [P] `packages/core/` を**純粋 Dart パッケージ**として作成（`packages/core/pubspec.yaml`・Flutter に依存させない）
- [ ] T004 [P] `packages/location/` を Flutter パッケージとして作成し、`pubspec.yaml` の dependencies に `core` のみを追加（逆向き依存を作らない）
- [ ] T005 `app/pubspec.yaml` に `core`・`location` を path 依存で追加し、`flutter build apk --debug` が通ることを確認
- [ ] T006 [P] `analysis_options.yaml` をリポジトリルートに配置し、lint ルール（`flutter_lints` ベース）を全パッケージに適用
- [ ] T007 **依存方向の機械的強制**: `packages/core/` から `location`・`flutter`・地図SDK を import できないことを検査する仕組みを導入（`import_lint` 等）し、`tools/check_import_direction.sh` として実行可能にする
- [ ] T008 [P] GitHub Actions ワークフロー `.github/workflows/ci.yml` を作成（`dart analyze`・`flutter test`・T007 の import 方向チェックを実行）
- [ ] T009 [P] `.gitignore` を Flutter/Android/Dart 向けに整備（`build/`・`.dart_tool/`・`local.properties`・APK 等）
- [ ] T010 [P] `docs/dev-setup.md` を新規作成し、開発環境構築手順（SDK バージョン・Android SDK パス・実機/エミュレータ接続方法）を記録

**Checkpoint**: 空の Flutter アプリが実機/エミュレータで起動し、CI が green

---

## Phase 2: 技術検証スパイク（R1〜R6・ブロッキング）

**Purpose**: plan.md §14 のリスクを潰す。**R1 が落ちたら技術スタックの再検討（plan.md 差し戻し）が必要**なため、本フェーズはすべてのユーザーストーリーに先行する

**⚠️ CRITICAL**: 使い捨てコード可（`prototype/spike-*` ブランチ）。合格基準は plan.md §8・§14 の数値を用いる

- [ ] T011 Flutter 地図プラグインの候補比較（`maplibre_gl` 系 vs 新 `maplibre`）を実機で行い、選定結果と根拠を `specs/001-mvp/research.md` に記録（plan.md §16 の未確定事項①）
- [ ] T012 **R1**: 選定プラグインで**ローカル MBTiles 読込**（`mbtiles://`）が動作することを検証し、結果を `specs/001-mvp/research.md` に追記（不可なら PMTiles → ネイティブビュー埋め込みへフォールバック検討）
- [ ] T013 **R1**: 動的 `addSource`/`addLayer` と `feature-state` 操作が API 経由で可能なことを検証し `specs/001-mvp/research.md` に追記
- [ ] T014 **R2**: fog of war の GeoJSON 穴あきポリゴン方式で性能基準を計測（開示1ヘクス追加の更新 **200ms 以内** / 1万ヘクス開示状態でパン・ズーム **55fps 以上**）し、結果を `specs/001-mvp/research.md` に追記
- [ ] T015 **R3**: Kotlin foreground service で1時間の実歩行（都市部マルチパス含む）を記録し、電池消費と測位品質を計測。距離しきい値の初期値を決定して `specs/001-mvp/research.md` に記録（plan.md §16 の未確定事項②の一部）
- [ ] T016 **R4**: `tools/pack-builder/` の試作で OSM 抽出 → 地形事前計算 → SQLite 出力を1エリア分通し、`docs/terrain.md` §5 の判定ルールどおりの分類が出ることを検証
- [ ] T017 **R5**: モック位置検出と速度判定（移動平均/カルマン平滑後）を試作し、**正規歩行で報酬没収が起きない**ことを実歩行データで確認
- [ ] T018 [P] **R6**: Health Connect の歩数読み取り疎通とオプトイン UX を検証し、Google Play のヘルスデータ申告要件を `specs/001-mvp/research.md` に記録
- [ ] T019 スパイク結果を `specs/001-mvp/plan.md` に反映（プラグイン最終選定・距離しきい値・fog of war 方式の確定）。**plan.md に差分が出る場合は代表承認を得る**（ドキュメントが常に正）

**Checkpoint**: 技術スタックが実機で成立することを確認。R1 が不合格なら plan.md ゲート②に差し戻し

---

## Phase 3: Foundational（基盤・ブロッキング前提）

**Purpose**: 全ユーザーストーリーが依存する core 抽象・データモデル・地域パック・位置記録パイプラインを構築

**⚠️ CRITICAL**: 本フェーズ完了までユーザーストーリーの実装を開始しない

### core の抽象と値オブジェクト（plan.md §5・§2）

- [ ] T020 [P] `packages/core/lib/src/geo/hex_id.dart` に `HexId`（決定論的な緯度経度→ID変換の**結果**を保持する値オブジェクト）を実装。ヘクス幾何や地図SDKには依存しない
- [ ] T021 [P] `packages/core/lib/src/geo/tile_id.dart` に `TileId`、`packages/core/lib/src/geo/distance.dart` に `Distance` を実装
- [ ] T022 [P] `packages/core/lib/src/terrain/terrain_type.dart` に `TerrainType`（空き地/森/山/水辺/海/農地/市街 — `docs/terrain.md` §2）を実装
- [ ] T023 [P] `packages/core/lib/src/position/position_provider.dart` に `PositionProvider` 抽象インターフェースを定義（実装は `location/`。テストではフェイクを注入 — plan.md §10）
- [ ] T024 [P] `packages/core/lib/src/pack/region_pack.dart` に `RegionPack` 抽象（地形属性・区画・POI の読み取り口）と `pack_version` を定義
- [ ] T025 [P] `packages/core/test/geo/hex_id_test.dart` に `HexId` の決定論テスト（同一入力→同一ID）を作成

### 資材・経済のドメインモデル（spec.md §6・buildings.md §6）

- [ ] T026 [P] `packages/core/lib/src/economy/resource.dart` に資材種別を実装（建設系: 木・石・鉄 / 食料系: 塩・水・野菜・フルーツ・**肉**）
- [ ] T027 [P] `packages/core/lib/src/economy/inventory.dart` に `Inventory`（資材の加算・消費・上限）を実装
- [ ] T028 [P] `packages/core/lib/src/terrain/terrain_yield.dart` に地形→資材の一次産出マッピング（森→木、山→石/鉄、水辺→水、海→塩、農地→野菜/フルーツ、市街→産出なし）を実装
- [ ] T029 [P] `packages/core/test/economy/terrain_yield_test.dart` に地形→資材マッピングのテーブル駆動テストを作成

### データ永続化（plan.md §6）

- [ ] T030 SQLite（Drift）を `packages/location/` または `app/` 側に導入し、**ゲーム状態DB**と**地域パックDB（読み取り専用）**を別接続として分離する構成を作る
- [ ] T031 [P] `disclosed_hex` テーブル（開示済みヘクス・`pack_version`）のスキーマとマイグレーションを作成
- [ ] T032 [P] `inventory` テーブルのスキーマとマイグレーションを作成
- [ ] T033 [P] `building` テーブル（建物種別・レベル・建築状態軸・ヘクス座標・区画）のスキーマを作成（`docs/buildings.md` §2）
- [ ] T034 [P] `district_progress`（制覇率・発展度）・`collection`（名所図鑑）・`quest_daily`・`settings` のスキーマを作成
- [ ] T035 **開示ヘクス集合の圧縮表現**を実装（Roaring Bitmap / ビットセット・plan.md §6）。GeoJSON 保持はしない
- [ ] T036 **パック更新の不変性ルール**を実装: 一度開示したヘクスの資材分類は、パック更新後も過去分を不変とする（獲得履歴は当時の `pack_version` で確定 — plan.md §3.3）
- [ ] T037 [P] `packages/core/test/pack/pack_version_immutability_test.dart` にパック更新後も過去の開示・獲得が変わらないことのテストを作成
- [ ] T038 Repository 層の抽象を `packages/core` に定義し、実装を `location`/`app` 側に置く（将来のサーバ同期 #16 に備えた抽象化 — #10 代表回答）

### 地域パック生成パイプライン（plan.md §3・§4）

- [ ] T039 `tools/pack-builder/` に Planetiler/osmium ベースの生成スクリプトを実装（OSM日本抽出 → ベクタタイル MBTiles）
- [ ] T040 `tools/pack-builder/` に **地形属性の事前計算**を実装（`docs/terrain.md` §5 の OSMタグ→地形タイプ判定ルールを細分グリッドセルに適用 → §4 の多数決でヘクスに集約 → SQLite `cell_terrain`/`hex_terrain`）
- [ ] T041 [P] `tools/pack-builder/` に行政区域ポリゴン（国土数値情報 N03・トポロジ保持簡略化）の取り込みを実装
- [ ] T042 [P] `tools/pack-builder/` に名所 POI 抽出（OSM 観光POI → SQLite `poi`）を実装
- [ ] T043 [P] `tools/pack-builder/` にパックメタ（`pack_version`）の付与を実装
- [ ] T044 バーティカルスライス対象エリア（**代表の生活圏を含む約5km四方**・水辺/緑地/農地/市街が混在 — plan.md §15）のパックを生成し、`app/assets/` に**同梱**する
- [ ] T045 [P] パック生成を CI で再現可能にする（`.github/workflows/pack-build.yml`）

### 位置記録パイプライン（plan.md §7・#10）

- [ ] T046 `app/android/` に Kotlin **foreground service** を実装（fused location provider・距離ベースサンプリング・停止中は省電力）
- [ ] T047 位置記録の保存を Kotlin 側からローカルDBへ直接書き込む形で実装し、**Dart は読むだけ**にする（plan.md §2・将来のバックグラウンド対応で作り直さないため）
- [ ] T048 時刻に**単調時計 `elapsedRealtime`** を使用する（端末時刻改竄への耐性 — plan.md §7）
- [ ] T049 **Pigeon** で platform channel の型定義を作成（`pigeons/location_api.dart`）し、生成コードを Dart/Kotlin 双方に組み込む（iOS 移植の正 — plan.md §1-C）
- [ ] T050 [P] `packages/location/lib/src/position/native_position_provider.dart` に `PositionProvider` の実装（Kotlin 側の記録を読む）を作成
- [ ] T051 [P] `packages/core/test/position/fake_position_provider.dart` にフェイク実装と、**録画済み歩行ルートのリプレイテスト基盤**を作成（plan.md §10）

**Checkpoint**: 基盤完成。ここからユーザーストーリーを並列着手できる

---

## Phase 4: US1 — 散歩ユーザー（Priority: P1）🎯 MVP

**Goal**: 通勤・散歩で歩いた場所の**実地図**が開拓され、霧が晴れていく。歩くこと自体がゲーム進行になる

**Independent Test**: 実機で30分歩き、通過した経路のヘクスの霧が晴れ、アプリ再起動後も開示状態が残ること

### Tests for US1

- [ ] T052 [P] [US1] `packages/core/test/disclosure/disclosure_test.dart` に開示判定のテスト（グリッドセル通過→ヘクス開示）を作成
- [ ] T053 [P] [US1] `packages/core/test/disclosure/replay_walk_test.dart` に録画歩行ルートのリプレイで期待どおりのヘクス集合が開示されるテストを作成

### Implementation for US1

- [ ] T054 [US1] `packages/core/lib/src/disclosure/disclosure_service.dart` に開示判定ロジック（通過グリッドセル→ヘクス多数決集約→`disclosed_hex` 更新）を実装。**GPS/地図に依存しない純粋ロジック**
- [ ] T055 [US1] `packages/location/lib/src/map/map_view.dart` に MapLibre 地図表示（同梱 MBTiles をローカル読込）を実装
- [ ] T056 [US1] `packages/location/lib/src/map/fog_of_war_layer.dart` に fog of war を実装（未開示領域を穴あきポリゴン1枚の GeoJSON として差分更新・union は isolate・ビューポート近傍に限定 — plan.md §8）
- [ ] T057 [US1] `app/lib/features/map/map_screen.dart` にマップ画面を実装（`DESIGN.md` のトークンに準拠。色・サイズの直書きをしない）
- [ ] T058 [US1] 現在地表示と地図追従を実装（`app/lib/features/map/`）
- [ ] T059 [US1] 位置記録サービスの起動/停止と権限リクエスト（フォアグラウンド位置のみ）を実装（`app/lib/features/permissions/`）
- [ ] T060 [US1] 開示状態の永続化と復元を実装し、アプリ再起動後も霧の状態が残ることを確認
- [ ] T061 [US1] オフライン蓄積→前景復帰時の状態反映を実装（FR-7・MVP は端末内完結）
- [ ] T062 [P] [US1] 歩行距離・歩数の表示（HUD）を実装（`app/lib/features/map/widgets/`・`DESIGN.md` の HUD 方針に準拠）
- [ ] T063 [US1] **開放ポイント**の入手を実装（自然回復 **1P/日** ＋ GPS移動距離ベースの付与・上限 **50** — `docs/opening_points.md`）
- [ ] T064 [US1] `packages/core/lib/src/opening/opening_point_service.dart` にポイント消費による未踏破ヘクス開放を実装（**1pt/メッシュ**・**開放済みヘクスに隣接するもののみ**・海は開放可・**実在の立入禁止エリアは黒塗りで対象外**）
- [ ] T065 [P] [US1] `packages/core/test/opening/opening_point_test.dart` にポイント経済のテスト（歩行優位が保たれること・隣接制約・上限）を作成

**Checkpoint**: US1 単独で「歩く→霧が晴れる→再起動後も残る」が成立（Fog of World 相当として遊べる）

---

## Phase 5: US2 — 収集ユーザー（Priority: P2）

**Goal**: その土地の地形に応じた資材が手に入り、実在の名所が地図上に現れて「行ってみたい」と思える

**Independent Test**: 森・水辺・市街を含む経路を歩き、地形に応じた資材が付与され、名所オブジェクトが図鑑に記録されること

### Tests for US2

- [ ] T066 [P] [US2] `packages/core/test/economy/resource_grant_test.dart` に開示ヘクスの地形属性→資材付与の決定論テストを作成
- [ ] T067 [P] [US2] `packages/core/test/collection/collection_test.dart` に名所の図鑑登録テスト（現地訪問と遠隔開放の差分ボーナス）を作成

### Implementation for US2

- [ ] T068 [US2] `packages/core/lib/src/economy/resource_grant_service.dart` に資材付与を実装（**地域パックの事前計算済み地形属性を読む純粋関数**・実行時のタイルクエリはしない — plan.md §4）
- [ ] T069 [US2] `packages/location/lib/src/pack/region_pack_repository.dart` に地域パック（SQLite・読み取り専用）へのアクセスを実装
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

- [ ] T082 [US3] `packages/core/lib/src/building/building_type.dart` に建物3系統7種を実装（住宅・マンション / 畑・農場・工場 / リゾート・ミュージアム — `docs/buildings.md` §2）
- [ ] T083 [US3] `packages/core/lib/src/building/build_rule_service.dart` に建築可否判定を実装（**開示済みかつ空き地**・1マス1建物・**リゾートは海に隣接**・**ミュージアムは市街に隣接**）
- [ ] T084 [US3] `packages/core/lib/src/building/build_cost_service.dart` に建設コスト（建設系資材のみ消費）とアップグレード（Lv.1〜3）を実装（`docs/buildings.md` §4）
- [ ] T085 [US3] `packages/core/lib/src/population/population_service.dart` に人口メカニクスを実装（建物ごとの人口上限・時間経過で漸増・総人口の閾値到達で産出倍率ボーナス — `docs/buildings.md` §5）
- [ ] T086 [US3] 生産系建物の産出を実装（畑→野菜/フルーツ、農場→**肉**、工場→街全体の産出効率UP）
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

1. **Flutter SDK のインストール先OS**（Windows / WSL）— T001。リポジトリは WSL、Android SDK は Windows 側にある現状を踏まえて代表判断が必要
2. **plan.md §2 の `android/` 配置** — ルート直下 vs `app/android/`（T002 で確定し plan.md を追記修正）
3. **plan.md §1・§14 の「Issue #1」参照** — GitHub の Issue #1 は「spec-kit 導入」で既にクローズ済み。技術検証スパイク（Phase 2）に対応する Issue が**未起票**のため、起票するか本 tasks.md で代替するかを決める
4. Flutter 地図プラグインの最終選定（T011・plan.md §16）
5. 距離しきい値・`balance.csv` の数値（T015・T106）
6. 地域パックの静的ホスティング先（MVP は同梱のため拡張時に決定）
7. `DESIGN.md` のカラートークン確定値
