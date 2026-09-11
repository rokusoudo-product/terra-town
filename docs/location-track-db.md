---
type: spec
project: terra-town
doc: 位置記録DB（Kotlin所有）のスキーマ・受け渡し方法
status: approved
created: 2026-09-11
updated: 2026-09-11
related:
  - specs/001-mvp/plan.md
  - docs/architecture.md
  - https://github.com/rokusoudo-product/terra-town/issues/123
  - https://github.com/rokusoudo-product/terra-town/issues/124
  - https://github.com/rokusoudo-product/terra-town/issues/10
supersedes: null
---

# 位置記録DB（`location_track.sqlite`）— スキーマと受け渡し方法

> Issue #123（T046〜T048）で実装。**このドキュメントは Issue #124（Dart 側の読み取り実装・
> `NativePositionProvider`）が読む前提の契約書**であり、実装（
> `app/android/app/src/main/kotlin/jp/rokusoudo/terra_town/location/LocationTrackDatabase.kt`）
> と同じ内容を保つこと。スキーマを変更した場合は同じPRで本ドキュメントも更新する。

## 1. なぜゲーム状態DB（Drift）と別ファイルにするのか

ゲーム状態DB（`disclosed_hex` 等）は **Drift（Dart 側）がスキーマとマイグレーションを管理**
している（`packages/location/lib/src/db/game_database.dart`・`schemaVersion` 2）。
Kotlin が Drift 管理下のテーブルに直接 `INSERT` すると、スキーマの正が2箇所（Drift の
Dart 定義と Kotlin の DDL）に分裂し、Drift 側のマイグレーションと Kotlin の書き込みが
ずれたときに**例外を出さずに静かに壊れる**（Issue #123 本文・2026-09-11 代表決定②）。

そのため、位置記録は完全に別ファイル `location_track.sqlite` に置く。**このファイルの
スキーマの所有者は Kotlin 側のみ**。Dart 側（Issue #124）はこのファイルを
読み取り専用として開くだけで、書き込みは一切行わない。

## 2. ファイルの場所（Kotlin ⇔ Dart の受け渡し方法）

**保存先ディレクトリ**: `context.getDir("flutter", Context.MODE_PRIVATE)`
（実体は `/data/user/<userId>/jp.rokusoudo.terra_town/app_flutter/`）。

これは Flutter エンジン自身の `io.flutter.util.PathUtils.getDataDirectory(Context)` の
実装と**全く同じディレクトリ**である（`getDir("flutter", MODE_PRIVATE)` を呼んでおり、
`context.getDir` はディレクトリが無ければ作成する。バイトコード〔`javap`〕で実装を確認済み・
2026-09-11）。`path_provider` の Dart API では `getApplicationDocumentsDirectory()` が
これに対応する。ゲーム状態DB（`game_state.sqlite`・`game_database.dart`）も同じ
`getApplicationDocumentsDirectory()` を使っており、**このファイルと同じディレクトリに
既に置かれている**。

つまり、**Issue #124 は新しいプラットフォームチャンネルを介さず**、既存の
`path_provider` の呼び出し（`getApplicationDocumentsDirectory()`）だけで
このファイルを見つけられる:

```dart
final directory = await getApplicationDocumentsDirectory();
final file = File(p.join(directory.path, 'location_track.sqlite'));
```

**ファイル名**: `location_track.sqlite`（`game_state.sqlite` と同じディレクトリ内の別ファイル。
衝突しない）。

Kotlin 側の実装は `LocationTrackSchema.resolveDatabaseFile(context)`
（`LocationTrackDatabase.kt`）。`SQLiteOpenHelper` へは絶対パスを `name` として渡している
（`Context#getDatabasePath` は名前が `/` から始まる場合、そのディレクトリをそのまま使う、
という Android フレームワークの既定動作を利用）。

## 3. Dart 側で開く方法（Issue #124 向け・推奨）

`packages/location/lib/src/db/region_pack_connection.dart`（地域パックDB・Issue #83）と
**全く同じパターン**を踏襲することを推奨する:

