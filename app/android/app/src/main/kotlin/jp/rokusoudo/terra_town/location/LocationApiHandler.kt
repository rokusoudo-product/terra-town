package jp.rokusoudo.terra_town.location

import android.content.Context
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * [LocationTrackingHostApi]（Pigeon 生成・`LocationApi.g.kt`）の実装（Issue #124・T049。
 * Issue #131 で位置データの読み取りもこのハンドラの責務に加わった）。
 *
 * ## このハンドラの責務
 * `pigeons/location_api.dart` のドキュメント参照。位置記録
 * foreground service（[LocationTrackingService]・PR #128）の**起動・停止・状態問い合わせ**
 * に加え、**位置データそのもの**（[getLocationPoints]）も Dart 側へ橋渡しする
 * （Issue #131・2026-09-11 代表決定。以前は Dart が `location_track.sqlite` を
 * 直接読む設計だったが、同一プロセス内に Kotlin/Dart 2つの SQLite が存在する構成が
 * 実機不具合を起こしたため撤回した。`LocationTrackDatabase.kt` クラスdoc参照）。
 *
 * ## 権限が無い場合の扱い
 * 権限確認は [LocationTrackingService.Companion.start] 側で行われ、権限が無ければ
 * `Context#startForegroundService()` 自体を呼ばずに `false` を返す（2026-09-11・PR #130で
 * main に反映済み。詳細は [LocationTrackingService] クラスdoc・`Companion.start` docコメント
 * 参照）。本ハンドラはその戻り値をそのまま Pigeon の [TrackingStartOutcome] に変換するだけで、
 * 自前の権限チェックは行わない。
 */
class LocationApiHandler(private val context: Context) : LocationTrackingHostApi {

    override fun startTracking(): TrackingStartResult {
        val started = LocationTrackingService.start(context)
        val outcome =
            if (started) TrackingStartOutcome.STARTED else TrackingStartOutcome.PERMISSION_DENIED
        return TrackingStartResult(outcome = outcome)
    }

    override fun stopTracking() {
        LocationTrackingService.stop(context)
    }

    override fun getTrackingStatus(): TrackingStatus {
        val sessionId = LocationTrackingService.runningSessionId
        return TrackingStatus(isRunning = sessionId != null, sessionId = sessionId)
    }

    /**
     * `location_point` の新規行を Dart 側へ渡す（Issue #131）。
     *
     * Pigeon の生成コード（`LocationApi.g.kt`）は `@async` メソッドを Kotlin の
     * `suspend fun` として生成し、`CoroutineScope(Dispatchers.Main).launch` から呼ぶ
     * （＝この関数自体はメインスレッドの呼び出しから始まる）。そのため
     * [withContext] で `Dispatchers.IO` に切り替えてから SQLite を読む
     * （メインスレッドでブロッキング I/O を行わない、という Issue #131 の要件）。
     * `withContext` はブロック完了後に呼び出し元のディスパッチャ（`Dispatchers.Main`）に
     * 自動的に戻るため、戻り値を返した時点で Pigeon 生成コードの `reply.reply(...)` も
     * メインスレッドで呼ばれる（既存の同期メソッドと同じスレッドで応答する）。
     *
     * ファイルがまだ存在しない（記録が1件も無い）場合は
     * [LocationTrackDatabaseHelper.getInstance] にすら触れず空リストを返す。
     * 先に `LocationTrackDatabaseHelper`（`SQLiteOpenHelper`）を経由してしまうと、
     * `readableDatabase` の呼び出しが `onCreate` を発火させて空のファイルを
     * 新規作成してしまい、「ファイル無し＝記録0件」という意味が壊れるため
     * （`pigeons/location_api.dart` の `getLocationPoints` ドキュメント参照）。
     */
    override suspend fun getLocationPoints(afterId: Long, limit: Long): List<LocationPointMessage> =
        withContext(Dispatchers.IO) {
            val file = LocationTrackSchema.resolveDatabaseFile(context)
            if (!file.exists()) {
                return@withContext emptyList()
            }
            LocationTrackDatabaseHelper.getInstance(context)
                .selectPointsAfter(afterId, limit.toInt())
                .map { row ->
                    LocationPointMessage(
                        id = row.id,
                        sessionId = row.sessionId,
                        elapsedRealtimeNanos = row.elapsedRealtimeNanos,
                        latitude = row.latitude,
                        longitude = row.longitude,
                        accuracyMeters = row.accuracyMeters?.toDouble(),
                        possibleMockLocation = row.possibleMockLocation,
                    )
                }
        }
}
