---
type: doc
project: terra-town
doc: 開示（位置→霧の解除）配線と永続化・復元
status: draft
created: 2026-09-11
related:
  - specs/001-mvp/plan.md
  - docs/architecture.md
  - docs/terrain.md
  - docs/location-track-db.md
  - https://github.com/rokusoudo-product/terra-town/issues/137
  - https://github.com/rokusoudo-product/terra-town/issues/102
---

# terra-town — 開示（位置→霧の解除）配線と永続化・復元

> Issue #137（配線・`RegionPack`/`Repository<DisclosedHex>` の実装）・Issue #102（永続化と復元）で
> 実装した composition root の構成・実機確認手順をまとめる。`docs/architecture.md` の環境構成図・
> `docs/location-track-db.md`（位置記録DB）と対をなす、開示・霧まわりの実装ドキュメント。

## 1. 全体の流れ

> **2026-09-11（Issue #138）で配線を更新**: 本番の位置ストリームを購読する
> composition root は `DisclosureCoordinator` から `TerrainYieldPipeline`
> （`app/lib/map/economy/terrain_yield_pipeline.dart`）に置き換わった。地形産出
> （受動・時間ベース）を同じ直列パイプラインに統合するためで、詳細は
> `docs/terrain-yield.md` 参照。`DisclosureCoordinator` 自体はクラス・単体テストと
> しては残っている（手動開示等の別用途に再利用可能）が、composition root では
> 使わない。

```
NativePositionProvider.recordedPositionUpdates（packages/location・行id付き）
  → TerrainYieldPipeline（app/lib/map/economy/terrain_yield_pipeline.dart）
      位置1件ごとに次を直列に（両方awaitして）実行する:
      1. TerrainYieldAccrualCoordinator.accrue（地形産出の計上。docs/terrain-yield.md）
      2. DisclosureService.recordPosition（packages/core・T054・既存）
          - RewardPolicy.allowsDisclosure でモック位置を除外
          - RecordedHexLocator で GeoPosition.hexId をそのまま HexId として使用
          - known（DisclosedHexSet）に無ければ RegionPackRepository.terrainOf で
            地形をスナップショットし DisclosedHex を組み立てる
          - DisclosedHexRepository.save（disclosed_hex テーブルへ insertOrIgnore）
          - known.add
         新規開示イベントごとに TerrainHexCounter を更新し、hexIdToFeatureId で
         featureId へ変換して FogOfWarController.revealHex を呼ぶ
```

配線を組み立てるのは `app/lib/features/map/map_screen.dart` の `_DisclosureAwareMapView`
（composition root）。`MapView.onFogLayerReady`（地図の fog ソース構築完了）を起点に、

1. `restoreDisclosedHexes`（`app/lib/map/disclosure/disclosure_restore.dart`）で
   `disclosed_hex` の全行を読み、`known`（`DisclosedHexSet`）へ反映しつつ
   `FogOfWarController.revealHex` で霧を解除する（**復元**）。
2. 復元が完了した**後**に `TerrainYieldPipeline.start()` で位置ストリームの購読を開始する
   （順序が逆だと、まだ `known` に載っていない既知のヘクスを新規開示と誤認しうる）。
   `start()` 自体が `DisclosedHexRepository.findAll()` から `TerrainHexCounter` を
   組み立て、`TerrainYieldLedger` からウォーターマーク・端数を読み込む処理も行う。

`onFogLayerReady` は、アプリ起動時の初回ソース構築後だけでなく、（MVPでは実際には発生しないが
経路として用意した）将来 `setStyle` が呼ばれ地図のスタイルが再読み込みされた場合にも
再度発火する。同じ関数（`restoreDisclosedHexes`）を両方の入口から呼ぶことで、
「復元経路は1つ」を保っている（`packages/location/lib/src/map/fog_of_war_layer.dart`
クラスdoc「開示状態の正は永続ストレージである」参照）。

## 2. 主要な実装ファイル

| ファイル | 役割 |
|---|---|
| `packages/location/lib/src/pack/region_pack_repository.dart` | `core` の `RegionPack` 抽象の実装（T069）。`hex_terrain`・`pack_meta` を読み込み専用でメモリに展開する |
| `packages/location/lib/src/db/disclosed_hex_repository.dart` | `core` の `Repository<DisclosedHex, HexId>` の Drift 実装（T060）。`insertOrIgnore` でスナップショット不変性を保護する |
| `packages/location/lib/src/map/hex_feature_bridge.dart` | `HexId`（H3 index）→ 地図 Feature の `id` への変換（下位52bitマスク・`docs/terrain.md` §4.4） |
| `app/lib/map/disclosure/disclosure_coordinator.dart` | 位置ストリーム→開示判定→霧の解除の配線（クラス・テストとして残存。composition rootでは不使用。Issue #138以降） |
| `app/lib/map/economy/terrain_yield_pipeline.dart` | 位置ストリーム→地形産出の計上→開示判定→霧の解除を直列に行う composition root 本体（Issue #138。`docs/terrain-yield.md`） |
| `app/lib/map/disclosure/disclosure_restore.dart` | 起動時・`setStyle`後の復元（`known`への反映＋`revealHex`の一括呼び出し・所要時間の計測） |
| `app/lib/features/map/map_screen.dart` | 上記すべてを組み立てる composition root |
| `app/lib/map/debug/disclosure_debug_panel.dart` | デバッグ専用「地図の中心のヘクスを開示」ボタン（`kDebugMode`限定） |
| `app/lib/map/debug/fog_of_war_debug_panel.dart` | デバッグ専用「霧に戻す」「DBから復元」「本番相当で計測」ボタン群 |

