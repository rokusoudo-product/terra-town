package jp.rokusoudo.terra_town.location

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import android.util.Log
import java.io.File

/**
 * 位置記録専用のローカル SQLite（Issue #123・plan.md §2「位置記録は Kotlin 側から
 * 直接書き込む・Dart は読むだけ」・Issue #10 代表決定②）。
 *
 * ## なぜゲーム状態DB（Drift）と別ファイルにするのか
 * ゲーム状態DB（`disclosed_hex` 等）は Drift（Dart 側）がスキーマとマイグレーションを
 * 管理している（`schemaVersion` 2・`packages/location/lib/src/db/game_database.dart`）。
 * Kotlin が Drift 管理下のテーブルへ直接 INSERT すると、スキーマの正が2箇所（Drift の
 * Dart 定義と、この Kotlin の DDL）に分裂する。Drift 側がマイグレーションを行っても
 * Kotlin の書き込みはそれを知らないため、**例外を出さずに静かに壊れる**（Issue #123 本文）。
 *
 * そのため位置記録は完全に別のファイル [DATABASE_FILE_NAME] に置き、**このスキーマの
 * 所有者は Kotlin 側のみ**とする。Dart 側（Issue #124）はこのファイルを
 * `packages/location/lib/src/db/region_pack_connection.dart` と同じ手法
 * （`sqlite3.OpenMode.readOnly`）で読み取り専用に開く想定であり、書き込みはしない
 * （＝SQLite自身が書き込みを拒否するため構造的に防がれる）。
 *
 * ## 保存先ディレクトリ（Kotlin ⇔ Dart の受け渡し方法・重要）
 * このファイルは `context.getDir("flutter", Context.MODE_PRIVATE)` に置く。
 * これは Flutter エンジン自身の `io.flutter.util.PathUtils.getDataDirectory(context)`
 * （`getApplicationDocumentsPath` の実体）と**全く同じディレクトリ**であり、
 * `packages/location/lib/src/db/game_database.dart` の `game_state.sqlite` も
 * ここに置かれている（`path_provider` の `getApplicationDocumentsDirectory()`）。
 * つまり Issue #124 の Dart 実装は、**新しいプラットフォームチャンネルを介さず**
 * `getApplicationDocumentsDirectory()` を呼ぶだけでこのファイルを見つけられる。
 * 詳細・検証方法は `docs/location-track-db.md` に記録する。
 *
 * ## スキーマ本体
 * DDL は [LocationTrackSchema] に集約する。`docs/location-track-db.md` にはこの
 * オブジェクトの内容をそのまま転記し、実装（このファイル）とドキュメントの乖離を防ぐ。
 */
object LocationTrackSchema {
    /** ファイル名。ゲーム状態DBの `game_state.sqlite` と同じディレクトリに置くが別ファイル。 */
    const val DATABASE_FILE_NAME = "location_track.sqlite"

    /**
     * スキーマバージョン。[LocationTrackDatabaseHelper] のバージョン引数と同じ値を
     * `location_track_meta` テーブルにも書き込み、Dart 側（Issue #124）が
     * マイグレーション未対応の古い前提で読んでいないかを確認できるようにする。
     */
    const val SCHEMA_VERSION = 1

    const val TABLE_META = "location_track_meta"
    const val TABLE_POINT = "location_point"

    const val CREATE_TABLE_META = """
        CREATE TABLE IF NOT EXISTS $TABLE_META (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
        )
    """

