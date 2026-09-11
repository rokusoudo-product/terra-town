package jp.rokusoudo.terra_town.location

import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import java.io.File
import java.sql.Connection
import java.sql.DriverManager

/**
 * `location_track.sqlite` のマイグレーション（[LocationTrackMigrations]・Issue #108・
 * Issue #126）を検証するテスト。
 *
 * ## なぜ Robolectric ではなく xerial の sqlite-jdbc を使うか（判断・PR本文にも記載）
 * このリポジトリには Kotlin の単体テストがまだ無く（Issue #108 が最初）、
 * `SQLiteOpenHelper.onUpgrade` のライフサイクル全体（`PRAGMA user_version` を経由した
 * 呼び出しタイミング・`getDatabaseLocked` が用意する外側のトランザクション等）を
 * JVM 単体テストで動かすには Robolectric のような Android フレームワークの
 * シャドウ実装が必要になる。初めての Kotlin テスト導入と同時に Robolectric まで
 * 導入するのは重く、初回導入時に不安定になりやすいと判断し不採用にした。
 *
 * 代わりに、**移行ロジックそのもの**（[LocationTrackMigrations] の SQL 文
 * ——ALTER TABLE・バックフィルの UPDATE・schema_version 更新——)を、JVM から直接
 * 使える純粋な SQLite 実装（xerial `sqlite-jdbc`）に対して実行し、結果を検証する。
 * 本番コード（[LocationTrackDatabaseHelper.onUpgrade]・`applyMigrationStep`）と
 * **文字どおり同じ SQL 定数**を実行するため、SQL 自体の正しさは検証できる。
 *
 * **この設計の限界**: 本テストが検証するのは SQL 文自体の効果であり、Android の
 * `SQLiteOpenHelper`/`SQLiteDatabase` の実装や `onUpgrade` が実際に正しいタイミングで
 * 呼ばれるかどうかは検証しない（`SQLiteOpenHelper` のバージョン機構そのものは
 * Android フレームワークの既存動作であり、本 Issue で変更していない）。実機の
 * 既存DB（schema_version 1 または 2）への上書きインストールでの確認は代表・秘書
 * セッションが行う（`docs/location-track-db.md` §8 参照。PR本文に「実機確認は
 * 未実施」と明記）。
 *
 * ## Issue #126 での拡張（段階的な移行ループ）
 * [LocationTrackDatabaseHelper.onUpgrade] は schema_version 3 の追加に伴い、
 * `oldVersion` から `newVersion` まで1バージョンずつ順に適用するループに
 * 変更された（v1の端末が一気に v3 へ更新される場合に備える）。本テストは
 * v1→v2（既存）に加え、**v1→v3**（複数ステップを一括で適用）・**v2→v3**
 * （1ステップのみ）の両方を検証する。
 */
class LocationTrackMigrationTest {
    private lateinit var dbFile: File
    private lateinit var connection: Connection

    /**
     * v1 時点の `location_point` DDL のスナップショット（[LocationTrackSchema] は
     * 既に v3 の DDL——`hex_id`・`step_count` 列を含む——に更新済みのため、v1 の状態を
     * 再現するにはここに当時の定義をそのまま書き写す必要がある）。
     */
    private val createTablePointV1 =
        """
        CREATE TABLE ${LocationTrackSchema.TABLE_POINT} (
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
        """.trimIndent()

    /**
     * v2 時点の `location_point` DDL のスナップショット（Issue #108 で `hex_id` を
     * 追加した後、Issue #126 で `step_count` を追加する前の状態。[LocationTrackSchema]
     * は既に v3 のDDLに更新済みのため、v1のときと同じ理由でここに書き写す）。
     */
    private val createTablePointV2 =
        """
        CREATE TABLE ${LocationTrackSchema.TABLE_POINT} (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            session_id TEXT NOT NULL,
            elapsed_realtime_nanos INTEGER NOT NULL,
            wall_clock_unix_millis INTEGER NOT NULL,
            latitude REAL NOT NULL,
            longitude REAL NOT NULL,
            accuracy_meters REAL,
            possible_mock_location INTEGER NOT NULL DEFAULT 0,
            inserted_at_unix_millis INTEGER NOT NULL,
            hex_id INTEGER
        )
        """.trimIndent()