```dart
final rawDatabase = sqlite3.sqlite3.open(
  locationTrackFilePath,
  mode: sqlite3.OpenMode.readOnly,
);
```

`OpenMode.readOnly` により、書き込み系SQL文は Dart 側のコーディング規約ではなく
**SQLite 自身が `SQLITE_READONLY` でエラーにする**（構造的に書き込みを防ぐ）。

### WAL（Write-Ahead Logging）に関する注意（重要）

Kotlin 側は `enableWriteAheadLogging()` で WAL を有効にしている（書き込み側と読み取り側が
同時にアクセスできるようにするため）。WAL 使用時は本体ファイルに加えて
`location_track.sqlite-wal` / `location_track.sqlite-shm` のサイドカーファイルが生成され、
**直近の書き込みは本体ファイルではなくこれらのサイドカーにしか無いことがある**。

- Dart 側で `sqlite3.open(path, mode: OpenMode.readOnly)` する場合、同じディレクトリに
  `-wal`/`-shm` があれば SQLite が自動的に読みに行く（同一プロセス内・同一UIDなので
  読み取り専用でも正しく動作する）。**`-wal`/`-shm` を消したり分離したりしないこと。**
  接続を開く際にコピーする場合は3ファイルまとめてコピーする。読み取り専用で開く場合も
  `-shm`（共有メモリインデックス）ファイルへの書き込み権限が必要になる点に注意
  （同一アプリ内・同一ディレクトリなので通常は問題にならない）。
- Dart の `sqlite3` パッケージ（`package:sqlite3`）は Android プラットフォームの SQLite とは
  **別のSQLiteビルド**（バンドルされたネイティブライブラリ）を使うが、WAL フォーマットは
  SQLite間で相互互換であるため、Kotlin（プラットフォームのSQLite）が書いた WAL を
  Dart 側の別ビルドから問題なく読める。上記の「`-wal`/`-shm` を分離しない」というルールは
  この互換性を活かすための運用ルールである。
- サービスの `onDestroy()` は `LocationTrackDatabaseHelper#close()` を呼ぶ。**WALデータベースは
  最後の接続が閉じられた時点で SQLite 自身が自動的にチェックポイントし `-wal`/`-shm` を
  解消する**ため、明示的な `PRAGMA wal_checkpoint` を実行しなくても同じ効果が得られる
  （あえて実行しない理由: `wal_checkpoint` は結果を1行返すPRAGMAであり、Android の
  `SQLiteDatabase#execSQL` は行を返すSQL文を受け付けずOSバージョンによっては例外を投げる。
  代表がサービスを止めてデータを取り出そうとした瞬間にクラッシュする事故を避けるため、
  単純な `close()` に留めている）。**サービス停止後**であれば本体ファイル単体でも
  直近データを含む（代表が `adb pull` で1ファイルだけ取り出す場合は、先にサービスを
  止めることを推奨。§8.3参照）。

## 4. スキーマ（DDL・実装からそのまま転記）

出典: `app/android/app/src/main/kotlin/jp/rokusoudo/terra_town/location/LocationTrackDatabase.kt`
の `LocationTrackSchema`。

```sql
CREATE TABLE IF NOT EXISTS location_track_meta (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL
);
-- 初期化時に1行だけ挿入: ('schema_version', '1')

CREATE TABLE IF NOT EXISTS location_point (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id TEXT NOT NULL,
    elapsed_realtime_nanos INTEGER NOT NULL,
    wall_clock_unix_millis INTEGER NOT NULL,
    latitude REAL NOT NULL,
    longitude REAL NOT NULL,
    accuracy_meters REAL,
    possible_mock_location INTEGER NOT NULL DEFAULT 0,
    inserted_at_unix_millis INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_location_point_session
ON location_point (session_id, id);
```

