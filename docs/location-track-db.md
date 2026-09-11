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
  - https://github.com/rokusoudo-product/terra-town/issues/131
  - https://github.com/rokusoudo-product/terra-town/issues/126
supersedes: null
---

# 位置記録DB（`location_track.sqlite`）— スキーマと受け渡し方法

> Issue #123（T046〜T048）で実装。**このドキュメントは Issue #124・#131（Dart 側への
> 読み取り実装）が読む前提の契約書**であり、実装（
> `app/android/app/src/main/kotlin/jp/rokusoudo/terra_town/location/LocationTrackDatabase.kt`）
> と同じ内容を保つこと。スキーマを変更した場合は同じPRで本ドキュメントも更新する。
>
> **2026-09-11 追記・訂正（Issue #131）**: 当初（Issue #124）は Dart 側が
> `package:sqlite3` でこのファイルを直接読み取り専用オープンする設計だったが、実機検証
> （PR #129・Pixel 7a）で、同一プロセス内に Kotlin（`android.database.sqlite`）と
> Dart（`package:sqlite3`）という**2つの別々の SQLite** が同じ WAL ファイルを扱う構成に
> なっており、これが SQLite 公式の警告する構成（§3参照）に該当し、Kotlin が記録した
> 新しい行が Dart 側に最大2分以上届かない不具合を起こすことが判明した。**この方針は
> 撤回し、`location_track.sqlite` を開くのは Kotlin だけにした。** Dart 側
> （`packages/location/lib/src/position/native_position_provider.dart`）は Pigeon の
> host API（`pigeons/location_api.dart`・`LocationTrackingHostApi.getLocationPoints`）
> 経由で行を受け取る（旧実装 `location_track_connection.dart` は削除済み）。
> `possible_mock_location` は `GeoPosition.spoofSuspected` へそのまま写す
> （判定ロジック自体は Issue #126）。位置記録サービスの起動・停止・状態問い合わせに加え、
> 位置データそのものも Pigeon（`pigeons/location_api.dart`）経由で渡す。
>
> **2026-09-11 追記（Issue #126・T099・T101）**: `possible_mock_location`
> （`GeoPosition.spoofSuspected`）を使って開拓を無効化する判定
> （`RewardPolicy.allowsDisclosure`）と、歩数センサー突合（`step_count` 列・
> schema v3）を実装した。スキーマは v2→v3 に改訂し、`onUpgrade` を段階的な
> 移行ループに変更した（§4「段階的な移行ループ」参照）。

## 1. なぜゲーム状態DB（Drift）と別ファイルにするのか

ゲーム状態DB（`disclosed_hex` 等）は **Drift（Dart 側）がスキーマとマイグレーションを管理**
している（`packages/location/lib/src/db/game_database.dart`・`schemaVersion` 2）。
Kotlin が Drift 管理下のテーブルに直接 `INSERT` すると、スキーマの正が2箇所（Drift の
Dart 定義と Kotlin の DDL）に分裂し、Drift 側のマイグレーションと Kotlin の書き込みが
ずれたときに**例外を出さずに静かに壊れる**（Issue #123 本文・2026-09-11 代表決定②）。

そのため、位置記録は完全に別ファイル `location_track.sqlite` に置く。**このファイルの
スキーマの所有者は Kotlin 側のみ**。**Dart 側はこのファイルを一切開かない**
（Issue #131・§3参照。Pigeon の host API 経由で行を受け取る）。

## 2. ファイルの場所

**保存先ディレクトリ**: `context.getDir("flutter", Context.MODE_PRIVATE)`
（実体は `/data/user/<userId>/jp.rokusoudo.terra_town/app_flutter/`）。

これは Flutter エンジン自身の `io.flutter.util.PathUtils.getDataDirectory(Context)` の
実装と**全く同じディレクトリ**である（`getDir("flutter", MODE_PRIVATE)` を呼んでおり、
`context.getDir` はディレクトリが無ければ作成する。バイトコード〔`javap`〕で実装を確認済み・
2026-09-11）。ゲーム状態DB（`game_state.sqlite`・`game_database.dart`）も
`path_provider` の `getApplicationDocumentsDirectory()`（Dart API）で同じディレクトリを
指しており、**このファイルと同じディレクトリに既に置かれている**。

**ファイル名**: `location_track.sqlite`（`game_state.sqlite` と同じディレクトリ内の別ファイル。
衝突しない）。

