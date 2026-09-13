---
type: impl-note
project: terra-town
doc: 開放ポイントの消費（未踏破ヘクスの開放）の実装と実機確認手順
created: 2026-09-13
related:
  - docs/opening_points.md
  - docs/opening-points-impl.md
  - specs/001-mvp/tasks.md（T064・T065）
  - https://github.com/rokusoudo-product/terra-town/issues/151
---

# terra-town — 開放ポイントの消費（ヘクス開放）の設計と実機確認手順

`docs/opening_points.md` §5・§6 が定める「開放ポイントを消費して未踏破ヘクスを
開放する」機能（Issue #151・T064・T065）の実装をまとめる。入手側
（歩行距離換算・Issue #143）は `docs/opening-points-impl.md` を参照。

## 1. 何を実装したか

- `packages/core/lib/src/opening/opening_point_service.dart`
  `evaluateHexOpening`（純粋関数）: 隣接制約・コスト（1pt/メッシュ固定）・
  ポイント残高・既に開示済みでないかを判定する。海は開放可。
- `packages/location/lib/src/db/hex_opening_spend_service.dart`
  `HexOpeningSpendService`: ポイントの減算と `disclosed_hex` への保存を
  **1つのDriftトランザクション**で行う実処理。
- `app/lib/map/economy/terrain_yield_pipeline.dart` の
  `TerrainYieldPipeline.openHexWithPoints`: 上記2つを繋ぎ、成功時は
  `disclosureService.known` への追加・`terrainHexCounter` の増分・fog解除
  （`reveal`）・HUD用キャッシュの同期までを行う composition。
  `grantOpeningPointsForDebug`: `kDebugMode` 限定のデバッグ付与。
- `app/lib/features/map/widgets/hex_opening_sheet.dart`: タップ時に表示する
  モーダルボトムシート（製品UI）。

## 2. タップされたヘクスの特定方法（重要）

Dart 側には H3 の実行時変換手段が無い（`hex_locator.dart` クラスdoc参照。
歩行時は Kotlin 側 `H3HexIndexer` が記録時点で確定済みの値を渡すだけ）ため、
任意の画面タップ座標からヘクスを求める経路が別途必要だった。

採用した方式:

1. `MapView`（`packages/location/lib/src/map/map_view.dart`）に
   `onFogHexTapped(int featureId)` を追加。`onFogHexTapped` が渡されている
   場合のみ `MapLibreMap.onMapClick` を購読し、タップ地点で
   `controller.queryRenderedFeatures(point, [fogLayerId], null)` を呼ぶ。
   fog of war レイヤーは開示済み・未開示問わず全ヘクスがソースに存在し続ける
   （開示済みは `fill-opacity: 0` になるだけ）ため、原理上どちらのヘクスを
   タップしても地物が見つかる想定——**ただし実機では未検証**（後述§6）。
2. 見つかった地物の直下の整数 `id`（＝ `feature_id`。H3 indexの下位52bit
   マスク・`hex_bridge.py`/`hex_feature_bridge.dart`）をそのまま
   composition root（`map_screen.dart`）へ渡す。
3. composition root は起動時に一度だけ、`fogHexFeatureCollection`
   （fog of war 描画に使っているのと同じインスタンス。各Featureの
   `properties.hex_id_str` に H3 index を文字列化して保持済み・
   `fog_hex_source.dart`）から `feature_id → HexId` の逆引き表を組み立てる
   （`app/lib/map/hex_feature_lookup.dart` の `buildHexIdByFeatureId`）。
   地域パックへの追加のDBアクセスは発生しない。

`app/lib/map/debug/nearest_pack_hex.dart`（デバッグパネル「地図中心のヘクスを
開示」）が既に同じ `properties.hex_id_str` を読む手法を使っており、本実装は
それを製品UI向けに一般化したものにあたる。

## 3. 消費と開示の同一トランザクション

