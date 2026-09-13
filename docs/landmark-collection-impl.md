---
type: impl-note
project: terra-town
doc: 名所の収集判定と図鑑記録（collectionスキーマ v3）の実装と実機確認手順
created: 2026-09-14
related:
  - docs/landmark_objects.md
  - docs/opening-points-spend-impl.md
  - specs/001-mvp/tasks.md（T067・T070）
  - https://github.com/rokusoudo-product/terra-town/issues/159
  - https://github.com/rokusoudo-product/terra-town/issues/158
  - https://github.com/rokusoudo-product/terra-town/issues/151
  - https://github.com/rokusoudo-product/terra-town/issues/162
---

# terra-town — 名所の収集判定と図鑑記録の設計と実機確認手順

`docs/landmark_objects.md` §3.2・§5 が定める「名所を含むヘクスが開示されたら
自動収集する（現地開示／ポイント開放）」機能（Issue #159・T067・T070）の
実装をまとめる。前提（POI→ヘクス対応 `hex_poi`）は Issue #158。

## 1. 何を実装したか

- `packages/core/lib/src/landmark/landmark_service.dart`
  - `CollectMethod`（`walk`/`point`）・`LandmarkCollectionRecord`（`docs/landmark_objects.md`
    §5 の必須項目に対応する値オブジェクト）。
  - `evaluateLandmarkCollection`（純粋関数）: 新規開示された `DisclosedHex` と
    `RegionPack.pointsOfInterestIn` から、未収集の名所の収集記録を返す。
    `alreadyCollected`（呼び出し側が事前に読み出した既収集ID集合）で
    冪等性を保証する。
- `packages/location/lib/src/db/game_database.dart`
  - `collection` テーブルを **schemaVersion 3** に更新し、
    `kind`・`name`・`is_bonus`・`collect_method`・`bonus_granted` を追加。
  - `discovered_at` 列は据え置き（§3参照）。
- `packages/location/lib/src/db/collection_repository.dart`: `collection`
  テーブルの読み書き（`findCollectedIds`・`save`〔`insertOrIgnore`〕・
  `findAll`・`count`）。
- `packages/location/lib/src/db/landmark_collection_support.dart`:
  `collectLandmarksForDisclosedHex`（POI検索→収集判定→保存の共通処理。
  徒歩・ポイント開放の両経路から呼ばれる）。
- `packages/location/lib/src/db/landmark_aware_disclosed_hex_repository.dart`:
  `LandmarkAwareDisclosedHexRepository`（徒歩経路。`disclosed_hex` の保存と
  名所の収集記録を同一トランザクションで行う `Repository<DisclosedHex, HexId>`
  実装）。
- `packages/location/lib/src/db/hex_opening_spend_service.dart`:
  `HexOpeningSpendService` に `regionPack`・`collectionRepository` を追加し、
  `spend()` の既存トランザクション内で名所の収集記録も行うよう拡張。
  `HexOpeningSpendResult.collectedLandmarks` で結果を公開。
- `app/lib/map/economy/terrain_yield_pipeline.dart`:
  `HexOpeningAttemptResult.collectedLandmarks` を追加し、`spend` の結果を
  `map_screen.dart` まで伝播。
- `app/lib/features/map/widgets/hex_opening_sheet.dart`: 「閉じる」を押した
  時点の `HexOpeningAttemptResult` を `Navigator.pop` の戻り値として返す
  ように変更（§4参照）。
- `app/lib/features/map/map_screen.dart`: composition root の配線。
  `DisclosureService.repository` に `LandmarkAwareDisclosedHexRepository` を
  注入し、`HexOpeningSpendService` に `regionPack`・`collectionRepository` を
  渡す。新規収集時に `SnackBar` で名所名を表示する。

## 2. 同一トランザクションの実現方式（受け入れ基準）

`docs/landmark_objects.md` §3.2 の2経路それぞれで、開示と収集記録を
1つのDBトランザクションにまとめた。

### a. ポイント開放経路（`HexOpeningSpendService.spend`）

もともと `spend()` 自体が `disclosed_hex` の保存とポイント減算を1つの
`GameDatabase.transaction()` で行っていた（Issue #151）ため、**同じ
トランザクションの中に名所の収集記録を追加する**だけで済んだ
（`disclosed_hex` 保存の直後・`outcome = opened` を確定した直後に
`collectLandmarksForDisclosedHex` を呼ぶ）。`regionPack`・
`collectionRepository` は省略可能（null 許容）にし、渡さない既存の
呼び出し元・テストは従来どおり動作する（後方互換）。

### b. 徒歩経路（`LandmarkAwareDisclosedHexRepository`）