現在の `schema_version` = **1**。将来スキーマを変更する場合は
`LocationTrackDatabaseHelper.onUpgrade`（現状は未実装で例外を投げる＝スキーマ変更を
実装せず放置すると即座にクラッシュして気づける設計）を実装し、
`location_track_meta.schema_version` の値も一緒に更新すること。

### 列の意味

| 列 | 型 | 意味 |
|---|---|---|
| `id` | INTEGER（自動採番） | 挿入順に単調増加。値は再利用されない。セッションをまたいだ大まかな前後関係の判定に使える（§5.2参照）。 |
| `session_id` | TEXT（UUID） | `LocationTrackingService.onCreate()` のたびに新規発行（§5.1参照）。 |
| `elapsed_realtime_nanos` | INTEGER | `Location.getElapsedRealtimeNanos()`。単調時計・端末時刻の改竄に耐性（T048）。**同一 `session_id` 内でのみ比較可能**（§5.1）。 |
| `wall_clock_unix_millis` | INTEGER | `Location.getTime()`。**改竄可能な参考情報**。速度判定・順序保証には使わないこと。 |
| `latitude` / `longitude` | REAL | 緯度・経度（度）。 |
| `accuracy_meters` | REAL（NULL可） | `Location.getAccuracy()`。値が無い fix は NULL。 |
| `possible_mock_location` | INTEGER（0/1） | Android の `Location.isMock()`（API31+）／`isFromMockProvider()`（それ未満）の生の値。**Android の用語（`isFromMockProvider` 等）はこの列の実装に閉じており、列名・呼び出し側は中立な名前にしてある。** モック検出そのもの（判定ロジック）は本 Issue では実装していない。Issue #126 がこの値を読み、`packages/core` の `GeoPosition`（Issue #124 で追加予定の「偽装の疑い」フラグ）へ変換する想定。 |
| `inserted_at_unix_millis` | INTEGER | 行を INSERT した時刻（`System.currentTimeMillis()`）。デバッグ用。 |

## 5. 時刻の扱い（T048・重要な決定）

### 5.1 `elapsedRealtime` は端末再起動でリセットされる → セッションIDで区切る

**方針**: `elapsed_realtime_nanos` は**同一 `session_id` の行同士でのみ**比較・減算してよい。
`session_id` は `LocationTrackingService.onCreate()`（サービスプロセスが新しく起動する
たび。端末再起動をまたぐかどうかに関わらず、サービスの再起動そのものが区切りになる）ごとに
新しい UUID を発行する。

- **同一 `session_id` 内**: `elapsed_realtime_nanos` の差分から経過時間・速度を計算してよい
  （速度判定・Issue #125・PR #127「移動平均後の速度による判定」はこれを前提にしている）。
- **`session_id` が異なる行同士**: 経過時間・速度は**計算しない**。foreground service の
  停止/再起動自体がGPSストリームの連続性を断つ（再開後は新しい fix から測位が再開する）ため、
  ここで速度計算を諦めても失うものは無い。
- **セッションをまたいだ大まかな前後関係**が必要な場合（例: 表示用の時系列一覧）は、
  `id`（`INTEGER PRIMARY KEY AUTOINCREMENT`。挿入順に単調増加し、値が再利用されない）を使う。
  これは経過時間・速度の計算とは別物であることに注意。

この方針を採った理由: 「壁時計とelapsedRealtimeの差からブート時刻を推定し、ズレが
閾値を超えたら再起動とみなす」ヒューリスティックも検討したが、その推定自体が
壁時計（NTP補正・ユーザーによる手動変更）に依存してしまい、単調時計を使う目的
（端末時刻の改竄・変更に影響されないこと）と矛盾する。**セッションIDによる明示的な
区切りはヒューリスティックを必要とせず、単調時計の保証をそのまま活かせる。**

### 5.2 速度判定（Issue #125・PR #127）との関係

`packages/core/lib/src/antispoof/speed_filter.dart`（`SpeedFilter`）は
`GeoPosition` のリストに単調時刻が入っている前提で動く。Issue #124 が
`location_track.sqlite` を読んで `GeoPosition` の列へ変換する際は、
**`session_id` が変わる境界をまたいで `SpeedFilter` に連続した区間として渡さないこと**
（区間を分割する・またはその境界だけ速度判定の対象外にする）。

