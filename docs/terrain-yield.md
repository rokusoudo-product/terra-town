---
type: doc
project: terra-town
doc: 地形産出（受動・時間ベース）の設計と実機確認手順
status: draft
created: 2026-09-11
related:
  - specs/001-mvp/spec.md
  - specs/001-mvp/plan.md
  - docs/terrain.md
  - docs/buildings.md
  - docs/disclosure-and-fog.md
  - https://github.com/rokusoudo-product/terra-town/issues/138
---

# terra-town — 地形産出（受動・時間ベース）の設計と実機確認手順

> Issue #138（T066・T068）で実装した「開示済みヘクスから時間の経過とともに資材が
> 増える」仕組みの設計・二重計上防止（ウォーターマーク）の方式・実機確認手順を
> まとめる。`docs/disclosure-and-fog.md`（開示・霧）と対をなす、経済まわりの
> 実装ドキュメント。

## 1. 何を実装したか（`spec.md` §6 より）

> 入手（地形産出＝受動・薄く常時）: 開示メッシュの地物特性に連動し、開示済みであれば
> 操作なしに継続的に産出される（森→木、山→石/鉄、水辺→水、海→塩）。

**仮値（2026-09-11 代表決定）**: 1ヘクスあたり、その地形の産出資材それぞれ
**1時間に1個**。貯められる上限は設けない。数値の正本は
`specs/001-mvp/balance.csv`（Issue #36・T106・**未作成**）であり、作成された際は
そちらへ移す（`packages/core/lib/src/economy/resource_grant_service.dart` の
`terrainYieldAmountPerHexPerUnit` 定数のコメント参照）。**本 Issue の時点では
`balance.csv` は作らない。**

## 2. 全体の流れ

```
NativePositionProvider.recordedPositionUpdates（packages/location・行id付き）
  → TerrainYieldPipeline（app/lib/map/economy/terrain_yield_pipeline.dart）
      位置1件ごとに、次の2ステップを直列に（両方awaitして）実行する:
      1. TerrainYieldAccrualCoordinator.accrue
         - 直前の点と同一セッションの場合のみ、経過時間（単調時計の差分）を計算
         - computeTerrainYieldAccrual（core・純粋関数）で資材付与量・端数を計算
           （このとき使う「開示済みヘクスの地形別件数」は、後述2.の開示より前の
           スナップショット）
         - TerrainYieldLedger.applyAccrual で「資材加算・端数・ウォーターマーク」
           を1トランザクションとして永続化
      2. DisclosureService.recordPosition（既存・Issue #101/#137）
         - 新規開示なら TerrainHexCounter を更新し、reveal で霧を解除する
  → 次の位置へ
```

同じストリームに2つ目のリスナーを追加しない（`terrain_yield_pipeline.dart`
クラスdoc「なぜ1本の直列パイプラインにするか」参照）。以前
（Issue #137）は `DisclosureCoordinator` が単独でこの役割（開示判定→霧の解除）を
担っていたが、composition root（`app/lib/features/map/map_screen.dart`）は
`TerrainYieldPipeline` に置き換えた。`DisclosureCoordinator` はクラス・テストとして
残っている（他所からの再利用や、単体テストの記述に使える）が、本番の位置ストリーム
（`recordedPositionUpdates`）は購読しない。

## 3. ウォーターマークの方式（二重計上防止・重要な設計判断）

### 3.1 何をウォーターマークにするか

**「最後に計上した位置記録の行id」**（`location_point.id`。Pigeon の
`LocationPointMessage.id`）をウォーターマークとする。settings テーブルの
`terrain_yield.watermark_row_id` キーに保存する（`TerrainYieldLedger`）。

**セッションIDと単調時刻の組をウォーターマークにしない。** そのセッションの行が
（何らかの理由で）存在しなくなった場合、永久に計上が止まってしまう危険がある
ため（行idは常に単調増加・一意であり、この危険が構造的に無い）。

### 3.2 なぜ「直前の点（prev）」を別途保存しなくてよいか

`NativePositionProvider` は起動のたびに記録の先頭（`sinceRowId = 0`）から全件を
再生する（Issue #124・#131 からの既存の設計）。`TerrainYieldAccrualCoordinator`
はこれを利用し、**ウォーターマークの行そのものが再生されてきた瞬間に、その行を
「直前の点（prev）」として復元する**（アプリ内メモリ上の状態のみで完結し、
settings に別途セッションID・単調時刻を保存する必要が無い）。