    private val createTableMetaV1 =
        "CREATE TABLE ${LocationTrackSchema.TABLE_META} (key TEXT PRIMARY KEY, value TEXT NOT NULL)"

    @After
    fun tearDown() {
        connection.close()
        dbFile.delete()
    }

    /** schema_version [startVersion]（1または2）のDBを一時ファイルに作る。 */
    private fun setUpDatabaseAtVersion(startVersion: Int) {
        dbFile = File.createTempFile("location_track_v$startVersion", ".sqlite")
        connection = DriverManager.getConnection("jdbc:sqlite:${dbFile.absolutePath}")
        val createTablePoint = if (startVersion == 1) createTablePointV1 else createTablePointV2
        connection.createStatement().use { statement ->
            statement.execute(createTableMetaV1)
            statement.execute(createTablePoint)
            statement.execute(
                "INSERT INTO ${LocationTrackSchema.TABLE_META} (key, value) VALUES " +
                    "('${LocationTrackSchema.META_KEY_SCHEMA_VERSION}', '$startVersion')",
            )
        }
    }

    private fun insertPointV1(id: Long, lat: Double, lon: Double) {
        connection.prepareStatement(
            "INSERT INTO ${LocationTrackSchema.TABLE_POINT} " +
                "(id, session_id, elapsed_realtime_nanos, wall_clock_unix_millis, " +
                "latitude, longitude, possible_mock_location, inserted_at_unix_millis) " +
                "VALUES (?, 'session-v1', 1000, 2000, ?, ?, 0, 3000)",
        ).use { statement ->
            statement.setLong(1, id)
            statement.setDouble(2, lat)
            statement.setDouble(3, lon)
            statement.executeUpdate()
        }
    }

    private fun insertPointV2(id: Long, lat: Double, lon: Double, hexId: Long) {
        connection.prepareStatement(
            "INSERT INTO ${LocationTrackSchema.TABLE_POINT} " +
                "(id, session_id, elapsed_realtime_nanos, wall_clock_unix_millis, " +
                "latitude, longitude, possible_mock_location, inserted_at_unix_millis, hex_id) " +
                "VALUES (?, 'session-v2', 1000, 2000, ?, ?, 0, 3000, ?)",
        ).use { statement ->
            statement.setLong(1, id)
            statement.setDouble(2, lat)
            statement.setDouble(3, lon)
            statement.setLong(4, hexId)
            statement.executeUpdate()
        }
    }

    /** v1→v2 の1ステップ分（[LocationTrackDatabaseHelper.applyMigrationStep] のfromVersion=1相当）。 */
    private fun runV1ToV2Step() {
        connection.createStatement().use { statement ->
            statement.execute(LocationTrackMigrations.V1_TO_V2_ADD_HEX_ID_COLUMN)
        }

        val points = mutableListOf<Triple<Long, Double, Double>>()
        connection.createStatement().use { statement ->
            statement.executeQuery(LocationTrackMigrations.V1_TO_V2_SELECT_ALL_POINTS).use { resultSet ->
                while (resultSet.next()) {
                    points.add(
                        Triple(
                            resultSet.getLong(LocationTrackSchema.COLUMN_ID),
                            resultSet.getDouble(LocationTrackSchema.COLUMN_LATITUDE),
                            resultSet.getDouble(LocationTrackSchema.COLUMN_LONGITUDE),
                        ),
                    )
                }
            }
        }

        connection.prepareStatement(LocationTrackMigrations.V1_TO_V2_UPDATE_HEX_ID).use { statement ->
            for ((id, lat, lon) in points) {
                val hexId = H3HexIndexer.locate(lat, lon)
                statement.setLong(1, hexId)
                statement.setLong(2, id)
                statement.executeUpdate()
            }
        }
    }