徒歩経路は `packages/core` の `DisclosureService.recordPosition` が
`repository.save(disclosed)`（`Repository<DisclosedHex, HexId>` 抽象越し）を
呼ぶだけであり、`spend()` のように呼び出し元が既にトランザクションを
持っているわけではない。**`core` の `DisclosureService` 自体は変更せず**
（GPS_ARCHITECTURE準拠・`core` は SQLite に依存しないという制約を保つ）、
`save` の実装を差し替えるデコレータ（`LandmarkAwareDisclosedHexRepository`）
を `location` 側に新設し、その `save()` の中で

1. `GameDatabase.transaction()` を開始
2. 既に開示済みでないか再確認（`DisclosedHexRepository.findById`）—
   既存開示済みなら収集判定を一切行わず何もしない（§3参照）
3. `DisclosedHexRepository.save`（`insertOrIgnore`）
4. `collectLandmarksForDisclosedHex`（`collectMethod: walk`）

を行う。`composition root`（`map_screen.dart`）は `DisclosureService.repository`
にこのデコレータを渡すだけで、既存の `DisclosureService` のテスト・実装は
一切変更していない。

いずれの経路も、収集記録の書き込みに失敗すればロールバックされ
「ヘクスは開示済みなのに名所が未収集」という状態は残らないことを
`packages/location/test/db/landmark_aware_disclosed_hex_repository_test.dart`
（トランザクションの原子性）・`hex_opening_spend_service_test.dart`
（名所の収集記録グループ）で検証している。

## 3. 既存開示済みヘクスへの遡及収集をしない（判断の記録）

`docs/landmark_objects.md`・Issue #159 本文「対象外」に明記のとおり、本Issue
より前に開示済みだったヘクスの名所は遡及収集しない（リリース前でユーザー
データが無いため、この判断による実害は無い）。

これは実装上、次の2点で**構造的に**保証されている（advisor指摘を反映）:

- 徒歩経路: `LandmarkAwareDisclosedHexRepository.save` がトランザクション内で
  `findById` を実行し、既に開示済みであれば収集判定自体を行わずに終える
  （`DisclosedHexRepository.save` の `insertOrIgnore` の戻り値には頼らない）。
- ポイント開放経路: `HexOpeningSpendService.spend` はもともと「既に開示済み
  なら `outcome = alreadyDisclosed` で早期リターンする」実装だった
  （Issue #151）。名所の収集判定はこの早期リターンより後（`outcome = opened`
  が確定した後）にのみ実行されるため、既存開示済みヘクスに対しては到達しない。
- 起動時の復元（`restoreDisclosedHexes`）は `findAll()` を読むだけで `save()`
  を一切呼ばないため、復元経路からも収集判定は発生しない。

## 4. `collection` テーブルの列設計（schemaVersion 3・判断の記録）

- **`kind`・`name`・`collect_method`・`bonus_granted` は nullable にした**
  （`is_bonus` のみ `NOT NULL DEFAULT false`）。SQLite の
  `ALTER TABLE ... ADD COLUMN` は `NOT NULL` 列に意味のあるデフォルト値が
  無いと DDL 自体を拒否するが、v2 時点の既存行（もしあれば）に対して
  `kind`/`name`/`collect_method` の架空の既定値（例: 全件 `walk` 扱いにする）を
  捏造すると「本当は歩いていないのに歩いたことになる」という不正確な記録を
  作ってしまう。`disclosed_hex.terrain_type` の v1→v2 移行で「意味のある
  デフォルト値を捏造するより正直にテーブルを作り直す方を選んだ」判断
  （`game_database.dart` 参照）と同じ精神で、今回は**テーブル再作成ではなく
  ADD COLUMN で列を追加しつつ、既存行には正直に null を残す**方式を採った
  （`collection` は `poi_id`・`discovered_at` という実データを保持したまま
  移行する必要があるため、テーブル再作成は選べない）。
- **`discovered_at` 列はリネームしなかった**（`collected_at` の方が意味的には
  正確）。SQLite の列リネーム（`ALTER TABLE ... RENAME COLUMN`）自体は可能だが、
  本Issueの他の変更（列追加5本）と比べてリスク・レビューコストが見合わないと
  判断した。ドメイン層（`LandmarkCollectionRecord.collectedAt`・
  `CollectionRepository`）ではこの列を `collectedAt` として読み書きし、
  スキーマ上の列名とドメイン上の意味の対応はコード上のコメントで明示している。
- v2→v3 の移行テスト（`packages/location/test/db/game_database_test.dart`
  「collection マイグレーション」グループ）で、v2の既存行
  （`poi_id`・`discovered_at`のみ）が失われずに残ること・新列が
  null/false（架空の値を捏造しない）で読めることを検証済み。

## 5. `is_bonus`・`bonus_granted`（2026-09-13代表決定）