Kotlin 側の実装は `LocationTrackSchema.resolveDatabaseFile(context)`
（`LocationTrackDatabase.kt`）。`SQLiteOpenHelper` へは絶対パスを `name` として渡している
（`Context#getDatabasePath` は名前が `/` から始まる場合、そのディレクトリをそのまま使う、
という Android フレームワークの既定動作を利用）。

**2026-09-11 追記（Issue #131）**: 以前はこの節が「Dart 側は
`getApplicationDocumentsDirectory()` を呼ぶだけでこのファイルを見つけて直接開ける」と
案内していたが、**この経路（Dart が直接ファイルを開く）は§3の理由により廃止した**。
現在、このディレクトリ・ファイルパスに触れるのは Kotlin 側の実装のみである。Dart 側
（`NativePositionProvider`）はファイルパスを一切知らず、Pigeon の host API
（`pigeons/location_api.dart`）を呼ぶだけになった。

## 3. なぜ Kotlin だけがこのファイルを開くのか（Issue #131・重要な一般ルール）

> ⚠️ **一般ルール**: **同じ SQLite ファイルを Kotlin と Dart の両方から開いてはならない。**
> これは `location_track.sqlite` に限らず、今後 Drift 管理下のゲーム状態DB
> （`game_state.sqlite`）や新しい DB ファイルを追加する場合にも適用される。

### 3.1 当初の設計（Issue #124・撤回済み）とその破綻

当初は `packages/location/lib/src/db/region_pack_connection.dart`（地域パックDB・
Issue #83）と同じパターンで、Dart 側が `package:sqlite3` を使い
`sqlite3.sqlite3.open(path, mode: OpenMode.readOnly)` でこのファイルを直接
読み取り専用オープンしていた（`OpenMode.readOnly` により書き込み系SQL文は
`SQLITE_READONLY` でエラーになる、という構造的な安全策自体は妥当だった）。