## 6. 距離しきい値・サンプリング方針（暫定値・T015で確定）

`LocationSamplingPolicy`（`LocationSamplingPolicy.kt`）参照。

- **距離しきい値**: 既定 **15m**（暫定）。Issue #10 代表回答「10〜20m」の中央付近を
  採用。10m寄りだと市街地のGPS/Wi-Fi測位ノイズで誤発火しやすく、20m寄りだとヘクス解像度
  （約50m）に対して記録が粗くなりすぎるための折衷。**T015（1時間の実歩行計測）で確定する
  までの暫定値**。
- **時間上限**: 既定 **5分**（暫定）。距離条件を満たさなくても強制的に1回だけ現在地を
  取得して記録する。
- **優先度（`priority`）: 既定 `PRIORITY_HIGH_ACCURACY`（2026-09-11・実機検証を受けた代表決定・
  案A。旧: `PRIORITY_BALANCED_POWER_ACCURACY`）**。
  当初は NFR-1「常時高精度GPSを使わない」に基づき `PRIORITY_BALANCED_POWER_ACCURACY` を
  既定にしていたが、実機（Pixel 7a）で位置が1件も記録されない不具合が発生し、原因は
  この優先度と精度ゲート（下記）が**構造的に両立しない**組み合わせだったことが判明した
  （詳細は本ドキュメント末尾の「2026-09-11 実機検証と修正」節・PR #128 コメント参照）。
  代表決定により `PRIORITY_HIGH_ACCURACY` に変更する。このサービスはアプリから明示的に
  起動されたときだけ動作し常駐しないため（`START_NOT_STICKY`）、NFR-1 の**意図**
  （使っていないときに電池を消費し続けない）自体は保たれる、というのが変更の理由。
  **`plan.md` §7 の文言（「常時高精度GPSを使わない」）は本 PR では変更しない**。改定案は
  PR 本文に記載し、代表承認後に別 PR で反映する。
- **精度ゲート**: `accuracy_meters` が距離しきい値の2倍（既定30m）を超える fix は破棄する。
  この値自体は優先度変更後も据え置いている。`PRIORITY_HIGH_ACCURACY` であれば屋外で通常
  5〜15m程度の精度になることが期待され30mゲートと両立するはずだが、**これは一般的傾向からの
  推測であり実測していない**。実際の分布は T015（1時間の実歩行計測）で確認し、必要なら
  しきい値・優先度の組み合わせを再調整する。破棄した fix は精度の値と累計破棄件数を
  `Log.d`（タグ `LocationTrackingService`、「位置破棄（精度不足）」）に必ず出すようにした
  （2026-09-11 修正・以前は無言で破棄しており記録0件の原因調査を難しくしていた）。
- **変更方法**: `LocationSamplingPolicy.currentPolicy` を差し替える。設定UI（T059以降）が
  できた場合はそこから値を読み込んで上書きする実装を追加すればよい。

## 7. 画面OFF時の挙動（plan.md §7 が明記を求めている事項）

foreground service は「フォアグラウンド位置」権限（`ACCESS_FINE_LOCATION` /
`ACCESS_COARSE_LOCATION`。**`ACCESS_BACKGROUND_LOCATION` は要求しない**）だけで、
**画面消灯・アプリがバックグラウンドに回っても動作し続ける**（Android の
while-in-use 制限は「アプリの画面が前面にあること」ではなく「foreground service が
動作していること」を条件にしているため）。したがって「フォアグラウンド位置」は
「アプリの画面を見ていること」を意味しない。サービスを止めるのは
明示的な停止操作（T059）のみで、本 Issue の時点では代表がデバッグフック
（`MainActivity.handleDebugLocationServiceIntent`）で止める。