    /** v2→v3 の1ステップ分（[LocationTrackDatabaseHelper.applyMigrationStep] のfromVersion=2相当）。 */
    private fun runV2ToV3Step() {
        connection.createStatement().use { statement ->
            statement.execute(LocationTrackMigrations.V2_TO_V3_ADD_STEP_COUNT_COLUMN)
        }
    }

    private fun updateSchemaVersion(newVersion: Int) {
        connection.prepareStatement(LocationTrackMigrations.UPDATE_SCHEMA_VERSION).use { statement ->
            statement.setString(1, newVersion.toString())
            statement.setString(2, LocationTrackSchema.META_KEY_SCHEMA_VERSION)
            statement.executeUpdate()
        }
    }

    /**
     * [LocationTrackDatabaseHelper.onUpgrade] の段階的ループを、同じ SQL 定数を
     * 使って JDBC 上で再現する（`fromVersion in oldVersion until newVersion` の
     * ループ→最後に1回だけ schema_version 更新、という順序も一致させる）。
     */
    private fun runMigration(oldVersion: Int, newVersion: Int) {
        connection.autoCommit = false
        try {
            for (fromVersion in oldVersion until newVersion) {
                when (fromVersion) {
                    1 -> runV1ToV2Step()
                    2 -> runV2ToV3Step()
                    else -> error("テストが未対応の fromVersion=$fromVersion です")
                }
            }
            updateSchemaVersion(newVersion)
            connection.commit()
        } catch (e: Exception) {
            connection.rollback()
            throw e
        } finally {
            connection.autoCommit = true
        }
    }

    @Test
    fun `v1のDBをv2へ移行すると全行にhex_idが入りschema_versionが2になる`() {
        setUpDatabaseAtVersion(1)
        // フィクスチャ（h3-pyとの一致テストと同じ元データ）から数点使う。
        // 「移行後のhex_idがh3-pyの値と一致する」ことまでこのテストで確認することで、
        // H3HexIndexerTest と本テストが同じ正（フィクスチャ）を共有し、解像度の
        // 食い違いがあれば両方のテストが失敗する、という関係を保つ。
        val fixtureRows = HexFixture.load().take(3)
        fixtureRows.forEachIndexed { index, row ->
            insertPointV1(id = (index + 1).toLong(), lat = row.lat, lon = row.lon)
        }

        runMigration(oldVersion = 1, newVersion = 2)

        connection.createStatement().use { statement ->
            statement.executeQuery(
                "SELECT ${LocationTrackSchema.COLUMN_ID}, ${LocationTrackSchema.COLUMN_HEX_ID} " +
                    "FROM ${LocationTrackSchema.TABLE_POINT} ORDER BY ${LocationTrackSchema.COLUMN_ID}",
            ).use { resultSet ->
                var count = 0
                while (resultSet.next()) {
                    val id = resultSet.getLong(LocationTrackSchema.COLUMN_ID)
                    val hexId = resultSet.getLong(LocationTrackSchema.COLUMN_HEX_ID)
                    assertEquals(false, resultSet.wasNull())
                    val expected = fixtureRows[(id - 1).toInt()].hexId
                    assertEquals(
                        "id=$id の hex_id が h3-py の値と一致しません",
                        expected,
                        hexId,
                    )
                    count++
                }
                assertEquals(3, count)
            }
        }
        assertSchemaVersion(2)
    }

    @Test
    fun `既存行が0件でもv1からv2への移行は成功しschema_versionだけ更新される`() {
        setUpDatabaseAtVersion(1)

        runMigration(oldVersion = 1, newVersion = 2)

        assertSchemaVersion(2)
    }