    /**
     * 1測位1行。列の設計方針:
     * - [COLUMN_SESSION_ID]: サービスの起動（`onCreate`）ごとに新しい UUID を発行する
     *   「記録セッションID」。**端末再起動をまたぐ・またがないに関わらず、サービスの
     *   プロセスが新しくなるたびに新しいセッションになる。**
     *   [COLUMN_ELAPSED_REALTIME_NANOS] は同一 [COLUMN_SESSION_ID] 内でのみ比較可能
     *   （`elapsedRealtime` は端末再起動でリセットされるため）。T048 の「再起動をまたぐ
     *   時刻の扱い」の決定は `docs/location-track-db.md` に記録する。
     * - [COLUMN_ELAPSED_REALTIME_NANOS]: `Location.getElapsedRealtimeNanos()`。
     *   端末時刻の改竄に耐性のある単調時計（T048）。速度判定（Issue #125・PR #127）は
     *   これを前提にしている。
     * - [COLUMN_WALL_CLOCK_UNIX_MILLIS]: `Location.getTime()`。**改竄可能な参考情報**。
     *   セッションをまたいだ大まかな時系列表示以外の用途（速度判定・順序保証）に使わないこと。
     * - [COLUMN_ID]（`INTEGER PRIMARY KEY AUTOINCREMENT`）: 挿入順に単調増加し、
     *   セッションをまたいでも順序が保たれ、値が再利用されない。セッションをまたぐ
     *   「大まかな前後関係」はこの列で表現できる（区間の所要時間・速度の計算はしない）。
     * - [COLUMN_POSSIBLE_MOCK_LOCATION]: Android の `Location.isMock()`（API 31+）／
     *   `isFromMockProvider()`（それ未満。deprecated だが唯一の入手経路）の生の値を
     *   0/1 で保存する。**Android の用語をこのカラム名に持ち込まないため、列名は
     *   `possible_mock_location`（中立な名前）にしている。** 本 Issue ではこの値を
     *   使った判定（モック検出そのもの）は実装しない。Issue #126 が読む想定。
     * - [COLUMN_ACCURACY_METERS]: 精度（メートル、`Location.getAccuracy()`）。
     *   値が無い fix は NULL（`Location.hasAccuracy()` が false の場合）。
     */
    const val CREATE_TABLE_POINT = """
        CREATE TABLE IF NOT EXISTS $TABLE_POINT (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            session_id TEXT NOT NULL,
            elapsed_realtime_nanos INTEGER NOT NULL,
            wall_clock_unix_millis INTEGER NOT NULL,
            latitude REAL NOT NULL,
            longitude REAL NOT NULL,
            accuracy_meters REAL,
            possible_mock_location INTEGER NOT NULL DEFAULT 0,
            inserted_at_unix_millis INTEGER NOT NULL
        )
    """

    const val CREATE_INDEX_POINT_SESSION = """
        CREATE INDEX IF NOT EXISTS idx_location_point_session
        ON $TABLE_POINT (session_id, id)
    """

    // location_point の列名（ContentValues のキー・生SQL双方で使うためオブジェクト化）。
    const val COLUMN_ID = "id"
    const val COLUMN_SESSION_ID = "session_id"
    const val COLUMN_ELAPSED_REALTIME_NANOS = "elapsed_realtime_nanos"
    const val COLUMN_WALL_CLOCK_UNIX_MILLIS = "wall_clock_unix_millis"
    const val COLUMN_LATITUDE = "latitude"
    const val COLUMN_LONGITUDE = "longitude"
    const val COLUMN_ACCURACY_METERS = "accuracy_meters"
    const val COLUMN_POSSIBLE_MOCK_LOCATION = "possible_mock_location"
    const val COLUMN_INSERTED_AT_UNIX_MILLIS = "inserted_at_unix_millis"

    const val META_KEY_SCHEMA_VERSION = "schema_version"

    /** [LocationTrackDatabaseHelper] が使う、Flutter と同じアプリ内ディレクトリを解決する。 */
    fun resolveDatabaseFile(context: Context): File {
        val flutterDir = context.applicationContext.getDir("flutter", Context.MODE_PRIVATE)
        return File(flutterDir, DATABASE_FILE_NAME)
    }
}

/**
 * [LocationTrackSchema] の DDL を実際に適用する [SQLiteOpenHelper]。
 *
 * `name` に絶対パス（[LocationTrackSchema.resolveDatabaseFile]）を渡すことで、
 * `Context#getDatabasePath` の既定（`/data/data/<pkg>/databases/`）ではなく
 * `app_flutter/` 配下（Dart 側 `game_state.sqlite` と同じディレクトリ）に置く。
 * `Context#getDatabasePath` は名前が `/` から始まる場合、そのディレクトリをそのまま
 * 使う（Android フレームワークの既定動作）。
 */