**`onStartCommand` は `START_STICKY` ではなく `START_NOT_STICKY` を返す**（プロセスが
kill された場合にシステムに自動再起動させない）。自動再起動しても、その時点でアプリに
前面の Activity が無ければ（Android 11+ の while-in-use 制限により）
`ACCESS_BACKGROUND_LOCATION` なしでは位置更新自体が届かず、「通知は表示されるが記録が
一切増えない」状態になるだけで意味が無いため。再開はユーザー操作（T059）に委ねる。

## 8. 代表が実機で確認する手順

### 8.1 前提（初回のみ）

```bash
adb shell pm grant jp.rokusoudo.terra_town android.permission.ACCESS_FINE_LOCATION
adb shell pm grant jp.rokusoudo.terra_town android.permission.POST_NOTIFICATIONS
```

`POST_NOTIFICATIONS` を許可しなくてもサービスは起動する（常駐通知が表示されないだけ）。
通知が出ない場合はこの許可を疑うこと。

### 8.2 サービスの起動・停止（T059未実装のためデバッグフック経由）

```bash
# 起動
adb shell am start -n jp.rokusoudo.terra_town/.MainActivity \
  --ez terra_town.debug.startLocationService true

# 起動確認（"location" の foregroundServiceType が付いたサービスが見えるはず）
adb shell dumpsys activity services jp.rokusoudo.terra_town

# 停止（close()によりWALが自動的にチェックポイントされる。§3参照）
adb shell am start -n jp.rokusoudo.terra_town/.MainActivity \
  --ez terra_town.debug.stopLocationService true
```

**`ACCESS_COARSE_LOCATION` のみを許可した場合の注意**: 大まかな位置（Wi-Fi/セル測位相当）
は精度が数十〜100m規模になりやすく、`LocationSamplingPolicy.maxAcceptedAccuracyMeters`
（既定30m）を超えて全fixが破棄され、記録が0件のままになることがある。これはバグではなく
精度ゲート（§6）の意図した動作。記録が増えない場合はまずこれを疑うこと（破棄した fix は
`adb logcat` に精度と累計破棄件数付きで出るようになっている。§6参照）。

**権限を許可せずに起動した場合（重要・プロセスが生存したまま拒否されることを必ず確認する）**:

2026-09-11 の実機検証で、権限が無い状態でサービスを起動すると
`ForegroundServiceDidNotStartInTimeException` により**アプリのプロセスごと強制終了される**
不具合が見つかった（`LocationTrackingService.Companion.start()` が権限を確認せずに
`startForegroundService()` を呼んでしまい、サービス側は `startForeground()` を呼ばずに
`stopSelf()` していたため）。修正後は `Companion.start()` 自身が権限を確認し、
無ければ `startForegroundService()` を呼ばない（戻り値 `false`）。サービス内
（`onStartCommand`）の確認は二重防御として残っているが、その経路でも
`startForeground()` を先に呼んでから停止するためクラッシュしない。

```bash
adb shell pm revoke jp.rokusoudo.terra_town android.permission.ACCESS_FINE_LOCATION
adb shell pm revoke jp.rokusoudo.terra_town android.permission.ACCESS_COARSE_LOCATION
adb shell am start -n jp.rokusoudo.terra_town/.MainActivity \
  --ez terra_town.debug.startLocationService true

# 修正の確認: プロセスが生存していること（PID が返ること）
adb shell pidof jp.rokusoudo.terra_town

# logcat に警告が出て即座に停止すること（サービスは起動しない）
adb logcat -d | grep LocationTrackingService
adb shell dumpsys activity services jp.rokusoudo.terra_town
```

- `adb shell pidof jp.rokusoudo.terra_town` が**値を返す**（＝プロセスが落ちていない）こと。
  何も返らない場合はクラッシュしており、修正前の状態に戻っている疑いがある。