    @Test
    fun `v1のDBをv3へ一気に移行すると、hex_idがバックフィルされ、step_countはNULLのまま、schema_versionが3になる`() {
        setUpDatabaseAtVersion(1)
        val fixtureRows = HexFixture.load().take(3)
        fixtureRows.forEachIndexed { index, row ->
            insertPointV1(id = (index + 1).toLong(), lat = row.lat, lon = row.lon)
        }

        runMigration(oldVersion = 1, newVersion = 3)

        connection.createStatement().use { statement ->
            statement.executeQuery(
                "SELECT ${LocationTrackSchema.COLUMN_ID}, ${LocationTrackSchema.COLUMN_HEX_ID}, " +
                    "${LocationTrackSchema.COLUMN_STEP_COUNT} " +
                    "FROM ${LocationTrackSchema.TABLE_POINT} ORDER BY ${LocationTrackSchema.COLUMN_ID}",
            ).use { resultSet ->
                var count = 0
                while (resultSet.next()) {
                    val id = resultSet.getLong(LocationTrackSchema.COLUMN_ID)
                    // hex_id は v1→v2 のステップでバックフィルされているはず。
                    val hexId = resultSet.getLong(LocationTrackSchema.COLUMN_HEX_ID)
                    assertEquals(false, resultSet.wasNull())
                    val expected = fixtureRows[(id - 1).toInt()].hexId
                    assertEquals("id=$id の hex_id が h3-py の値と一致しません", expected, hexId)

                    // step_count は Issue #126 の方針どおりバックフィルされず NULL のまま。
                    resultSet.getLong(LocationTrackSchema.COLUMN_STEP_COUNT)
                    assertTrue(
                        "id=$id の step_count はバックフィルせずNULLのままのはず",
                        resultSet.wasNull(),
                    )
                    count++
                }
                assertEquals(3, count)
            }
        }
        assertSchemaVersion(3)
    }

    @Test
    fun `v2のDBをv3へ移行すると、既存のhex_idは保持されたままstep_count列が追加されNULLになりschema_versionが3になる`() {
        setUpDatabaseAtVersion(2)
        insertPointV2(id = 1, lat = 35.681236, lon = 139.767125, hexId = 999L)

        runMigration(oldVersion = 2, newVersion = 3)

        connection.createStatement().use { statement ->
            statement.executeQuery(
                "SELECT ${LocationTrackSchema.COLUMN_HEX_ID}, ${LocationTrackSchema.COLUMN_STEP_COUNT} " +
                    "FROM ${LocationTrackSchema.TABLE_POINT} WHERE ${LocationTrackSchema.COLUMN_ID} = 1",
            ).use { resultSet ->
                assertEquals(true, resultSet.next())
                // 既存のhex_id（v2時点で既にバックフィル済み）は変更されない。
                assertEquals(999L, resultSet.getLong(LocationTrackSchema.COLUMN_HEX_ID))
                resultSet.getLong(LocationTrackSchema.COLUMN_STEP_COUNT)
                assertTrue("v2→v3移行後の既存行のstep_countはNULLのはず", resultSet.wasNull())
            }
        }
        assertSchemaVersion(3)
    }

    @Test
    fun `既存行が0件でもv2からv3への移行は成功しschema_versionだけ更新される`() {
        setUpDatabaseAtVersion(2)

        runMigration(oldVersion = 2, newVersion = 3)

        assertSchemaVersion(3)
    }

    private fun assertSchemaVersion(expected: Int) {
        connection.createStatement().use { statement ->
            statement.executeQuery(
                "SELECT ${LocationTrackSchema.META_COLUMN_VALUE} FROM ${LocationTrackSchema.TABLE_META} " +
                    "WHERE ${LocationTrackSchema.META_COLUMN_KEY} = " +
                    "'${LocationTrackSchema.META_KEY_SCHEMA_VERSION}'",
            ).use { resultSet ->
                assertEquals(true, resultSet.next())
                assertEquals(expected.toString(), resultSet.getString(LocationTrackSchema.META_COLUMN_VALUE))
            }
        }
    }
}