class LocationTrackDatabaseHelper(context: Context) :
    SQLiteOpenHelper(
        context.applicationContext,
        LocationTrackSchema.resolveDatabaseFile(context).absolutePath,
        null,
        LocationTrackSchema.SCHEMA_VERSION,
    ) {

    override fun onConfigure(db: SQLiteDatabase) {
        super.onConfigure(db)
        // Kotlin（書き込み）と Dart（Issue #124・読み取り専用の別接続）が同時にファイルへ
        // アクセスできるよう WAL を使う。docs/location-track-db.md に取り出し手順（-wal/-shm
        // を含めて pull する、またはサービス停止〔close()で自動チェックポイント〕後に
        // pull する）を記録する。
        db.enableWriteAheadLogging()
    }

    override fun onCreate(db: SQLiteDatabase) {
        db.execSQL(LocationTrackSchema.CREATE_TABLE_META)
        db.execSQL(LocationTrackSchema.CREATE_TABLE_POINT)
        db.execSQL(LocationTrackSchema.CREATE_INDEX_POINT_SESSION)
        val values = ContentValues().apply {
            put("key", LocationTrackSchema.META_KEY_SCHEMA_VERSION)
            put("value", LocationTrackSchema.SCHEMA_VERSION.toString())
        }
        db.insertOrThrow(LocationTrackSchema.TABLE_META, null, values)
    }

    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
        // Issue #123 時点でスキーマ改訂の実績はない。将来スキーマを変更する場合は、
        // ここに ALTER TABLE 等の移行処理を実装し、location_track_meta.schema_version の
        // 値も更新すること。実装せずに例外を投げるのは「静かに壊れる」ことを避けるため
        // （Issue #123 本文が Drift との齟齬について指摘している問題と同種の事故を、
        // Kotlin 側スキーマ自身の将来の改訂でも起こさないための意図的な設計）。
        // 手順は docs/location-track-db.md に記録すること。
        throw IllegalStateException(
            "location_track.sqlite の onUpgrade は未実装です " +
                "(oldVersion=$oldVersion, newVersion=$newVersion)。" +
                "docs/location-track-db.md の移行手順に従って実装してください。",
        )
    }

    /** 1測位分を挿入する。呼び出し側（[LocationTrackingService]）が値の妥当性を確認済みであること。 */
    fun insertPoint(
        sessionId: String,
        elapsedRealtimeNanos: Long,
        wallClockUnixMillis: Long,
        latitude: Double,
        longitude: Double,
        accuracyMeters: Float?,
        possibleMockLocation: Boolean,
    ) {
        val values = ContentValues().apply {
            put(LocationTrackSchema.COLUMN_SESSION_ID, sessionId)
            put(LocationTrackSchema.COLUMN_ELAPSED_REALTIME_NANOS, elapsedRealtimeNanos)
            put(LocationTrackSchema.COLUMN_WALL_CLOCK_UNIX_MILLIS, wallClockUnixMillis)
            put(LocationTrackSchema.COLUMN_LATITUDE, latitude)
            put(LocationTrackSchema.COLUMN_LONGITUDE, longitude)
            if (accuracyMeters != null) {
                put(LocationTrackSchema.COLUMN_ACCURACY_METERS, accuracyMeters)
            } else {
                putNull(LocationTrackSchema.COLUMN_ACCURACY_METERS)
            }
            put(LocationTrackSchema.COLUMN_POSSIBLE_MOCK_LOCATION, if (possibleMockLocation) 1 else 0)
            put(LocationTrackSchema.COLUMN_INSERTED_AT_UNIX_MILLIS, System.currentTimeMillis())
        }
        writableDatabase.insertOrThrow(LocationTrackSchema.TABLE_POINT, null, values)
    }

    /**
     * `onDestroy` から呼ぶ。
     *
     * 【`PRAGMA wal_checkpoint` を明示実行しない理由】
     * `wal_checkpoint` は結果を1行返すPRAGMAであり、Android の `SQLiteDatabase#execSQL` は
     * 行を返すSQL文を受け付けない（OSバージョンによっては
     * `SQLiteException: Queries can be performed using SQLiteDatabase query or rawQuery
     * methods only` を投げる）。これを `onDestroy` で踏むと、まさに代表がサービスを止めて
     * データを取り出そうとした瞬間にアプリがクラッシュする。
     *
     * 代わりに単に [close] を呼ぶ。WALデータベースは**最後の接続が閉じられた時点で
     * SQLite自身が自動的にチェックポイントし `-wal`/`-shm` を解消する**ため、
     * 明示的なPRAGMAが無くても同じ効果が得られる（`docs/location-track-db.md` §3・§8.2）。
     * また [close] は一度も `writableDatabase`/`readableDatabase` を呼んでいない
     * （＝DBファイルを一度も開いていない）状態では何もしない安全な no-op であるため、
     * 権限が無く記録が一度も行われなかった経路（`onStartCommand` → `stopSelf` →
     * `onDestroy`）でも空のDBファイルを新規作成してしまうことがない。
     */
    fun closeQuietly() {
        try {
            close()
        } catch (e: Exception) {
            Log.e(TAG, "location_track.sqlite のクローズに失敗しました", e)
        }
    }

    companion object {
        private const val TAG = "LocationTrackDatabase"
    }
}