- `adb logcat` に
  `ACCESS_FINE_LOCATION/ACCESS_COARSE_LOCATION が無いため startForegroundService() を呼ばずに起動を中止します`
  （`Companion.start()` 側・主経路）または
  `ACCESS_FINE_LOCATION/ACCESS_COARSE_LOCATION が無いため起動を中止します（二重防御経路）`
  （`onStartCommand` 側・二重防御経路。通常はここまで来ない）という警告が出ること。
- `dumpsys activity services` にサービスが見えない（起動していない）こと。

### 8.3 記録データの取り出し

サービスを停止した後（§8.2）に取り出すと `-wal`/`-shm` を気にせず1ファイルで完結する:

```bash
adb shell run-as jp.rokusoudo.terra_town \
  cat app_flutter/location_track.sqlite > location_track.sqlite
sqlite3 location_track.sqlite "SELECT COUNT(*), MIN(id), MAX(id) FROM location_point;"
sqlite3 location_track.sqlite "SELECT * FROM location_point ORDER BY id DESC LIMIT 20;"
```

サービスを止めずに取り出したい場合は `-wal`/`-shm` も一緒に `run-as cat` すること
（3ファイルとも同じ `app_flutter/` 配下にある）。

### 8.4 T015（1時間の実歩行・電池と測位品質の計測）手順案

1. 上記手順でサービスを起動する（屋外・都市部マルチパスを含むルートを歩く）。
2. 端末の「設定 → バッテリー → アプリごとの使用量」で terra_town の1時間あたりの
   バッテリー消費を記録する（`PRIORITY_BALANCED_POWER_ACCURACY` 版）。
3. 歩行後、§8.3 の手順で `location_point` を取り出し、以下を確認する:
   - 記録された点数・`accuracy_meters` の分布（粗い fix が多すぎないか）。
   - 隣接点間の距離（Haversine）が概ね15m前後に収まっているか（しきい値通りに
     間引かれているか）。極端に短い/長い区間がないか。
   - `possible_mock_location` が意図せず1になっていないか（実機なら基本0のはず）。
4. `LocationSamplingPolicy.DEFAULT_PRIORITY` を `PRIORITY_HIGH_ACCURACY` に変更した
   ビルドでも同じ手順を行い、バッテリー消費・精度を比較する。
5. 結果を `specs/001-mvp/research.md` に記録し、`distanceThresholdMeters` /
   `timeCapMillis` / `priority` の確定値を決める（plan.md §16 未確定事項②）。

**本 Issue（#123）のスコープはここまでの手順の用意であり、実施は代表が行う。**

## 9. Google Play 関連の申告事項（PR本文にも記載）

- **App content → Foreground service permissions**: `FOREGROUND_SERVICE_LOCATION` の
  申告と用途の説明文、デモ動画が必要（Play Console 側の設定・本 Issue のスコープ外だが
  実装により必要になった申告として記録する）。
- **データセーフティ**（T104が本体を作成。ここでは事実のみ記録）: 位置情報（正確な位置）を
  収集し、端末上で処理する。サーバへは送信しない（`docs/architecture.md` のとおり MVP は
  外部通信ゼロ）。
- バックグラウンド位置の申告は不要（要求していないため）。

## 10. 前提: Google Play services 依存

fused location provider（`com.google.android.gms:play-services-location`）は
Google Play services に依存する。Play services が入っていない端末（一部の中国市場向け端末等）
では `FusedLocationProviderClient` が位置を返さず、記録が0件になる。MVP はこの制約を許容する
（`plan.md` に別途明記が無い場合、端末要件として Play services 搭載を前提とする）。

## 11. 2026-09-11 実機検証と修正の記録（PR #128・Pixel 7a）

PR #128 のマージ前レビューとして実機検証を行い、3件の問題が見つかった。いずれも本ドキュメントが
対象とする実装（`LocationTrackingService.kt`・`LocationSamplingPolicy.kt`）への修正で対応済み。

### 問題1（重大・修正済み）: 権限が無いとアプリがクラッシュする

**症状**: 位置権限を取り消した状態でサービスを起動すると、
`ForegroundServiceDidNotStartInTimeException` でアプリのプロセスごと強制終了された。

