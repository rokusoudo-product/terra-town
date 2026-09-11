package jp.rokusoudo.terra_town.location

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
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
 * 所有者は Kotlin 側のみ**とする。
 *
 * ## ⚠️ このファイルを開くのは Kotlin だけ（Issue #131・2026-09-11 代表決定。方針転換）
 * 当初（Issue #123・#124）は、Dart 側が `packages/location/lib/src/db/region_pack_connection.dart`
 * と同じ手法（`sqlite3.OpenMode.readOnly`）でこのファイルを直接読み取り専用に開く設計
 * だった。**しかし実機検証（PR #129・Pixel 7a）で、この設計が SQLite 公式が警告する
 * 「同一プロセス内の複数の SQLite」構成
 * （[How To Corrupt An SQLite Database File §2.2.1](https://www.sqlite.org/howtocorrupt.html)）
 * に該当し、Kotlin が書いた新しい行が Dart 側に最大2分以上届かない不具合を起こすことが
 * 判明したため、この方針は撤回した**（詳細: Issue #131・
 * [PR #129 の検証コメント](https://github.com/rokusoudo-product/terra-town/pull/129#issuecomment-5629791422)）。
 *
 * 現在の設計: **Dart はこのファイルを一切開かない**。読み取りも Kotlin
 * （[LocationTrackDatabaseHelper.selectPointsAfter]）が行い、Pigeon の host API
 * （`LocationTrackingHostApi.getLocationPoints`・`LocationApiHandler.kt`）経由で
 * Dart の `NativePositionProvider` に行を渡す。**同じ SQLite ファイルを Kotlin と Dart の
 * 両方から開いてはならない、という一般ルールは今後 Drift のゲーム状態DB等に他のファイルを
 * 追加する場合にも適用される**（`docs/location-track-db.md` §3 参照）。
 *
 * ## 保存先ディレクトリ
 * このファイルは `context.getDir("flutter", Context.MODE_PRIVATE)` に置く。
 * これは Flutter エンジン自身の `io.flutter.util.PathUtils.getDataDirectory(context)`
 * （`getApplicationDocumentsPath` の実体）と**全く同じディレクトリ**であり、
 * `packages/location/lib/src/db/game_database.dart` の `game_state.sqlite` も
 * ここに置かれている（`path_provider` の `getApplicationDocumentsDirectory()`）。
 * このディレクトリを Dart 側から直接読みに行くことはもう無いが、Kotlin 側の
 * 保存先自体はこれまでどおり（詳細・検証方法は `docs/location-track-db.md`）。
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
     * `location_track_meta` テーブルにも書き込む。
     *
     * 【Issue #131 追記】以前（Issue #124）は Dart 側の `LocationTrackConnection` が
     * このメタ情報を読み、マイグレーション未対応の古い前提で読んでいないかを自前で
     * 確認していた。現在は読み取りも同じ [LocationTrackDatabaseHelper] インスタンス
     * （[getInstance]）を介して Kotlin が行うため、スキーマの整合性は
     * `SQLiteOpenHelper` のバージョン機構（[onUpgrade]）がそもそも保証しており、
     * Dart 側での二重確認は不要になった。この列自体はデバッグ・実機確認用の
     * メタ情報として残す。
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
 *
 * ## プロセス内で1インスタンスに共有する理由（Issue #131）
 * このファイル（`location_track.sqlite`）は、書き込み側（[LocationTrackingService]）と
 * 読み取り側（`LocationApiHandler.kt`・Pigeon 経由）の**両方から Kotlin だけが**
 * アクセスする設計に変更した（Issue #131 本文・`pigeons/location_api.dart` の
 * ドキュメント参照。以前は Dart 側が `package:sqlite3` で直接この WAL ファイルを
 * 開いており、同一プロセス内に2つの別々の SQLite 実装が存在する構成——SQLite公式
 * [How To Corrupt An SQLite Database File §2.2.1](https://www.sqlite.org/howtocorrupt.html)
 * が警告する構成——が実機で不具合を引き起こしていた）。
 *
 * 書き込み側と読み取り側で**別々の `SQLiteOpenHelper` インスタンス**を作ってしまうと、
 * Android 標準の SQLite 実装同士とはいえ、同一プロセス内で同じファイルに対する
 * ロック・キャッシュ管理が二重になる（`SQLiteDatabase` はプロセス内のロック調停を
 * 前提にしており、`SQLiteDatabaseConfiguration`・接続プールはインスタンス単位で
 * 管理される）。そのため [getInstance] で**プロセス内に1インスタンスだけ**を
 * 生成し、[LocationTrackingService]（書き込み）と Pigeon ハンドラ（読み取り）の
 * 双方がこの同じインスタンスを共有する。
 */
class LocationTrackDatabaseHelper private constructor(context: Context) :
    SQLiteOpenHelper(
        context.applicationContext,
        LocationTrackSchema.resolveDatabaseFile(context).absolutePath,
        null,
        LocationTrackSchema.SCHEMA_VERSION,
    ) {

    override fun onConfigure(db: SQLiteDatabase) {
        super.onConfigure(db)
        // Issue #131: 書き込み（LocationTrackingService）と読み取り（LocationApiHandler・
        // Pigeon 経由）は、いずれもこの同じ LocationTrackDatabaseHelper インスタンス
        // （getInstance 参照）を介した Android 標準 SQLite の接続。WAL を有効にすることで
        // 書き込み中でも読み取り側がブロックされない（SQLiteOpenHelper が内部で管理する
        // 接続プールが協調する）。取り出し手順（常に -wal/-shm を含めて pull する）は
        // docs/location-track-db.md §8.3 に記録する。
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
     * `location_point` から `id` が [afterId] より大きい行を `id` 昇順で最大 [limit] 件返す
     * （Issue #131・Pigeon `LocationTrackingHostApi.getLocationPoints` の実体）。
     *
     * **呼び出し前提**: 呼び出し側（`LocationApiHandler`）が
     * [LocationTrackSchema.resolveDatabaseFile] の存在を確認済みであること。
     * このメソッド自身はファイルの存在確認を行わない（[readableDatabase] を呼んだ時点で
     * ファイルが無ければ `SQLiteOpenHelper` が新規作成してしまうため、「ファイル無し＝
     * 記録0件」という意味を保つ責務は呼び出し側にある。クラスdoc・
     * `LocationApiHandler.kt` 参照）。
     *
     * **呼び出しスレッド**: このメソッドはブロッキング I/O（`SQLiteDatabase#rawQuery`）を
     * 行う。メインスレッドから呼ばないこと（`LocationApiHandler.getLocationPoints` が
     * `Dispatchers.IO` 上で呼ぶ）。
     */
    fun selectPointsAfter(afterId: Long, limit: Int): List<LocationPointRow> {
        val rows = mutableListOf<LocationPointRow>()
        readableDatabase.rawQuery(
            "SELECT " +
                "${LocationTrackSchema.COLUMN_ID}, " +
                "${LocationTrackSchema.COLUMN_SESSION_ID}, " +
                "${LocationTrackSchema.COLUMN_ELAPSED_REALTIME_NANOS}, " +
                "${LocationTrackSchema.COLUMN_LATITUDE}, " +
                "${LocationTrackSchema.COLUMN_LONGITUDE}, " +
                "${LocationTrackSchema.COLUMN_ACCURACY_METERS}, " +
                "${LocationTrackSchema.COLUMN_POSSIBLE_MOCK_LOCATION} " +
                "FROM ${LocationTrackSchema.TABLE_POINT} " +
                "WHERE ${LocationTrackSchema.COLUMN_ID} > ? " +
                "ORDER BY ${LocationTrackSchema.COLUMN_ID} ASC " +
                "LIMIT ?",
            arrayOf(afterId.toString(), limit.toString()),
        ).use { cursor ->
            val idIndex = cursor.getColumnIndexOrThrow(LocationTrackSchema.COLUMN_ID)
            val sessionIdIndex = cursor.getColumnIndexOrThrow(LocationTrackSchema.COLUMN_SESSION_ID)
            val elapsedRealtimeNanosIndex =
                cursor.getColumnIndexOrThrow(LocationTrackSchema.COLUMN_ELAPSED_REALTIME_NANOS)
            val latitudeIndex = cursor.getColumnIndexOrThrow(LocationTrackSchema.COLUMN_LATITUDE)
            val longitudeIndex = cursor.getColumnIndexOrThrow(LocationTrackSchema.COLUMN_LONGITUDE)
            val accuracyMetersIndex =
                cursor.getColumnIndexOrThrow(LocationTrackSchema.COLUMN_ACCURACY_METERS)
            val possibleMockLocationIndex =
                cursor.getColumnIndexOrThrow(LocationTrackSchema.COLUMN_POSSIBLE_MOCK_LOCATION)
            while (cursor.moveToNext()) {
                rows.add(
                    LocationPointRow(
                        id = cursor.getLong(idIndex),
                        sessionId = cursor.getString(sessionIdIndex),
                        // Long のまま取り出す。64bit整数の丸めについては
                        // pigeons/location_api.dart の LocationPointMessage.elapsedRealtimeNanos
                        // ドキュメント参照（このカーソル読み取り自体もJSONを経由しない）。
                        elapsedRealtimeNanos = cursor.getLong(elapsedRealtimeNanosIndex),
                        latitude = cursor.getDouble(latitudeIndex),
                        longitude = cursor.getDouble(longitudeIndex),
                        accuracyMeters =
                            if (cursor.isNull(accuracyMetersIndex)) {
                                null
                            } else {
                                cursor.getFloat(accuracyMetersIndex)
                            },
                        possibleMockLocation = cursor.getInt(possibleMockLocationIndex) != 0,
                    ),
                )
            }
        }
        return rows
    }

    companion object {
        @Volatile
        private var instance: LocationTrackDatabaseHelper? = null

        /**
         * プロセス内で共有する唯一の [LocationTrackDatabaseHelper] を返す（Issue #131）。
         *
         * ## なぜ [onDestroy] 相当のクローズ処理を持たないのか（重要な設計決定）
         * 以前の実装は `LocationTrackingService.onDestroy()` がヘルパーの `close()` を
         * 呼んでいた（WALの自動チェックポイントを期待して）。しかしヘルパーを
         * サービスと Pigeon ハンドラで共有する今の設計では、**サービス停止時に閉じると
         * Pigeon ハンドラ側の読み取りが壊れる**（次回読み取り時に新しい接続を作り直す
         * 実装が必要になり、それ自体が「ポーリングごとに接続を開き直す」という
         * Issue #131 で明示的に不採用とした案と同じ問題——`-shm` の再初期化判定が
         * Kotlin 側の WAL インデックスを壊しうる——を Kotlin 側で再現してしまう）。
         *
         * そのため、**このインスタンスはアプリのプロセスが生存している間、開いたまま
         * にする**（明示的な `close()` は行わない）。プロセスは同じインスタンスを
         * 使い続けるため、開きっぱなしによる複数接続のリークは発生しない
         * （`getInstance` を何度呼んでも同じインスタンスが返る）。WAL は SQLite が
         * 既定で約1000ページごとに自動チェックポイントするため、`-wal` ファイルが
         * 無制限に肥大化することもない。プロセスが終了すればOSがファイル
         * ディスクリプタを回収する。
         *
         * この変更により、`docs/location-track-db.md` §3・§8.3 が前提としていた
         * 「サービス停止＝`close()`＝チェックポイント」という関係は成り立たなくなった
         * （ドキュメント側を実態に合わせて修正済み。取り出しは常に `-wal`/`-shm` を
         * 含む3ファイルまとめて行うこと）。
         */
        fun getInstance(context: Context): LocationTrackDatabaseHelper {
            return instance ?: synchronized(this) {
                instance ?: LocationTrackDatabaseHelper(context.applicationContext).also {
                    instance = it
                }
            }
        }
    }
}

/**
 * [LocationTrackDatabaseHelper.selectPointsAfter] が返す1行分（Issue #131）。
 *
 * Pigeon が生成する `LocationPointMessage`（`pigeons/location_api.dart`）とは
 * 意図的に別の型にしてある。DB層（本ファイル）が Pigeon の生成コードを知らなくて済むよう
 * にするため（変換は `LocationApiHandler.kt` の責務）。
 */
data class LocationPointRow(
    val id: Long,
    val sessionId: String,
    val elapsedRealtimeNanos: Long,
    val latitude: Double,
    val longitude: Double,
    val accuracyMeters: Float?,
    val possibleMockLocation: Boolean,
)
