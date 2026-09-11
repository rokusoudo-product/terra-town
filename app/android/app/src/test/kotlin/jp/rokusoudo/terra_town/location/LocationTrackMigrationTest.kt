package jp.rokusoudo.terra_town.location

import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Before
import org.junit.Test
import java.io.File
import java.sql.Connection
import java.sql.DriverManager

/**
 * `location_track.sqlite` の v1→v2 マイグレーション（[LocationTrackMigrations]・
 * Issue #108）を検証するテスト。
 *
 * ## なぜ Robolectric ではなく xerial の sqlite-jdbc を使うか（判断・PR本文にも記載）
 * このリポジトリには Kotlin の単体テストがまだ無く（本 Issue が最初）、
 * `SQLiteOpenHelper.onUpgrade` のライフサイクル全体（`PRAGMA user_version` を経由した
 * 呼び出しタイミング・`getDatabaseLocked` が用意する外側のトランザクション等）を
 * JVM 単体テストで動かすには Robolectric のような Android フレームワークの
 * シャドウ実装が必要になる。初めての Kotlin テスト導入と同時に Robolectric まで
 * 導入するのは重く、初回導入時に不安定になりやすいと判断し不採用にした。
 *
 * 代わりに、**移行ロジックそのもの**（[LocationTrackMigrations] の3つの SQL 文
 * ——ALTER TABLE・バックフィルの UPDATE・schema_version 更新——)を、JVM から直接
 * 使える純粋な SQLite 実装（xerial `sqlite-jdbc`）に対して実行し、結果を検証する。
 * 本番コード（[LocationTrackDatabaseHelper.onUpgrade]）と**文字どおり同じ SQL 定数**
 * を実行するため、SQL 自体の正しさは検証できる。
 *
 * **この設計の限界**: 本テストが検証するのは SQL 文自体の効果であり、Android の
 * `SQLiteOpenHelper`/`SQLiteDatabase` の実装や `onUpgrade` が実際に正しいタイミングで
 * 呼ばれるかどうかは検証しない（`SQLiteOpenHelper` のバージョン機構そのものは
 * Android フレームワークの既存動作であり、本 Issue で変更していない）。実機の
 * 既存DB（schema_version 1）への上書きインストールでの確認は代表・秘書セッションが
 * 行う（`docs/location-track-db.md` §8 参照。PR本文に「実機確認は未実施」と明記）。
 */
class LocationTrackMigrationV1ToV2Test {
    private lateinit var dbFile: File
    private lateinit var connection: Connection

    /**
     * v1 時点の `location_point` DDL のスナップショット（[LocationTrackSchema] は
     * 既に v2 の DDL——`hex_id` 列を含む——に更新済みのため、v1 の状態を再現するには
     * ここに当時の定義をそのまま書き写す必要がある）。
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

    private val createTableMetaV1 =
        "CREATE TABLE ${LocationTrackSchema.TABLE_META} (key TEXT PRIMARY KEY, value TEXT NOT NULL)"

    @Before
    fun setUp() {
        dbFile = File.createTempFile("location_track_v1", ".sqlite")
        connection = DriverManager.getConnection("jdbc:sqlite:${dbFile.absolutePath}")
        connection.createStatement().use { statement ->
            statement.execute(createTableMetaV1)
            statement.execute(createTablePointV1)
            statement.execute(
                "INSERT INTO ${LocationTrackSchema.TABLE_META} (key, value) VALUES " +
                    "('${LocationTrackSchema.META_KEY_SCHEMA_VERSION}', '1')",
            )
        }
    }

    @After
    fun tearDown() {
        connection.close()
        dbFile.delete()
    }

    private fun insertV1Point(id: Long, lat: Double, lon: Double) {
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

    /**
     * [LocationTrackDatabaseHelper.onUpgrade] のv1→v2ロジックを、同じ SQL 定数
     * （[LocationTrackMigrations]）を使って JDBC 上で再現する。
     */
    private fun runV1ToV2Migration() {
        connection.autoCommit = false
        try {
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

            connection.prepareStatement(LocationTrackMigrations.V1_TO_V2_UPDATE_SCHEMA_VERSION).use { statement ->
                statement.setString(1, "2")
                statement.setString(2, LocationTrackSchema.META_KEY_SCHEMA_VERSION)
                statement.executeUpdate()
            }

            connection.commit()
        } catch (e: Exception) {
            connection.rollback()
            throw e
        } finally {
            connection.autoCommit = true
        }
    }

    @Test
    fun `v1のDBを移行すると全行にhex_idが入りschema_versionが2になる`() {
        // フィクスチャ（h3-pyとの一致テストと同じ元データ）から数点使う。
        // 「移行後のhex_idがh3-pyの値と一致する」ことまでこのテストで確認することで、
        // H3HexIndexerTest と本テストが同じ正（フィクスチャ）を共有し、解像度の
        // 食い違いがあれば両方のテストが失敗する、という関係を保つ。
        val fixtureRows = HexFixture.load().take(3)
        fixtureRows.forEachIndexed { index, row ->
            insertV1Point(id = (index + 1).toLong(), lat = row.lat, lon = row.lon)
        }

        runV1ToV2Migration()

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

        connection.createStatement().use { statement ->
            statement.executeQuery(
                "SELECT ${LocationTrackSchema.META_COLUMN_VALUE} FROM ${LocationTrackSchema.TABLE_META} " +
                    "WHERE ${LocationTrackSchema.META_COLUMN_KEY} = " +
                    "'${LocationTrackSchema.META_KEY_SCHEMA_VERSION}'",
            ).use { resultSet ->
                assertEquals(true, resultSet.next())
                assertEquals("2", resultSet.getString(LocationTrackSchema.META_COLUMN_VALUE))
            }
        }
    }

    @Test
    fun `既存行が0件でも移行は成功しschema_versionだけ更新される`() {
        runV1ToV2Migration()

        connection.createStatement().use { statement ->
            statement.executeQuery(
                "SELECT ${LocationTrackSchema.META_COLUMN_VALUE} FROM ${LocationTrackSchema.TABLE_META} " +
                    "WHERE ${LocationTrackSchema.META_COLUMN_KEY} = " +
                    "'${LocationTrackSchema.META_KEY_SCHEMA_VERSION}'",
            ).use { resultSet ->
                assertEquals(true, resultSet.next())
                assertEquals("2", resultSet.getString(LocationTrackSchema.META_COLUMN_VALUE))
            }
        }
    }
}