具体的には、`accrue(record, hexCountByTerrain)` は次の規則で動く:

- `record.rowId <= watermarkRowId`（既に計上済みの行、またはウォーターマーク
  そのもの）: **一切書き込みを行わない**が、内部の `_previous` は必ず
  `record` に更新する。
- `record.rowId > watermarkRowId`（新しい行）: `_previous` と同一セッションの
  場合のみ経過時間を計算し、`computeTerrainYieldAccrual` → `TerrainYieldLedger`
  （1トランザクション）→ 内部状態（`_previous`・ウォーターマーク・端数）の更新、
  という順で処理する。

このため、再起動直後の全件再生では「ウォーターマークの行までは何もしないが
`_previous` だけ更新され続け、ウォーターマークの次の行が来た瞬間に正しい区間
（`prev` → 新しい行）として計上が再開する」という挙動になる。

### 3.3 二重計上防止のトランザクション

`TerrainYieldLedger.applyAccrual` は「資材の加算（`inventory` テーブル）」と
「端数・ウォーターマークの更新（`settings` テーブル）」を**1つの
`GameDatabase.transaction` で行う**。アプリがクラッシュする等でこの
トランザクションが完了しなかった場合、SQLiteのトランザクションはロールバック
され、**資材もウォーターマークもどちらも進まない**。次回起動時は同じ区間が
改めて計上される（失われない）。`packages/location/test/db/terrain_yield_ledger_test.dart`
で、意図的に失敗させたときにロールバックされることを検証している。

### 3.4 受け入れ基準との対応

| 受け入れ基準 | 検証箇所 |
|---|---|
| (a) 起動のたびに全件が流れ直しても計上済みの区間を飛ばす | `terrain_yield_accrual_coordinator_test.dart` |
| (b) 再起動をまたいでも最初の未計上区間が失われない | 同上（ウォーターマークの行がprevとして復元されるテスト） |
| (c) ウォーターマークより新しい行が無ければ何も起きない | 同上 |
| (d) 計上の途中で失敗したら資材もウォーターマークも進まない | `terrain_yield_ledger_test.dart`（DB層のロールバック）・`terrain_yield_accrual_coordinator_test.dart`（内部状態が進まないこと） |

## 4. 端数（1時間未満の産出）を失わない

`computeTerrainYieldAccrual`（`packages/core`）は整数演算のみを使う。資材ごとに
「寄与ヘクス数 × 経過マイクロ秒 × 1（仮の基礎産出量）」を、持ち越された端数
〔マイクロ秒〕に加算し、1時間のマイクロ秒（`Duration.microsecondsPerHour`）で
整数除算する。商を付与量、余りを次回への端数として返す。**区間を細かく分けて
何度呼び出しても、合計の付与量は1回で呼び出した場合と一致する**
（`packages/core/test/economy/resource_grant_test.dart`「分割しても合計が
変わらない」グループで証明）。

## 5. 「区間開始時点の開示済みヘクス」を使う（決定論）

位置 p(i) を処理するとき、区間 (p(i-1), p(i)] の産出は「p(i) を開示する**前**の
開示済み集合」で計上し、そのあとで p(i) の開示（新規なら霧の解除）を行う。
`TerrainYieldPipeline` が `accrualCoordinator.accrue` → `disclosureService.
recordPosition` の順で必ず await することでこれを保証する
（`terrain_yield_pipeline_test.dart`「区間の産出には区間開始時点の開示済みヘクスを
使う」で検証）。

`TerrainHexCounter`（`packages/core`）は開示済みヘクスの地形別件数を保持する
派生インデックス（正は `disclosed_hex` テーブル）で、アプリ起動時に
`DisclosedHexRepository.findAll()` から作り直し（`TerrainYieldPipeline.start`）、
新規開示のたびに `increment` する。

## 6. 「アプリを閉じている間は産出しない」の解釈（判断の記録）

Issue #138 の決定事項1「産出するのはサービスが動いている間だけ」「アプリを
閉じている間・サービス停止中は産出しない」について、次のように解釈して実装した:

