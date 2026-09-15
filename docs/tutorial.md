---
type: spec
project: terra-town
doc: チュートリアル（開始時の資材）付与の仕様
status: approved            # 2026-09-15 代表決定（Issue #184）
created: 2026-09-15
updated: 2026-09-15
related:
  - specs/001-mvp/spec.md
  - specs/001-mvp/plan.md
  - specs/001-mvp/balance.yaml
  - docs/location-track-db.md
  - DESIGN.md
  - https://github.com/rokusoudo-product/terra-town/issues/184
  - https://github.com/rokusoudo-product/terra-town/issues/36
  - https://github.com/rokusoudo-product/terra-town/issues/180
supersedes: null
---

# terra-town — チュートリアル（開始時の資材）付与の仕様

> 本書は [Issue #184](https://github.com/rokusoudo-product/terra-town/issues/184) の受け入れ基準を満たすための設計ドキュメント。
> `specs/001-mvp/spec.md` §7.1（チュートリアル・開始時の資材）を具体化する。
> **MVP の範囲は本書が定義する「付与」のみ。チュートリアルの案内の画面（何をどの順で案内するか）は対象外（MVP 後・別 Issue）。**
> 実装は `tasks.md` T116（本書の付与）・T117（MVP 後の案内画面）に分けて行う。

## 1. 背景・目的

- `plan.md` §15 のバーティカルスライス完了の定義は「実際に30分歩いて、霧が晴れ、資材が貯まり、建物が1つ建ち、アプリ再起動後も状態が残る」。
- 2026-09-15 の数値検討（Issue #36）で、現行の地形産出（地形産出は森1ヘクスにつき1時間に木1個・`docs/terrain-yield.md`）だけでは、30分歩いても最も安い建物（畑＝木10）すら建たないことが判明した。
- **2026-09-15 代表決定**: 「チュートリアルを実装する。チュートリアルでは建設可能な建物を建てられるだけの資材を最初に持つ」。開始地点（森・山の近さ）に依存せず、最初の空き地を歩いて開示すれば建物が建つようにする（`spec.md` §7 の「開始地点に依存せず」という進行曲線の設計意図と整合）。

## 2. 開始時の資材

- **木50・石10**。畑（木10）・採石場（木20）・住宅（木20・石10）を1棟ずつ建てられる量。
- 工場・マンションなど鉄を使う建物はこの資材だけでは建たない。その先は採石場の産出（`docs/buildings.md` §4）と歩行で貯める。
- 数値の正本は `specs/001-mvp/balance.yaml`（Issue #36）の `starting_resources`（`wood.value: 50` / `stone.value: 10`）。本書はこの値を参照するのみで、値自体は保持しない（正本の重複を避ける）。同ファイルは「付与フロー自体は別Issueで定義する」と明記しており、本書がその付与フローにあたる。

## 3. 付与のタイミングと1回だけ付与する仕組み

- **1回だけ付与する**。付与済みかどうかは `packages/location` の `GameDatabase` が管理する `settings` テーブル（`Settings` テーブル・`key`/`value` の2カラム。`docs/location-track-db.md` §4 で言及される既存のキー・バリュー保存先で、`RewardSettingsRepository` が同テーブルを使う既存パターンを踏襲する）にキー `tutorial.initial_resources_granted` として持つ。
- 起動時（アプリ起動直後、他の初期化処理と同様のタイミング）に `settings` テーブルを確認し、キーが存在しなければ次を行う。
  1. `inventory` テーブル（`Inventories`・`resourceKey`/`amount`）の `wood`/`stone` に木50・石10 を加算する。
  2. `settings` に `tutorial.initial_resources_granted` を書き込む。**値は判定に使わない**（キーの存在有無だけで判定する）ため、任意の固定文字列（例: `"1"`）でよい。本プロジェクトは端末の壁時計を信用しない方針（`docs/opening_points.md` §2.1・plan.md §7）のため、付与日時のような壁時計由来の値を持たせない。
  3. §4 の通知を表示する。
- **1（資材の加算）と 2（印の書き込み）は、`GameDatabase` の同じトランザクションで行う。** 片方だけが保存された状態でアプリが終了すると、次回起動時に二重に付与される（または付与されないまま印だけが残る）ため。通知（3）はトランザクションの確定後に表示する。
- **既にデータがある端末**（新規インストールではなく、本機能より前のバージョンから使い続けている端末）にも、キーが無い限り同じ手順で1回だけ付与する。新規端末と既存端末で分岐しない（キーの有無だけを条件にすることで自然に両対応する）。

## 4. 利用者への通知

- 付与した直後に、利用者へ通知する。**見せ方（コンポーネント・色トークン）は `DESIGN.md`「プロジェクト固有ルール」の「初回資材付与（チュートリアル）の通知」に定義する**（本書は「通知すること」自体の要件のみを持ち、見た目の決定は `DESIGN.md` に委ねる。数値・色の二重管理を避ける）。

## 5. セーブデータの読み込み（エクスポート/インポート）時の扱い

- Issue #180 で実装したセーブデータのエクスポート/インポート（`packages/location/lib/src/save_data/`）は、`GameDatabase` の7テーブルすべて（`settings` を含む）を書き出し・読み込みの対象にしている（`save_data_codec.dart`）。読み込み（`save_data_transfer_service.dart` の `importFromJsonString`）は対象テーブルを全削除してから読み込んだ内容を挿入する「入れ替え」方式であり、`settings` テーブルもこの対象に含まれる。
- そのため、**セーブデータを読み込むと `settings` テーブルごと入れ替わり、`tutorial.initial_resources_granted` の印も書き出し元の状態に一緒に移る**。印を持つファイルを読み込めば「付与済み」の状態のまま維持される。
- **印を持たない古い書き出しファイル**（本機能を実装する前のバージョンで書き出したファイル）を読み込んだ場合は、印が無い状態になるため、次回起動時に §3 の手順でもう一度付与される（二重付与になる）。
  - この状況が起こり得るのは、本機能より前のバージョンで書き出したファイルを保存しておいて、本機能を含む新しいバージョンに読み込ませる場合のみである。一般利用者が新規にエクスポートするファイルは常に印を含むため対象にならない。
  - **開発端末でしか起きない前提として許容する**（2026-09-15 代表決定の一部。Issue #184 提案内容 参照）。一般利用者向けの救済策（読み込み時の重複防止・警告表示等）は本 Issue の対象外とする。

## 6. MVP との関係・対象外

- MVP に含むのは本書 §3・§5 の**付与**のみ（`tasks.md` T116。plan.md §15 のバーティカルスライス完了判定 T110 の前提条件）。
- チュートリアルの**案内の画面**（何をどの順で案内するか。例: 「まず畑を建てましょう」等のガイド表示）は MVP 後に作る（`tasks.md` T117）。中身の検討は本 Issue の対象外とし、別 Issue で扱う。
- 建物そのものの実装（`tasks.md` T082〜T090）・数値ファイルの作成（Issue #36）は本書の対象外。

## 参考

- Obsidian `Specs/terra-town/20260915_balance_proposal.md`（数値の提案と代表回答）
- `specs/001-mvp/spec.md` §7.1・§7、`specs/001-mvp/plan.md` §15、`docs/buildings.md` §4、`docs/terrain-yield.md`
- Issue #36（数値の正本・`balance.yaml`）、#180（セーブデータの書き出し/読み込み）、#184（本書の起点）
