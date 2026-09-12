---
type: doc
project: terra-town
doc: 開放ポイントの入手（歩行距離換算）の設計と実機確認手順
status: draft
created: 2026-09-13
related:
  - specs/001-mvp/spec.md
  - specs/001-mvp/plan.md
  - docs/opening_points.md
  - docs/terrain-yield.md
  - https://github.com/rokusoudo-product/terra-town/issues/143
---

# terra-town — 開放ポイントの入手（歩行距離換算）の設計と実機確認手順

> Issue #143（T063）で実装した「歩いた距離に応じて開放ポイントが増える」仕組みの
> 設計・二重計上防止（ウォーターマーク）の方式・実機確認手順をまとめる。
> `docs/terrain-yield.md`（地形産出）と対をなす、経済まわりの実装ドキュメント。
> 正本は引き続き `docs/opening_points.md`（本書はその実装の記録）。

## 1. 何を実装したか（`docs/opening_points.md` §2.2 より）

> 歩いた distance（GPS移動距離の累積）に応じて開放ポイントを付与する。
> 換算レート: 1.5km = 1P（2026-09-12 代表決定で確定）。

**実装したのは歩行距離換算（§2.2）のみ。自然回復（§2.1・1P/日）は実装していない**
（§6参照）。上限50P（超過分は切り捨て・§4）は歩行距離換算にもそのまま適用する。

数値（1.5km=1P・上限50P）は代表決定により確定した値だが、正本は引き続き
`specs/001-mvp/balance.csv`（Issue #36・T106・**未作成**）であり、同ファイル作成時は
`packages/core/lib/src/economy/opening_point_accrual_service.dart` の
`openingPointDistanceMillimetersPerPoint`・`openingPointStockCap` の差し替え元をそちらに
変更すること。**本 Issue（#143）のスコープでは `balance.csv` は作らない。**

## 2. 全体の流れ

```
NativePositionProvider.recordedPositionUpdates（packages/location・行id付き）
  → TerrainYieldPipeline（app/lib/map/economy/terrain_yield_pipeline.dart）
      位置1件ごとに、次の3ステップを直列に（すべてawaitして）実行する:
      1. TerrainYieldAccrualCoordinator.accrue（地形産出・既存）
      2. OpeningPointAccrualCoordinator.accrue（本Issue）
         - 直近の移動窓（既定120秒）に新しい点を加え、RewardPolicy.classify で
           最後の区間の移動距離・付与倍率を得る
         - computeOpeningPointAccrual（core・純粋関数）でポイント付与量・端数を計算
         - OpeningPointLedger.applyAccrual で「ポイント加算・端数・ウォーターマーク」
           を1トランザクションとして永続化
      3. DisclosureService.recordPosition（既存）
  → 次の位置へ
```

**新たな位置ストリームの購読は追加していない**（`terrain_yield_pipeline.dart`
クラスdoc「なぜ1本の直列パイプラインにするか」参照）。既存の `TerrainYieldPipeline`
へ処理ステップを1つ足す形で実装した。

## 3. なぜ「窓（直近数点の履歴）」が必要か（地形産出との違い）

地形産出（Issue #138）は「直前の1点との差分（経過時間）」だけで計算できたが、
開放ポイントは `RewardPolicy.classify` の付与倍率（速度超過・歩数不一致の判定）が
**移動平均**（既定120秒の時間窓。`SpeedFilter.smoothingWindow`・
`RewardPolicy.stepWindow`）を使うため、直前の1点だけでなく直近の窓ぶんの
`GeoPosition` が無いと正しい倍率が得られない（1区間〔2点〕だけを渡すと平滑化が
効かず、常に生の値で判定してしまう）。

`OpeningPointAccrualCoordinator` は新しい位置が届くたびに「既存の窓＋新しい位置」の
候補窓を作り、直近 `_maxWindowDuration`（速度平滑化窓・歩数突合窓のうち長い方。
既定は両方120秒）を超える古い点を先頭から除いたうえで
`rewardPolicy.classify(候補窓)` を呼び、**その結果の最後の区間**だけを開放ポイントの
計算に使う。窓を無制限に保持しないのは、`classify` の呼び出しコストがセッション長に
比例して増え続けるのを防ぐため（`SpeedFilter`・歩数ウィンドウ自身も同じ時間窓しか
見ないため、これより長く保持しても判定結果は変わらない）。

## 4. 付与倍率の適用（Issue #126・#135 が実際に効く最初の実装）

`RewardPolicy.classify` が返す区間ごとの倍率をそのまま「距離の重み」として使う:

| 状況 | 倍率 | 距離の扱い |
|---|---|---|
| モック位置疑い | 0 | 距離をどれだけ歩いても加算されない |
| 速度超過（時速10km超・平滑化後） | 0 | 同上 |
| 歩数不一致（既定0.5。Issue #135 の設定でオフに出来る） | 0.5 | **区間の移動距離を半分として積算する** |
| それ以外 | 1 | 実測距離をそのまま積算する |

**倍率0.5のときの距離の扱い（判断の記録・2026-09-12実装時決定）**: 「区間の移動距離を
半分として積算する」を採用した。`stepMismatchMultiplier`（倍率そのもの・
「無効化ではない穏やかな倍率」）の意味をそのまま距離に投影しただけであり、新たな
解釈は持ち込んでいない。詳細は
`packages/core/lib/src/economy/opening_point_accrual_service.dart` の
`computeOpeningPointAccrual` クラスdoc参照。

`RewardSettingsRepository`（Issue #135・`reward.step_check_disabled`）がオンの場合、
`RewardPolicy.useStepCheck` が false になり歩数不一致の判定自体が行われなくなる
（歩数の観点では常に倍率1）。この設定の配線は `map_screen.dart` 側で
`RewardPolicy` を構築する箇所を変更する必要があるが、**本 Issue の時点では
`OpeningPointAccrualCoordinator` は既定の `RewardPolicy()`（`useStepCheck: true`）を
使う**（`RewardSettingsRepository.buildRewardPolicy()` との配線は本 Issue のスコープ外・
判断に迷った点としてPR本文に記載）。

## 5. 距離の計算（`RewardPolicy` の既存の距離計算を再利用）

`packages/core/lib/src/antispoof/reward_policy.dart` の `RewardSegment` に
`distanceMeters` フィールドを追加した。値は同ファイルに既に存在する private な
`_haversineMeters`（`speed_filter.dart` と意図的に重複定義されている関数。
両ファイルのクラスdoc参照）をそのまま使う。**3つ目の重複定義は作っていない**——
`_classifySession` が区間ごとに呼ぶ回数を増やしただけで、関数自体は1つのまま。

## 6. なぜ自然回復（1P/日）を実装しないか