本Issueで生成される収集記録は全件 `is_bonus = false`・`bonus_granted = null`
固定（`evaluateLandmarkCollection` が常にこの値を設定する）。ボーナス
オブジェクトの判定・効果（T072〜T074）は `future` Issue #162 のスコープ。
`collect_method`（`walk`/`point`）は本Issueから記録を開始し、#162側で
差分ボーナスを計算する際の入力として使える状態にした。

## 6. UI（最小限のSnackBar）

新規収集があれば `map_screen.dart` が
`名所「○○」を図鑑に登録しました（現地で発見 / ポイントで開放）`
という `SnackBar` を表示する（本格的な通知UI・図鑑画面はIssue #159の対象外）。

**ポイント開放経路のSnackBar表示タイミングに注意**: `HexOpeningSheet`
（モーダルボトムシート）が開いている間にSnackBarを表示すると、Scaffold上に
表示されるSnackBarがモーダルの背面に隠れて利用者に見えない。そのため
`HexOpeningSheet` は「閉じる」ボタンで `HexOpeningAttemptResult`（収集結果を
含む）を `Navigator.pop` の戻り値として返すよう変更し、`map_screen.dart` の
`_handleFogHexTapped` は `showModalBottomSheet` の `Future` が完了した
（＝シートが完全に閉じた）後にSnackBarを表示する。

SnackBarは `SnackBarBehavior.floating` ＋ `AppSpacing` トークンによる
下マージン（`AppSpacing.xxxl + AppSpacing.sm`）で、画面下部の既存の製品UI
（記録開始ボタン・追従ボタン）より上に浮かせている（色・サイズの直書きは
していない。`tools/check_design_tokens.sh` で確認済み）。デバッグパネルの
既定非表示という現行仕様には影響しない。

## 7. 秘書が実機で確認する手順（実機では未確認）

前提: 2026-09-13時点の秘書の端末は、開示済みヘクスが2件（狭山湖パック内・
森1・空き地1）、開放ポイントは0P（`docs/opening-points-spend-impl.md` §8参照）。
この2件の周辺に名所（例: `amenity=place_of_worship` 等）があるかは
`app/assets/pack/region_pack.sqlite` の `hex_poi` テーブルで事前に確認できる
（本PR作成時点でパックを再ビルドしていないため具体的な名称・ヘクスIDはここには
記載しない。秘書の端末で以下のSQLを実行して対象ヘクスを選ぶこと）:

```sql
-- app/assets/pack/region_pack.sqlite に対して実行
SELECT hex_poi.hex_id, poi.name, poi.kind
FROM hex_poi
JOIN poi ON poi.id = hex_poi.poi_id
LIMIT 20;
```

手順:

1. アプリを起動し、`kDebugMode` のデバッグパネル一括表示トグルを押して開き、
   「デバッグ付与: +10P」を押す（所持ポイントが10になることを確認）。
2. 上記SQLで見つけた名所付きのヘクスのうち、既存の開示済みヘクスに
   **隣接する**ものをタップし、開放ポイントで開放する
   （`docs/opening-points-spend-impl.md` §8 の手順と同じ）。
   - シートで「開放しました」の表示後、「閉じる」を押してシートを閉じる。
   - シートが閉じた直後に、画面下部より上（記録開始ボタンと重ならない位置）に
     「名所『○○』を図鑑に登録しました（ポイントで開放）」というSnackBarが
     出ることを確認する。
3. アプリの `game_state.sqlite`（アプリのドキュメントディレクトリ配下）を
   DB閲覧ツール（`adb shell run-as jp.rokusoudo.terra_town cat ...` 等で
   端末から取り出す、または `adb exec-out` でホストに転送）で直接開き、
   次のSQLで記録を確認する:
   ```sql
   SELECT poi_id, kind, name, is_bonus, collect_method, bonus_granted, discovered_at
   FROM collection;
   ```
   `collect_method` が `point`、`is_bonus` が `0`、`bonus_granted` が `NULL`、
   `kind`/`name` が手順1のSQLで見た値と一致していることを確認する。
4. アプリを再起動し、`collection` テーブルの内容が引き続き残っていること
   （手順3のSELECTが同じ結果を返すこと）を確認する。
5. （余裕があれば）名所付きの別の未開示ヘクスへ実際に歩いて到達し、
   「名所『○○』を図鑑に登録しました（現地で発見）」のSnackBarが表示され、
   `collection.collect_method` が `walk` で記録されることを確認する。
6. （余裕があれば）手順2または5で一度収集した名所と同じヘクスに対し、
   デバッグパネルの「DBから復元」等でもう一度同じヘクスの開示処理を
   走らせても、`collection` の行が増えない（`poi_id` 主キーで冪等）ことを
   確認する。

**確認できないこと（実機で追加検証が必要な既知の未検証事項）**:

- SnackBarの表示タイミング（シートが閉じた直後）が実機の描画タイミング上
  自然に見えるか（エミュレータ・単体テストでは検証済みだが、実機の
  アニメーション速度による見え方の違いは未確認）。
