# terra-town — エージェント向け設定

GPS×実地図の街育成ゲーム。Android 先行・将来 iOS。spec-kit（仕様書ファースト）で開発する。

## ドキュメントの正
- 仕様（何を・なぜ）: [`specs/001-mvp/spec.md`](specs/001-mvp/spec.md)（ゲート①承認済み）
- 実装計画（どう作るか）: [`specs/001-mvp/plan.md`](specs/001-mvp/plan.md)（ゲート②承認済み）
- 地形・エリア定義の正: [`docs/terrain.md`](docs/terrain.md)（ヘクス約50m折衷方式）
- 環境構成図: [`docs/architecture.md`](docs/architecture.md)
- **UIは [`DESIGN.md`](DESIGN.md) に準拠する**（Material 3 ＋ 独自トークン。カラーコード・サイズの直書き禁止、トークン経由）

## アーキテクチャ制約（必守）
- `core/`（ゲームロジックの純粋実装）は `location/`（GPS・地図SDK）を **import しない**一方向依存（`C:\Users\moets\.claude\GPS_ARCHITECTURE.md` 準拠）。core は別 Dart パッケージ（`packages/core`）で物理分離する。
- 技術スタック: Flutter ＋ MapLibre GL Native ＋ 機微処理は Kotlin ネイティブ（Pigeon channel）。
- MVP は端末内完結（ステートフルなBEなし）。タイル・地形属性・区画・POI は「地域パック」に束ねる（plan.md §3・§4）。
- 資材分類は実行時タイルクエリではなく **CI で事前計算**した属性を参照する（決定論保証。plan.md §4）。

## 開発フロー
- Issue 駆動（1 Issue = 1 機能）。実装可能条件 = `ready` ラベルあり かつ `question` ラベルなし。
- 仕様変更はコードより先に `specs/` を更新して差分承認を得る（ドキュメントが常に正）。
- 構成が変わる実装をしたら、同じコミットで `docs/architecture.md` と README も更新する。