`docs/opening_points.md` §2.1・Issue #143 のコメント
（[代表決定](https://github.com/rokusoudo-product/terra-town/issues/143#issuecomment-5645908958)）
のとおり、MVPでは自然回復を実装しない:

- 「1日ごとに1P」の判定には端末の日付（壁時計）が必要。
- 本プロジェクトは「時刻は単調時計・壁時計は使わない」を一貫した方針としており
  （`specs/001-mvp/plan.md` §7、Issue #138 の地形産出も単調時計のみ）、サーバを
  持たない端末内完結の構成では端末時刻の改竄を防げない。
- 歩行優位（`specs/001-mvp/spec.md` §3.2）の設計とも整合しない。

自然回復は別 Issue（`future` ラベル・Issue #146）に切り出す。**後続の実装者は
これを実装漏れと誤認しないこと**（`opening_point_accrual_service.dart` のクラスdoc・
`docs/opening_points.md` §2.1 にも同じ理由を記載済み）。

## 7. 上限（50P）と端数の扱い（判断の記録）

`docs/opening_points.md` §4「上限に達している間は新規付与分は加算されずに
切り捨てられる」は**整数ポイント単位の付与にのみ適用**し、**ミリメートル単位の
端数（remainderMillimeters）は上限に関わらず常に積み上がり続ける**方式を採用した。

理由:
- 端数まで上限到達時に凍結・破棄すると、上限到達中に歩いた分の"あと少しで1P"と
  いう進捗が完全に失われ、消費（T064・未実装）でストックが上限を下回った直後の
  1歩で急に1Pが増えるという不自然な挙動になる。
- 「切り捨てるのは整数ポイントのみ・端数は失わない」という規則は
  `computeOpeningPointAccrual` だけで完結し、消費処理（T064）の実装に依存しない。
- 上限の趣旨（貯めすぎ・非稼働放置による無限蓄積を防ぐ）は、
  `OpeningPointAccrual.grantedPoints` のクランプで引き続き守られる。

詳細・具体例は `opening_point_accrual_service.dart` の `computeOpeningPointAccrual`
クラスdoc「上限到達後の端数の扱い」・`packages/core/test/economy/opening_point_accrual_test.dart`
「上限（cap）での切り捨て」グループ参照。

## 8. ウォーターマークの方式・二重計上防止

`TerrainYieldLedger`（Issue #138）と同じ設計を踏襲する:

- ウォーターマークは「最後に開放ポイントを計上した位置記録の行id」
  （`location_point.id`）。`settings` テーブルの `opening_point.watermark_row_id`
  キーに保存する（`OpeningPointLedger`）。
- ポイントの加算・端数・ウォーターマークの更新は`GameDatabase.transaction`で
  1つのトランザクションとして書く（`opening_point_ledger_test.dart`「トランザクションの
  原子性」で検証）。
- スキーマ変更はしない（既存の `settings` テーブルの key-value 方式のまま。
  開放ポイントは `core` の `Resource` enum に属さない独立した通貨のため、
  `inventory` テーブルは使わない）。

### 8.1 地形産出との違い: 「失敗時に窓を巻き戻さない」ことが追加で必要

地形産出（`TerrainYieldAccrualCoordinator`）は失敗時、`_previous`（直前の1点）への
更新が失敗した呼び出しの後に位置するコードパスにあるため、自然に「失敗した区間の
終点を直前の点にしない」が実現できていた。開放ポイントは窓（複数点）を持つため、
同じ規律を意図的に保つ必要がある: `OpeningPointAccrualCoordinator.accrue` は
`ledger.applyAccrual` を呼ぶ**前**に候補窓（`_buildCandidateWindow`）を同期的な
純粋計算として構築し、実際に `_window` へコミットするのは `applyAccrual` が
成功した後だけである。先に `_window` を書き換えてしまうと、失敗した区間 A→B の
後に C が届いたとき、コミット済みの窓の末尾が B になってしまい、次の区間として
B→C しか見えず A→B 分の距離を失う（`opening_point_accrual_coordinator_test.dart`
「計上の途中で失敗したら…」で検証）。

## 9. デバッグパネル（`kDebugMode` 限定）

`app/lib/map/debug/opening_point_debug_panel.dart`（`OpeningPointDebugPanel`）が
次を表示する:

- 所持ポイント数（上限との対比）と、次の1Pまでの進み具合（端数を%表示）
- ウォーターマーク（最後に計上した行id）
- 直近区間の移動距離・適用された倍率・その理由（`RewardSegmentReason`）

換算レート1.5km=1Pのままでは整数の増加を見るのに1.5km歩く必要があるため、
端数の%表示・直近区間の情報が実機確認の要（`TerrainYieldDebugPanel` と同じ理由）。

## 10. 実機で確認する手順（秘書セッションが行う。1.5km歩かないと1P増えないため、進み具合の表示で確認する）

1. `docs/disclosure-and-fog.md` §4.1 の手順で `flutter build apk --debug` を
   インストールする。
2. 地図画面右上のデバッグパネル表示トグル（バグアイコン）をタップし、デバッグ
   パネル群を表示する（既定は非表示。`map_screen.dart` `_debugPanelsVisible`）。
3. 「位置記録 デバッグパネル」の「起動」でサービスを開始する。
4. 屋外の見晴らしの良い場所で数分〜十数分ほど普段どおりに歩く
   （**屋内では精度ゲート〔30m〕で位置が長時間届かないことがある**。GPS精度が
   出やすい屋外で確認すること）。
5. 「開放ポイント デバッグパネル」を見る。「次の1Pまで」の進み具合（%）が、
   歩くたびに少しずつ増えていくことを確認する（1.5km歩き切らなくても、数十m〜
   百数十m歩くごとにパーセンテージが動くはず）。「直近区間」の距離・倍率が
   `0m`・`倍率-`のままなら、位置が届いていない可能性が高い（「位置記録
   デバッグパネル」の受信件数もあわせて確認する）。
6. 「直近区間」の倍率が常時 `1.00`（理由: 不一致なし）であることを確認する
   （徒歩なら通常はこの値になるはず。頻繁に `0.00` や `0.50` になる場合は
   GPSの精度・速度平滑化のチューニングを見直す余地がある）。
7. 立ち止まったまま数分待ち、「次の1Pまで」の%が変化しないこと（位置が届かない
   限り増えない）を確認する。
8. 端数（%）が100%に達し1Pに繰り上がる瞬間（所持ポイントが1増え、%が0に近い
   値へリセットされる）を確認できればなお良いが、1.5km歩く時間が確保できない
   場合は必須ではない（進み具合の増加が確認できれば計上が機能している証拠になる）。
9. `adb shell am force-stop jp.rokusoudo.terra_town` でアプリを完全終了し、
   再起動する。開放ポイントデバッグパネルの所持ポイント・端数が、force-stop
   直前の値から**二重に増えていない**（同じ区間が2回計上されていない）ことを
   確認する。

**実機では未確認**（本 PR の時点。上記手順の用意までがスコープ）。