- 位置記録サービス（Kotlin foreground service）は、アプリの**画面**を閉じても
  動き続けることがある（`docs/location-track-db.md` 参照）。その間に記録された
  位置は、次にアプリを開いたときに `NativePositionProvider` の全件再生で
  Dart側に届き、`TerrainYieldPipeline` によって計上される。
- これは「サービスが実際に稼働していた時間」の産出であり、決定事項1の
  「サービス稼働中だけ産出する」には合致すると解釈した。**サービス自体を
  完全に停止した（フォアグラウンドサービスが終了した）区間は、そもそも
  `location_point` に行が記録されないため、その間の時間は経過時間の計算に
  一切登場しない**（前後の記録の時刻差にその停止時間が含まれてしまうことは
  ない。停止中は新しい行が生まれないため）。

  ただし、**サービスが「アプリの画面を閉じても動き続ける」ことと「アプリを
  閉じている間は産出しない」という Issue 本文の文言の間に、解釈の余地がある**
  （代表がどちらを意図していたか要確認）。本実装は前者（サービスの実際の稼働
  時間で判定する。既存の decision "サービス稼働中のみ"・"壁時計不使用" と
  整合する解釈）を採用した。PR本文の「判断に迷った点」にも記載する。

## 7. デバッグパネル（`kDebugMode` 限定）

`app/lib/map/debug/terrain_yield_debug_panel.dart`（`TerrainYieldDebugPanel`）が
次を表示する:

- 資材ごとの所持数と、次の1個までの進み具合（端数を%表示）
- 開示済みヘクスの地形別の件数
- ウォーターマーク（最後に計上した行id）
- 起動後に処理した位置の件数・最後に処理した位置の行id・単調時刻・現在のセッションID

1個/時間の仮値だと整数の増加を見るには最大1時間かかるため、端数の%表示が
実機確認の要（産出が止まっているのか、単に1個に達していないだけなのかを
区別できる）。

## 8. 実機で確認する手順（秘書セッションが行う。代表の端末はパック範囲外）

1. `docs/disclosure-and-fog.md` §4.1 の手順で `flutter build apk --debug` を
   インストールする。
2. 「位置記録 デバッグパネル」の「起動」でサービスを開始する。
3. 「開示 デバッグパネル」の「地図の中心のヘクスを開示」で、地図中心に最も近い
   パック内ヘクスを開示する（本ボタンは地形カウンタを更新するが、地形産出の
   計上そのものは行わない。§9参照）。
4. 数分待ってから「地形産出 デバッグパネル」を見る。もし開示したヘクスが
   産出資材を持つ地形（森・山・水辺・海のいずれか）なら、端数（%）が
   少しずつ増えていくことを確認する（新しい位置の行が届くたびにしか進まない点に
   注意。「処理した位置」の件数・最後の行idが増えているのに端数が増えない
   場合は不具合の可能性がある）。
5. 「停止」でサービスを止め、数分待っても端数・所持数が増えないことを確認する
   （サービス停止中は新しい行が記録されないため）。
6. `adb shell am force-stop jp.rokusoudo.terra_town` でアプリを完全終了し、
   再起動する。地形産出デバッグパネルの所持数・端数が、force-stop 直前の値から
   **二重に増えていない**（同じ区間が2回計上されていない）ことを確認する。
7. 再起動後、サービスを再度「起動」し、数分待って産出が再開する（続きから
   増える）ことを確認する。

## 9. 「地図の中心のヘクスを開示」ボタンと地形産出の関係（判断の記録）

`DisclosureDebugPanel`（Issue #137）の手動開示ボタンは `TerrainYieldPipeline.
recordManualPosition` を呼ぶ。これは位置記録サービス由来の行id・経過時間の
概念を持たない一発の観測のため、**地形産出の計上は行わない**（開示・霧の解除・
`TerrainHexCounter` の更新のみ行う）。§8手順の「代表の端末はパック範囲外」の
制約から、このボタンで開示したヘクスも地形産出の**対象**（開示済みヘクスの
地形別件数に含まれる）には含めるが、このボタンを押した**瞬間に**資材が
増えるわけではない。以後、位置記録サービスが稼働し新しい行が届くたびに、
このヘクスの分も含めて時間ベースで産出が計上される。