しかし **2026-09-11 の実機検証（PR #129・Pixel 7a）で、Kotlin が記録した新しい行が
Dart 側に最大2分以上（ポーリング24回分）届かないことが決定的に再現した**
（時系列の証拠は
[PR #129 の検証コメント](https://github.com/rokusoudo-product/terra-town/pull/129#issuecomment-5629791422)）。

**原因**: 同じアプリプロセスの中で、**2つの別々の SQLite** が同じ WAL ファイルを
扱っていた。

- Kotlin: Android 標準の SQLite（`android.database.sqlite`）
- Dart: `package:sqlite3` + `sqlite3_flutter_libs` が同梱する SQLite

これは SQLite 公式
[How To Corrupt An SQLite Database File §2.2.1「Multiple copies of SQLite linked
into the same application」](https://www.sqlite.org/howtocorrupt.html) が明示的に
警告している構成である。POSIX のファイルロックはプロセス単位のため、同じプロセス内の
別々の SQLite 実装同士は互いのロックを認識できず、WAL の共有メモリ（`-shm`）の協調が
成り立たない。実機の症状（開く順序によっては届く・届かない、届くまで最大2分かかる、
画面を開き直す＝新しい接続を開くとその時点までの行は見える）はこれと整合する
（内部のメカニズムまでは追跡していない）。

**やってはいけない直し方**（どちらも問題を残す。Issue #131 で明示的に不採用とした）:

- **開く順序の調整**（Kotlin を先に開かせる）: 実機で「Kotlin が先に開けば届いた」
  ことは確認したが、これは安全な構成になったわけではなく、問題が表に出なかっただけ。
- **ポーリングごとに Dart の接続を開き直す**: 開くたびに `-shm` の初期化判定が走り、
  Kotlin 側の WAL インデックスを壊しうる。現状より悪化する。

### 3.2 修正後の設計（現在の実装）

**`location_track.sqlite` を開くのは Kotlin（`LocationTrackDatabaseHelper`）だけ**にした。
書き込み側（`LocationTrackingService`）と読み取り側（`LocationApiHandler`・Pigeon
ハンドラ）は、`LocationTrackDatabaseHelper.getInstance(context)` が返す**プロセス内で
共有された同一インスタンス**を使う（別々の `SQLiteOpenHelper` インスタンスを作らない。
理由は同クラスのdoc参照）。Dart 側（`NativePositionProvider`）はこのファイルのパスさえ
知らず、Pigeon の host API（`LocationTrackingHostApi.getLocationPoints`・`@async`）を
呼んで行を受け取る（`pigeons/location_api.dart` 参照）。

### WAL（Write-Ahead Logging）に関する注意

Kotlin 側は `enableWriteAheadLogging()` で WAL を有効にしている（同一プロセス内の
書き込み側接続と読み取り側接続——今は両方とも Android 標準 SQLite の、同じ
`LocationTrackDatabaseHelper` インスタンスが管理する接続——が同時にアクセスできる
ようにするため）。WAL 使用時は本体ファイルに加えて `location_track.sqlite-wal` /
`location_track.sqlite-shm` のサイドカーファイルが生成され、**直近の書き込みは本体
ファイルではなくこれらのサイドカーにしか無いことがある**。

- **`-wal`/`-shm` を消したり分離したりしないこと。** 端末から取り出す場合は
  常に3ファイルまとめてコピーすること（§8.3参照。以前の版は「サービス停止後なら
  本体ファイル単体で取り出せる」としていたが、後述のとおり誤りだったため訂正した）。
- ~~Dart の `sqlite3` パッケージ（`package:sqlite3`）は Android プラットフォームの
  SQLite とは別のSQLiteビルドを使うが、WAL フォーマットは SQLite間で相互互換である
  ため、Kotlin が書いた WAL を Dart 側の別ビルドから問題なく読める。~~
  **この記述は「ファイル形式の互換性」としては正しいが、「同一プロセスでの同時利用」
  については誤りだった（Issue #131・§3.1 参照）。ファイル形式が互換であることと、
  同じプロセス内で2つの独立した SQLite 実装が同じ WAL ファイルに同時アクセスして
  安全であることは別の問題であり、後者は SQLite 公式が明示的に警告している。**
- **`LocationTrackDatabaseHelper` は明示的に `close()` しない**（Issue #131・
  2026-09-11 決定）。以前はサービスの `onDestroy()` が `close()` を呼び、「WALデータベースは
  最後の接続が閉じられた時点で自動的にチェックポイントされる」ことを期待していた。
  しかしヘルパーを書き込み側・読み取り側で共有する現在の設計では、サービス停止時に
  閉じると Pigeon ハンドラ側の読み取りが壊れる（次回読み取り時に接続を作り直す必要が
  生じ、それ自体が §3.1「ポーリングごとに接続を開き直す」と同種の問題を Kotlin 側で
  再現してしまう）。そのため**アプリのプロセスが生存している間、接続は開いたままにする**
  （`LocationTrackDatabaseHelper.getInstance` のドキュメント参照）。WAL は SQLite が
  既定で約1000ページごとに自動チェックポイントするため `-wal` が無制限に肥大化する
  ことはないが、**「サービス停止＝チェックポイント済み」という前提はもう成り立たない**。
  取り出しは常に3ファイル（本体・`-wal`・`-shm`）をまとめて行うこと（§8.3参照）。

## 4. スキーマ（DDL・実装からそのまま転記）

出典: `app/android/app/src/main/kotlin/jp/rokusoudo/terra_town/location/LocationTrackDatabase.kt`
の `LocationTrackSchema`。

```sql
CREATE TABLE IF NOT EXISTS location_track_meta (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL
);
-- 初期化時に1行だけ挿入: ('schema_version', '2')

CREATE TABLE IF NOT EXISTS location_point (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id TEXT NOT NULL,
    elapsed_realtime_nanos INTEGER NOT NULL,
    wall_clock_unix_millis INTEGER NOT NULL,
    latitude REAL NOT NULL,
    longitude REAL NOT NULL,
    accuracy_meters REAL,
    possible_mock_location INTEGER NOT NULL DEFAULT 0,
    inserted_at_unix_millis INTEGER NOT NULL,
    hex_id INTEGER,
    step_count INTEGER
);

CREATE INDEX IF NOT EXISTS idx_location_point_session
ON location_point (session_id, id);
```

現在の `schema_version` = **3**（Issue #126・`step_count` 列を追加。移行手順は
下記参照。v2までの経緯は「移行手順（v1→v2）」節に残す）。
将来さらにスキーマを変更する場合は `LocationTrackDatabaseHelper.onUpgrade` に
移行処理を追加し（未対応の版の組み合わせは例外を投げる＝スキーマ変更を実装せず
放置すると即座にクラッシュして気づける設計を維持する）、
`location_track_meta.schema_version` の値も一緒に更新すること。

### 段階的な移行ループ（Issue #126）

`onUpgrade` は `oldVersion` から `newVersion` まで **1バージョンずつ順に**
移行を適用する（`for (fromVersion in oldVersion until newVersion) { applyMigrationStep(db, fromVersion) }`）。
端末が複数世代分のスキーマ改訂を一度にまたいで更新される場合（例:
schema_version 1 のまま長期間更新していなかった端末が、schema_version 3 の
本アプリへ一気に更新される）に、v1→v2→v3 を順に適用できるようにするための
設計である。`location_track_meta.schema_version` の更新は各ステップの途中では
行わず、ループの最後に一度だけ `newVersion` へ更新する。未知のバージョン
（`applyMigrationStep` が対応しない `fromVersion`）に遭遇した場合は、これまで
どおり例外を投げて止める（実装せずに放置して静かに壊れることを避けるため）。

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
| `hex_id` | INTEGER（NULL可・v2で追加） | 緯度経度から `H3HexIndexer`（解像度11・`docs/terrain.md` §4.2）が記録時点で計算した H3 インデックス。**列自体は NULL 許容だが、新規挿入では必ず値が入る**（SQLite は既定値なしの列を `ALTER TABLE` で `NOT NULL` にできないため列制約としては表現できない。v1→v2 移行で既存行もバックフィル済み）。Pigeon 経由で `GeoPosition.hexId` としてそのまま Dart へ渡る（Issue #108）。 |
| `step_count` | INTEGER（NULL可・v3で追加） | 歩数センサー（`TYPE_STEP_COUNTER`）による、記録時点までの累積歩数。**`hex_id` と異なり、新規挿入でも NULL になりうる**。歩数センサーが無い端末・`ACTIVITY_RECOGNITION` 権限（API 29+）が無い端末・まだ最初のセンサーイベントを受け取っていない場合は NULL（罰しない側に倒す設計・Issue #126）。v2→v3 移行では既存行を **バックフィルしない**（既存行は歩数データを持たないため、NULL＝「不明」が正しい値）。Pigeon 経由で `GeoPosition.cumulativeStepCount` としてそのまま Dart へ渡る（Issue #126）。 |

### 移行手順（v1→v2・Issue #108・このリポジトリで初めての本物のマイグレーション）

`hex_id` 列の追加に伴う移行。`LocationTrackDatabaseHelper.onUpgrade`
（`oldVersion=1, newVersion=2`）が次を行う:

1. `ALTER TABLE location_point ADD COLUMN hex_id INTEGER`（NULL許容のまま追加）。
2. 既存の全行を `(id, latitude, longitude)` で読み出し、`H3HexIndexer.locate` で
   `hex_id` を計算して1行ずつ `UPDATE location_point SET hex_id = ? WHERE id = ?` で
   バックフィルする。
3. `UPDATE location_track_meta SET value = '2' WHERE key = 'schema_version'`。

**同一トランザクションで行う理由**: `SQLiteOpenHelper` は `onUpgrade` 呼び出し自体を
既に1つのトランザクション（`beginTransaction()` … `setVersion(2)` …
`setTransactionSuccessful()` … `endTransaction()`）で包んでいる（`getDatabaseLocked` の
実装）。そのため上記1〜3のいずれかで例外が起きても、フレームワークが提供する外側の
トランザクションによって「列だけ追加されて `hex_id` が空欄の行が残る」という
中途半端な状態にはならない。実装（`onUpgrade`）は独自に入れ子のトランザクションを
開始していない（入れ子にする場合は `setTransactionSuccessful()` を対で呼ばないと
外側のトランザクションまでロールバックしてしまう点に注意）。

**テスト方針**: Android の `SQLiteOpenHelper` ライフサイクル全体を JVM 単体テストで
動かすには Robolectric が必要になり、初めての Kotlin テスト導入と同時に入れるのは
重いと判断した。代わりに、移行SQL自体（`LocationTrackMigrations` の3つの文字列定数。
本番コードと文字どおり同じ定数）を xerial の `sqlite-jdbc`（JVM から使える純粋な
SQLite 実装）に対して実行するテスト（`LocationTrackMigrationV1ToV2Test`）を書いた。
**このテストが検証するのは SQL 文自体の効果であり、Android の `SQLiteOpenHelper` の
呼び出しタイミングそのものではない**。実機の既存DB（schema_version 1）への
上書きインストールでの確認は§8で行う。

### 移行手順（v2→v3・Issue #126・T101）

`step_count` 列の追加に伴う移行。`LocationTrackDatabaseHelper.onUpgrade` の
段階的ループ（上記「段階的な移行ループ」参照）が `fromVersion=2` の
ステップとして次を行う:

1. `ALTER TABLE location_point ADD COLUMN step_count INTEGER`（NULL許容のまま追加）。
2. **既存行のバックフィルは行わない**（v1→v2 のときと異なる点。既存行は
   歩数センサーのデータを持たないため、NULL＝「不明」が正しい値。`0` 等で
   バックフィルすると「歩いていないのに移動した」という誤ったシグナルに
   なってしまう）。
3. ループの最後に `UPDATE location_track_meta SET value = ? WHERE key = 'schema_version'`
   で `newVersion`（1バージョンずつのループなので v1 スタートなら最終的に
   `3`）に更新する。

v1 の端末が本アプリに更新される場合は、`fromVersion=1`（v1→v2 の hex_id
バックフィル）→ `fromVersion=2`（本ステップ）の順に適用され、`hex_id` は
バックフィルされるが `step_count` はバックフィルされない（両者で扱いが
異なる点に注意）。

**テスト方針**: v1→v2 のときと同じ理由（Robolectric 不採用）で、移行SQL自体を
xerial `sqlite-jdbc` に対して実行するテスト（`LocationTrackMigrationTest`。
Issue #126 で `LocationTrackMigrationV1ToV2Test` から改名・拡張）で検証する。
v1→v3（複数ステップの一括適用）・v2→v3（単一ステップ）の両方をテストしている。
実機の既存DB（schema_version 1 または 2）への上書きインストールでの確認は
§8.7 で行う。

### 歩数突合の閾値（Issue #126・正本は将来 `balance.csv`）

`step_count` を使った歩数対距離の突合ロジック本体は `core`（GPS/Kotlin非依存）
の `packages/core/lib/src/antispoof/reward_policy.dart`（`RewardPolicy`）に実装
されている。閾値（歩幅上限・最小ウィンドウ距離・不一致時の倍率）は以下のとおり
（詳細な根拠は同ファイルのクラスdoc参照）:

| 定数 | 既定値 | 意味 |
|---|---|---|
| `RewardPolicy.defaultMaxStrideMeters` | 1.5m | 「歩数 × この値」で説明できる距離とみなす歩幅上限 |
| `RewardPolicy.defaultMinWindowDistanceMeters` | 100m | このウィンドウ内の合計移動距離未満では判定しない |
| `RewardPolicy.defaultStepMismatchMultiplier` | 0.5 | 不一致時の資材付与レート倍率（0にはしない） |

**いずれも仮の値であり、正本は将来 `specs/001-mvp/balance.csv`（Issue #36・
T106・未作成）。作成時はそこへ移す。** 最終調整は `tasks.md` T017（代表の
実機スパイク）で行う。

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
  - **判定はアプリ側で行う（2026-09-11 実機検証で判明）**: `setMinUpdateDistanceMeters` は
    OS に対する省電力のヒントであり、しきい値未満の fix が配送されないことは保証されない。
    実機（Pixel 7a）では直前の記録から **0.86m・46秒後の fix が通常経路で配送された**。
    そのため `handleLocationFix` で直前の記録地点からの距離を計算し、しきい値未満なら
    記録せず `位置破棄（移動距離不足）` をログに出す（`discardedByDistanceCount`）。
    修正後、静止中の約5分間で記録は1件のみになり、0.5〜0.8m の fix が破棄されることを確認した。
  - 時間上限による強制記録（`forcedByTimeCap=true`）はこの距離判定を通さない。
    **ただし精度ゲートは通る**ため、屋内などで強制 fix の精度が悪い場合は記録されない。
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

# 停止
adb shell am start -n jp.rokusoudo.terra_town/.MainActivity \
  --ez terra_town.debug.stopLocationService true
```

**2026-09-11 訂正（Issue #131）**: 以前は上記コメントに「`close()` により WAL が自動的に
チェックポイントされる」と書いていたが、`LocationTrackDatabaseHelper` はサービス停止時に
`close()` しなくなった（§3.2参照。読み取り側〔Pigeon ハンドラ〕と共有しているため）。
記録データを取り出す際は §8.3 のとおり常に3ファイル（本体・`-wal`・`-shm`）をまとめて
取り出すこと。

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

**2026-09-11 訂正（Issue #131）**: 以前は「サービスを停止した後に取り出すと `-wal`/`-shm`
を気にせず1ファイルで完結する」としていたが、`LocationTrackDatabaseHelper` を
サービス（書き込み）と Pigeon ハンドラ（読み取り）で共有し、サービス停止時にも
`close()` しなくなった（§3.2参照）ため、**この前提はもう成り立たない**。
サービスを止めても止めなくても、**常に3ファイル（本体・`-wal`・`-shm`）をまとめて
取り出すこと**:

```bash
adb shell run-as jp.rokusoudo.terra_town \
  cat app_flutter/location_track.sqlite > location_track.sqlite
adb shell run-as jp.rokusoudo.terra_town \
  cat app_flutter/location_track.sqlite-wal > location_track.sqlite-wal
adb shell run-as jp.rokusoudo.terra_town \
  cat app_flutter/location_track.sqlite-shm > location_track.sqlite-shm
sqlite3 location_track.sqlite "SELECT COUNT(*), MIN(id), MAX(id) FROM location_point;"
sqlite3 location_track.sqlite "SELECT * FROM location_point ORDER BY id DESC LIMIT 20;"
```

`-wal`/`-shm` が存在しない（まだ一度もチェックポイントをまたいでいない、または
記録が無い）場合、上記2つの `run-as cat` はエラーになるが無視してよい
（本体ファイルだけで完結する。SQLite が起動時に自動でチェックポイント済みと判断する）。

### 8.4 実機確認手順（Issue #131・回帰確認）

⚠️ **この不具合は単体テストでは構造的に検出できない**（`native_position_provider_test.dart`
はフェイクの [LocationPointsApi] を使っており、Kotlin/Dart 双方の実際の SQLite 実装が
同一プロセスで同じファイルを扱う状況そのものを再現できない）。回帰確認は実機のみで行う
（代表・秘書セッションが実施）。

**両方の順序**で確認すること（Issue #131 の再現手順・PR #129 検証コメントと同じ2パターン）。
いずれも、Kotlin が記録した新しい行が**ポーリング2回以内**（既定 `pollInterval` は5秒なので
概ね10秒以内）にデバッグパネルの「受信した位置」欄に増えることを確認する。

**① サービス停止中に画面を開く→起動**（旧不具合の主な再現条件）:

1. サービスが停止していることを確認する（§8.2「起動確認」で見えないこと）。
2. アプリの画面を開く（デバッグパネルの `NativePositionProvider` が購読を始める）。
3. デバッグパネルの「起動」（または §8.2 の adb コマンド）でサービスを起動する。
4. 位置権限があり、屋外など精度ゲート（§6）を満たす環境であれば、しばらくして
   `location_point` に新しい行が記録される（`adb logcat` の「位置記録」ログ、または
   §8.3 の手順で確認できる）。
5. **その新しい行が、デバッグパネルの「受信した位置」欄にポーリング2回以内
   （約10秒以内）に反映されることを確認する。**

**② サービス稼働中に画面を開き直す**:

1. サービスを稼働させたまま、アプリの画面を一度閉じて開き直す（新しい
   `NativePositionProvider` の購読が始まる）。
2. 稼働中のサービスが次の行を記録するのを待つ。
3. **①と同じく、ポーリング2回以内にデバッグパネルへ反映されることを確認する。**

いずれの順序でも②と同等の速さで届けば、Issue #131 の不具合（開く順序に依存して
最大2分以上届かないことがある）は解消している。

### 8.5 T015（1時間の実歩行・電池と測位品質の計測）手順案

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

### 8.6 実機確認手順（Issue #108・スキーマ移行・hex_id の一致確認）

⚠️ この確認も単体テストでは構造的に検出できない部分がある。`H3HexIndexerTest`・
`LocationTrackMigrationV1ToV2Test`（JVM 単体テスト・§4「移行手順」参照）は
Kotlin実装とSQL自体の正しさを検証するが、**実機の `SQLiteOpenHelper` が実際に
`onUpgrade` を正しいタイミングで呼ぶか**・**Pigeon 経由で Dart に渡った `hexId` が
DBの値と一致するか**は実機でのみ確認できる。

**① 既存DB（schema_version 1）からの移行確認**（本 Issue のリリースを、
schema_version 1 のまま運用していた既存インストールへ上書きインストールする形で
確認する。アプリを消さずに上書きインストールする点が重要——既存DBがそのまま
移行の実地テストになる）:

1. 上書きインストール前に、§8.3 の手順で `location_track.sqlite` を取り出し、
   `sqlite3 location_track.sqlite "SELECT value FROM location_track_meta WHERE key='schema_version';"`
   で `1` であることを確認しておく（バックアップとしても保存しておく）。
2. 本 Issue を含むビルドを上書きインストールし、アプリを起動する（`onUpgrade` が
   一度だけ走るはずのタイミング）。
3. 再度 §8.3 の手順で取り出し、次を確認する:
   - `sqlite3 location_track.sqlite "SELECT value FROM location_track_meta WHERE key='schema_version';"` が `2` になっている。
   - `sqlite3 location_track.sqlite "SELECT COUNT(*) FROM location_point WHERE hex_id IS NULL;"` が `0`
     （既存行が全件バックフィルされている）。
   - 移行前に記録されていた行の緯度経度から次のコマンドで単発計算した `hex_id` と、
     実際に入っている値が一致する（`generate_hex_locator_fixture.py` は固定の37点
     フィクスチャしか出力しないため、任意の緯度経度を単発計算するにはこちらを使う）:
     ```bash
     cd tools/pack-builder
     ./.venv/bin/python -c "import h3; print(h3.str_to_int(h3.latlng_to_cell(LAT, LON, 11)))"
     ```
     （`LAT`/`LON` を実際の値に置き換える）

**② hexId のパネル表示とDBの値の一致確認**（int64がPigeonで丸められていないかの
実測。§8.4 のデバッグパネル確認と同じ流れに追加する）:

1. §8.4 の手順で位置記録を起動し、デバッグパネルの「受信した位置」欄に新しい行が
   表示されるのを待つ（`hexId=...` が表示される。`location_tracking_debug_panel.dart`）。
2. §8.3 の手順で `location_track.sqlite` を取り出し、同じ `id` の行の `hex_id` 列の
   値を確認する。
3. **パネル表示の `hexId` と DB の `hex_id` が完全一致することを確認する**
   （2^53を超える値でも一致すれば、Pigeon の `StandardMessageCodec` 経由で
   int64が丸められていないことの実測確認になる。`native_position_provider_test.dart`
   の合成値でのテストと合わせて、実測と単体テストの両方でカバーする）。

**③ h3-javaネイティブが実機で読み込めるかの確認（Issue #108・重要）**:

実装中、`com.uber:h3:4.5.0` のネイティブ（`libh3-java.so`）をAPKに正しく同梱するには
AGPの標準の `jniLibs` パッケージング（`build.gradle.kts` の `extractH3NativeLibs`
タスク）が必要であることが判明し、修正済み（`unzip -l app-debug.apk` で
`lib/arm64-v8a/libh3-java.so` 等が含まれることを確認済み）。加えて、Android実行時は
`H3Core.newSystemInstance()`（`System.loadLibrary("h3-java")` 経由）を使うよう
`H3HexIndexer` を実装している（`H3Core.newInstance()` はクラスパスリソース経由の
読み込みで、AGPの通常パッケージングでは同梱されない別の仕組みのため）。

**この一連の対応（APKへの同梱＋`newSystemInstance`の使用）が実機で実際に
`H3Core` の初期化に成功するかどうかは、本Issueの実装セッションでは検証できていない
（エミュレータはandroid-x86_64ネイティブが無いため使えず、実機も持たない）。
以下を確認すること**:

1. サービスを起動し、精度・距離ゲートを満たす位置で記録が発生することを確認する
   （§8.2〜§8.4の手順）。
2. `adb logcat` で `H3HexIndexer`/`IllegalStateException`（`H3Core の初期化に
   失敗しました`）のクラッシュが出ていないことを確認する。
3. 上記①・②の手順で `hex_id` が実際に埋まっていることを確認する（`hex_id` が
   NULLのまま、またはアプリがクラッシュする場合は、`H3HexIndexer` のクラスdoc
   「実行環境によって H3Core の初期化方法を分けている」の節を参照し、カスタム
   ローダー〔`nativeLibraryDir` から直接 `System.load` する等〕への切り替えを検討する）。

**本 Issue（#123・#108）のスコープはここまでの手順の用意であり、実施は代表が行う。**

### 8.7 実機確認手順（Issue #126・T099・T101・モック検出の無効化と歩数センサー突合）

⚠️ この確認も単体テストでは構造的に検出できない部分がある。`reward_policy_test.dart`・
`LocationTrackMigrationTest` は合成データ・SQL自体の正しさを検証するが、**実機の
`SensorManager` が実際に `TYPE_STEP_COUNTER` イベントを配送するか**・**モック位置
アプリでの検出が実際に開拓を止めるか**・**正規の歩行で報酬が没収されないか**は
実機でのみ確認できる。

**① `ACTIVITY_RECOGNITION` 権限の有無での歩数取得確認**:

```bash
# 権限を与えずに起動 → デバッグパネルの steps= が常に null のままであること
adb shell pm revoke jp.rokusoudo.terra_town android.permission.ACTIVITY_RECOGNITION
# サービスを起動（§8.2）→ 歩いて記録を発生させる → デバッグパネルで steps=null を確認

# 権限を与えて起動 → steps= が増えていくこと
adb shell pm grant jp.rokusoudo.terra_town android.permission.ACTIVITY_RECOGNITION
# サービスを再起動 → 歩いて記録を発生させる → デバッグパネルで steps= の値が増加することを確認
```

いずれの場合もサービス自体は正常に起動し記録が続くこと（歩数センサーの可否が
位置記録そのものを妨げないこと）を確認する。

**② モック位置アプリでの検出確認**（開発者向け設定でモック位置アプリを選択し、
実際に位置を偽装するアプリで確認する）:

1. モック位置アプリを有効にし、現在地から離れた地点をモック位置として設定する。
2. サービスを起動し、モック位置が記録されることを確認する（`adb logcat` の
   「位置記録」ログ、または §8.3 の手順で `possible_mock_location` が `1` の行を
   確認する）。
3. デバッグパネルの該当行で `spoofSuspected=true` になっていることを確認する。
4. **アプリ側でその位置を含むヘクスの開拓（霧が晴れる表示）が起きないこと**を
   確認する（`RewardPolicy.allowsDisclosure`・`DisclosureService.recordPosition`
   の実装が実機でも機能していることの確認。地図描画への実際の配線は Issue #99・
   #100 の範囲であり、本確認はその配線ができている前提で行う）。

**③ 正規歩行で報酬（開拓・付与レート）が没収されないことの確認**:

1. モック位置を使わず、通常の徒歩でサービスを起動し、しばらく歩く。
2. 歩いた範囲の霧が晴れる（開拓される）ことを確認する。
3. デバッグパネルの位置ログで `spoofSuspected=false`・`steps=` が距離に見合って
   増えていることを確認する（極端に少ない場合は `RewardPolicy` の歩数不一致判定
   により将来の資材付与レートが下がりうる。閾値の妥当性は T017 で確定する）。
4. 本 Issue の時点では資材付与処理自体が未実装（Issue #126 本文「スコープ外」）
   のため、付与レート低下の最終確認（実際に資材が減ることの確認）は付与処理の
   実装後に改めて行う。本確認は「開拓が没収されないこと」・「歩数が概ね妥当に
   計測されること」までとする。

**本 Issue（#126）のスコープはここまでの手順の用意であり、実施は代表が行う。**

## 9. Google Play 関連の申告事項（PR本文にも記載）

- **App content → Foreground service permissions**: `FOREGROUND_SERVICE_LOCATION` の
  申告と用途の説明文、デモ動画が必要（Play Console 側の設定・本 Issue のスコープ外だが
  実装により必要になった申告として記録する）。
- **データセーフティ**（T104が本体を作成。ここでは事実のみ記録）: 位置情報（正確な位置）を
  収集し、端末上で処理する。サーバへは送信しない（`docs/architecture.md` のとおり MVP は
  外部通信ゼロ）。
- バックグラウンド位置の申告は不要（要求していないため）。
- **健康とフィットネス / フィットネス情報（歩数）**（Issue #126・T101で追加）:
  歩数センサー（`TYPE_STEP_COUNTER`）による累積歩数を収集する。**端末内のみで
  使用し、外部へ送信・共有しない**（GPS偽装対策の歩数突合にのみ使う。
  `docs/architecture.md` のとおり MVP は外部通信ゼロ）。`ACTIVITY_RECOGNITION`
  権限（API 29+）が必要。Google Play のデータセーフティ申告（「フィットネス」
  カテゴリ・「歩数」データ型）に追加が必要（T104が本体を作成する
  `docs/data-safety.md` に反映すること）。

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