**原因**: `Context.startForegroundService()` で起動したサービスは一定時間内に
`Service.startForeground()` を呼ぶことを Android から義務づけられている。修正前の実装は
`LocationTrackingService.onStartCommand` 側でのみ権限を確認し、無ければ `startForeground()` を
一度も呼ばずに `stopSelf()` していたため、この義務に違反してシステムに強制終了された。

**修正**: 権限確認を呼び出し側（`LocationTrackingService.Companion.start`）に移し、権限が
無ければ `startForegroundService()` 自体を呼ばないようにした（戻り値は `Boolean`。
`false` なら起動をリクエストしなかったことを呼び出し側が判別できる）。
`onStartCommand` 側の確認は二重防御として残しているが、その経路でも
`startForeground()`（Android 14+ で `SecurityException` が起きても握りつぶす）を
先に呼んでから `stopSelf()` するよう変更し、クラッシュしない形にした。
確認手順は §8.2 に追記した。

### 問題2（重大・修正済み）: 精度ゲートと測位優先度の矛盾で記録が0件になる

**症状**: 権限ありでサービスは起動・foreground化したが、`location_track.sqlite` が
作られず記録が1件も行われなかった。

**原因**: 既定の優先度 `PRIORITY_BALANCED_POWER_ACCURACY` は Android の公式ドキュメント上
「ブロック単位（約100m）」の精度とされ、GPSを使わずWi-Fi/基地局測位に留まることが多い。
一方で精度ゲート（`maxAcceptedAccuracyMeters`）は既定30mであり、**優先度が返す精度と
ゲートが受け付ける精度がそもそも両立しない**設計になっていた。実機の `dumpsys location`
でも fused=100.0m・network=56.3m・gps(屋内)=156.9m と、全プロバイダが30mを超えていた。

**修正（2026-09-11・代表決定・案A）**: `LocationSamplingPolicy.DEFAULT_PRIORITY` を
`PRIORITY_HIGH_ACCURACY` に変更した。サービスはアプリから明示的に起動されたときだけ動作し
常駐しない（`START_NOT_STICKY`）ため、NFR-1「常時高精度GPSを使わない」の**意図**（未使用時に
電池を消費し続けない）は維持できる、という判断による。精度ゲート（30m）自体は変更していない。
`PRIORITY_HIGH_ACCURACY` なら屋外で通常5〜15m程度の精度になり両立すると見込むが、**これは
推測であり実測していない**。実測はT015（1時間の実歩行）で行い、必要ならしきい値・優先度の
組み合わせを見直す。それでも電池消費が許容できなければ、歩行検出による優先度切り替え（案B）に
進む段階的な進め方とする。詳細・§6参照。

**`plan.md` §7 改定案（本 PR では未反映。PR #128 本文に記載・代表承認後に別PRで反映予定）**:

- 「常時高精度GPSを使わない」の意図＝電池保護は維持する
- プレイ中（サービス稼働中）に限り `PRIORITY_HIGH_ACCURACY` を使う。サービスは常駐せず、
  アプリから起動したときだけ動く
- `BALANCED_POWER`（約100m）はヘクス約50mに対して粗すぎて使えないことが実機で判明した経緯
  （2026-09-11・fusedでhAcc=100m、30mゲートで全破棄）を記録する
- 電池消費はT015で実測し、足りなければ歩行検出による切り替え（案B）に進む

### 問題3（軽微・修正済み）: 精度で破棄したfixがログに残らない

**症状**: 問題2の診断時、精度ゲートで破棄されたfixがログに一切出ず、原因調査が難航した。

**修正**: `LocationTrackingService.handleLocationFix` で、精度不足により破棄する際に
`Log.d`（タグ `LocationTrackingService`）で破棄した fix の精度・累計破棄件数
（`discardedByAccuracyCount`。サービスインスタンス内でのみ保持・永続化しない）を出力するようにした。
T015（1時間の実歩行計測）で「精度不足で何件捨てられたか」を確認する材料になる。