## 3. 約14,000ヘクスの復元コストについて（Issue #102・判断の記録）

`maplibre_gl`（`maplibre_gl_platform_interface.dart`）には複数の feature-state を
まとめて設定するバッチ API が無く、`setFeatureState` は1件ずつしか呼べない
（確認: `Future<void> setFeatureState(...)`・`removeFeatureState(...)`・
`Future<Map<String, dynamic>?> getFeatureState(...)` の3つのみ）。そのため
`revealHex` の呼び出し自体（＝ platform channel の往復）が復元対象ヘクス数ぶん
発生することは、既存 API の範囲では避けられない。

`restoreDisclosedHexes` はこれを完全には解消できないが、500件ずつ `Future.wait` で
**並行に**投げることで、Dart 側の `await` を直列にする場合と比べて体感の待ち時間を
短縮する（各呼び出しは異なる `featureId` に対する独立した操作であり競合状態は無い）。
復元したヘクス数・所要時間（ミリ秒）は `developer.log`（`name: terra_town.disclosure_restore`）と
`debugPrint` の両方に出す。

## 4. 実機で確認する手順（Issue #137・#102・代表・秘書セッションが行う）

⚠️ 本 Issue（#137）の時点では実機確認を実施していない。以下は確認のための手順である。

### 4.1 前提（初回のみ）

```bash
cd tools/pack-builder
./bundle_region_pack.sh   # app/assets/pack/{tiles.mbtiles,region_pack.sqlite} を生成
```

`flutter build apk --debug` でデバッグビルドをインストールする（`kDebugMode` の
デバッグパネルが表示される）。**代表の端末（Pixel 7a）の現在地は地域パック
（狭山湖周辺）の範囲外にあるため、実際に歩いても開示は起きない**（`RegionPack.terrainOf`
がパック範囲外で `null` を返すため。これは正しい挙動でバグではない）。そのため
実機確認は下記 4.2 節「地図の中心のヘクスを開示」ボタンを起点にする。

### 4.2 ①「地図の中心のヘクスを開示」で本番と同じ経路を確認する

1. アプリを起動し地図タブを開く。画面下部の「開示 デバッグパネル」の
   「地図の中心のヘクスを開示」をタップする。
2. 「開示しました: hexId=... featureId=... 地形=...」と表示され、地図上でそのヘクスの
   霧が晴れることを確認する。
3. 同じボタンをもう一度押すと「このヘクス（hexId=...）は既に開示済みです」と
   表示されること（冪等性の確認）。

### 4.3 ②アプリ再起動後も霧が残ることを確認する（Issue #102 の核心）

1. 上記 4.2 節で少なくとも1つのヘクスを開示した状態で、アプリを**完全に終了**する
   （`adb shell am force-stop jp.rokusoudo.terra_town`、またはタスクスイッチャーから
   スワイプで終了）。
2. アプリを再起動し、地図タブを開く。
3. 画面上部に「起動時の復元（Issue #102）: N件 / Mms」というカードが表示されること
   （N は事前に開示した件数以上、M は復元にかかった時間）。
4. 4.2 節で開示したヘクスの霧が晴れたままであることを確認する。
5. （簡易な追加確認）アプリを終了させず、設定タブに切り替えてから地図タブに
   戻すだけでも `MapScreen` は再構築され `_DisclosureAwareMapView.initState` から
   同じ復元経路が再度走る（`RootScaffold` がタブ切り替えのたびに `MapScreen` を
   作り直す実装のため）。手順①②を毎回アプリを終了・再起動せずに繰り返し確認したい
   場合はこちらが手軽。

### 4.4 ③`setStyle` 相当の状態喪失からの復元を確認する（実際に `setStyle` を呼ばずに）

MVP では実行時に `setStyle` を呼ぶ機能が無いため（`plan.md` §8・2026-09-09 代表決定）、
`FogOfWarController.resetAllForDebug`（内部で `removeFeatureState` を呼ぶ）で
同種の状態喪失を模して復元経路を確認する。

1. 「フォグ デバッグパネル」の「霧に戻す（setStyle相当の状態喪失を再現）」をタップする。
   画面上の全ヘクスが霧に覆われる（`disclosed_hex` テーブル自体は変更されない）。
2. 「DBから復元」をタップする。「復元しました: N件 / Mms」と表示され、
   これまで開示していたヘクスの霧が再び晴れることを確認する。

### 4.5 ログの見方

```bash
adb logcat | grep terra_town.disclosure_restore
```

`[terra_town.disclosure_restore] 開示済みヘクスの復元が完了しました: ヘクス数=N 所要時間=Mms（chunkSize=500）`
という行が、起動時・「DBから復元」ボタン押下のたびに出力される。

### 4.6 上限（約14,000ヘクス・plan.md §3.5）について

代表の端末が対象パック（狭山湖周辺・13,106ヘクス）の範囲内を実際に歩いて全ヘクスを
開示しない限り、復元件数がこの上限に達することは実機確認の範囲では起きない。
上限を超えるケースの検証は本 Issue のスコープ外（`plan.md` §3.5「上限超過時の方針」参照）。

**本 Issue（#137・#102）のスコープはここまでの手順の用意であり、実施は代表・秘書セッションが行う。**