`HexOpeningSpendService.spend` は次を1つの `GameDatabase.transaction` で行う:

1. `DisclosedHexRepository.findById` で既に開示済みでないか再確認する
   （`DisclosedHexRepository.save` の `insertOrIgnore` に任せない。任せると
   「開放は失敗したのにポイントだけ減る」誤りを見逃す）。
2. 残高を再読込し、コスト（1pt）以上あるか確認する。
3. 残高を減算し、`DisclosedHex` を保存する。

途中で例外が起きればロールバックされ、ポイント・開示状態のどちらも変化しない
（`hex_opening_spend_service_test.dart`「トランザクションの原子性」で検証）。

隣接制約（`notAdjacentToDisclosed`）・パック範囲外（`outsidePack`）は
トランザクションの外（`evaluateHexOpening`）で判定する。これらは一度真に
なった状態が偽に戻ることがない性質（開示は単調に増える一方）を利用した
判断であり、advisor 指摘のとおりトランザクション内での再確認は不要とした。

## 4. 入手（歩行距離換算）との競合

`opening_point.points` への書き手が「歩行距離換算の計上
（`OpeningPointLedger.applyAccrual`）」と「ヘクス開放
（`HexOpeningSpendService.spend`）」の2つになった。

- **DB上の整合性**: Drift の `transaction()` は同一コネクション上で排他的に
  実行される（`_StatementBasedTransactionExecutor.ensureOpen` が
  「Block the main database... while this transaction is active」と明記。
  実装上も親executorの `_lock` を掴んだままBEGIN〜COMMIT/ROLLBACKまで
  保持し続ける）。そのため2つの操作がほぼ同時に発行されても、片方が完全に
  確定してからもう片方が開始し、ロストアップデートは起きない
  （`hex_opening_spend_service_test.dart`「入手と消費が同時に起きても
  残高が食い違わない」で検証）。
- **呼び出し側キャッシュの整合性**: `OpeningPointAccrualCoordinator._points`
  は「自分が書いた量」しか知らないメモリ上のキャッシュのため、2人目の
  書き手（消費）の存在を前提に、`OpeningPointLedgerStore.applyAccrual` の
  戻り値を「書き込み後の実残高」に変更し、呼び出し側は `+=` ではなく
  **代入**するよう変更した（`OpeningPointAccrualCoordinator.
  syncPointsAfterExternalChange`）。あわせて `OpeningPointLedger.applyAccrual`
  自体も、呼び出し側のキャッシュが古くなっていた場合の安全網として、
  トランザクション内で読み直した実残高を基準に最終的に上限（50P）を
  クランプするよう変更した（`opening_point_ledger.dart` クラスdoc参照）。

## 5. 開放元（ポイント開放／歩行開示）の区別（判断の記録）

`disclosed_hex` に開放元を示す列を追加すれば区別できるが、**本Issueでは
追加しない**。理由:

- T072「現地訪問時の追加ボーナス」の要件がまだ確定していない段階で列を
  追加すると、実際の要件確定後にスキーマの形が合わずもう一度マイグレーション
  （移行テスト込み）が必要になる可能性が高い。
- ゲーム自体が一度もリリースされていない（`game_database.dart` の
  v1→v2マイグレーションのコメント「本Issueの対象バージョンは...一度も
  リリースされていない」と同じ状況。2026-09-13時点でタグ・Releaseとも無し）
  ため、今スキーマを変えても実データ移行の実地検証ができない。

**T072 の要件が固まった時点でのマイグレーション方針（先出し）**:
`disclosed_hex` に `disclosure_source`（`textEnum` 等。値は例えば
`walked` / `spentPoints`）列を追加し、`schemaVersion` を上げたうえで
`stepByStep`（`ALTER TABLE ... ADD COLUMN disclosure_source TEXT NOT NULL
DEFAULT 'walked'`）で移行する。**テーブル再作成方式は使わない**——
その時点では既にリリース済み・実データが載っている可能性があるため、
`game_database.dart` の v1→v2 とは異なり実データを保持する移行が必須になる。
移行テスト（既存行が `walked` として読めること）を必ず書く。

## 6. UI（最小限・モーダルボトムシート）

`HexOpeningSheet`（`app/lib/features/map/widgets/hex_opening_sheet.dart`）を
地図タップ時にのみ表示する。地形タイプ・開放可否・不可の理由（残高不足／
隣接していない／開示済み／パック範囲外）をテキスト＋アイコンで示すだけの
最小限のUI。

**配置についての判断**: 過去4回（Issue #137・#138・#141・#142）、新設したUI
要素が既存の製品ボタン（追従・記録開始・HUD等）を覆う不具合が繰り返された。
本UIは固定位置に常時表示するボタン・パネルを追加せず、タップした時だけ
現れて閉じれば何も残らないモーダルボトムシートにすることで、この種の不具合が
構造的に起こらないようにした。既存の製品UI（左上HUD・下中央記録ボタン・
右下追従ボタン・左下MapLibreロゴ・右上デバッグトグル）とは何も重ならない
（新規の固定配置要素が無いため確認自体が不要）。

## 7. デバッグパネル（`kDebugMode` 限定）

`OpeningPointDebugPanel` に「デバッグ付与: +10P」ボタンを追加した
（`TerrainYieldPipeline.grantOpeningPointsForDebug` を呼ぶ）。歩かずに
ポイントを用意し、ヘクス開放を試せるようにするため（release ビルドの
製品UIには一切出ない。パネル自体が `kDebugMode` 限定であることに加え、
`grantOpeningPointsForDebug` 自身も冒頭で `kDebugMode` を確認する多重の
安全策）。

## 8. 実機で確認する手順（秘書セッションが行う。実機では未確認）

前提（2026-09-13時点の秘書の端末）: 開示済みヘクスは2件（狭山湖パック内・
森1・空き地1）、開放ポイントは0P。

1. アプリを起動し、`kDebugMode` のデバッグパネル一括表示トグル（右上）を
   押して開く。`OpeningPointDebugPanel` の「デバッグ付与: +10P」を1回押す
   （所持ポイントが10になることを確認）。
2. 地図上で、既に開示済みの2ヘクス（森・空き地）のいずれかに**隣接する**
   未開示のヘクスをタップする。
   - モーダルボトムシートが開き、地形タイプと「所持ポイント10P（コスト1P）」
     が表示され、「開放ポイントを1P使って開放する」ボタンが押せることを
     確認する。
   - ボタンを押し、「開放しました」と表示され、シートを閉じた後に地図上の
     霧が晴れていることを確認する（fog層が透明になる）。
   - デバッグパネルの所持ポイントが9に減っていることを確認する。
3. 隣接していない（遠く離れた）ヘクスをタップし、シートに「開示済みの
   ヘクスに隣接していません」と表示され、ボタンが押せない（グレーアウト）
   ことを確認する。
4. 既に開示済みのヘクス（元々の2件、または手順2で開放したヘクス）を
   タップし、シートに「既に開示済みです」と表示されることを確認する。
5. デバッグパネルで所持ポイントを0まで使い切った状態（または最初から
   デバッグ付与をしない状態）で、隣接する未開示ヘクスをタップし、
   「開放ポイントが足りません」と表示されボタンが押せないことを確認する。
6. （余裕があれば）海に隣接する未開示ヘクスがあれば、それも開放できる
   ことを確認する（狭山湖パック内に該当ヘクスが無い場合はスキップ）。

**確認できないこと（実機で追加検証が必要な既知の未検証事項）**:

- `queryRenderedFeatures` が `fill-opacity: 0`（開示済み）の地物も返すか
  （§2「タップされたヘクスの特定方法」参照。返さない場合、開示済みヘクスの
  タップで「既に開示済みです」の判定に到達できず、シート自体が開かない
  可能性がある）。
