package jp.rokusoudo.terra_town.location

import android.Manifest
import android.app.Notification
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.location.Location
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.util.Log
import androidx.core.app.NotificationChannelCompat
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.app.ServiceCompat
import androidx.core.content.ContextCompat
import com.google.android.gms.location.FusedLocationProviderClient
import com.google.android.gms.location.LocationCallback
import com.google.android.gms.location.LocationRequest
import com.google.android.gms.location.LocationResult
import com.google.android.gms.location.LocationServices
import java.util.UUID
import jp.rokusoudo.terra_town.MainActivity
import jp.rokusoudo.terra_town.R

/**
 * 位置記録 foreground service（Issue #123・T046〜T048）。
 *
 * 設計の要点（詳細は `docs/location-track-db.md`・`specs/001-mvp/plan.md` §7・§10）:
 * - fused location provider（[FusedLocationProviderClient]）で位置を取得する（T046）。
 * - サンプリングは距離ベース（[LocationSamplingPolicy.distanceThresholdMeters]）＋
 *   時間上限（[LocationSamplingPolicy.timeCapMillis]）。停止中は
 *   [LocationSamplingPolicy.priority] を [com.google.android.gms.location.Priority.PRIORITY_BALANCED_POWER_ACCURACY]
 *   にする等、常時高精度GPSを使わない構成にする（NFR-1）。
 * - 記録は Kotlin 側所有の [LocationTrackDatabaseHelper]（`location_track.sqlite`）に直接書き込む。
 *   Drift 管理下のゲーム状態DBには一切触れない（T047）。
 * - 時刻は `Location.getElapsedRealtimeNanos()`（単調時計）を使う（T048）。
 * - **フォアグラウンド位置のみ**。`ACCESS_BACKGROUND_LOCATION` は要求・使用しない
 *   （plan.md §10。while-in-use のフォアグラウンド権限のみで、アプリがバックグラウンドに
 *   回っても、または画面消灯しても、foreground service が動いている間は更新が届く。
 *   「フォアグラウンド位置」は「アプリの画面が前面にある」こととは異なる点に注意）。
 */
class LocationTrackingService : Service() {

    private val handler = Handler(Looper.getMainLooper())
    private lateinit var fusedLocationClient: FusedLocationProviderClient
    private lateinit var dbHelper: LocationTrackDatabaseHelper
    private lateinit var sessionId: String

    private val policy: LocationSamplingPolicy
        get() = LocationSamplingPolicy.currentPolicy

    private val locationCallback = object : LocationCallback() {
        override fun onLocationResult(result: LocationResult) {
            for (location in result.locations) {
                handleLocationFix(location, forcedByTimeCap = false)
            }
        }
    }

    private val timeCapRunnable = object : Runnable {
        override fun run() {
            // 距離しきい値に達していなくても、時間上限に達したら1回だけ現在地を取得して記録する
            // （Issue #10「距離フィルタ主体＋時間上限」の「時間上限」側）。
            requestSingleLocationForTimeCap()
            handler.postDelayed(this, policy.timeCapMillis)
        }
    }

    override fun onCreate() {
        super.onCreate()
        sessionId = UUID.randomUUID().toString()
        fusedLocationClient = LocationServices.getFusedLocationProviderClient(this)
        dbHelper = LocationTrackDatabaseHelper(this)
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (!hasForegroundLocationPermission(this)) {
            // 権限が付与されていない状態でサービスが起動しないことを保証する（受け入れ基準）。
            // startForeground() を一度も呼ばずに即座に停止するため、
            // ForegroundServiceDidNotStartInTimeException の対象にもならない。
            Log.w(TAG, "ACCESS_FINE_LOCATION/ACCESS_COARSE_LOCATION が無いため起動を中止します")
            stopSelf()
            return START_NOT_STICKY
        }

        ServiceCompat.startForeground(
            this,
            NOTIFICATION_ID,
            buildNotification(),
            ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION,
        )

        startLocationUpdates()
        handler.removeCallbacks(timeCapRunnable)
        handler.postDelayed(timeCapRunnable, policy.timeCapMillis)

        // START_NOT_STICKY: プロセスが kill された場合、システムに自動再起動させない。
        // 自動再起動しても、その時点でアプリに前面の Activity が無ければ（Android 11+ の
        // while-in-use 制限により）ACCESS_BACKGROUND_LOCATION なしでは位置更新が届かず、
        // 「通知は出るが記録が増えない」状態になるだけで意味が無い（docs/location-track-db.md §7）。
        // 再開はユーザー操作（T059）に委ねる。
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        handler.removeCallbacks(timeCapRunnable)
        fusedLocationClient.removeLocationUpdates(locationCallback)
        dbHelper.closeQuietly()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    @android.annotation.SuppressLint("MissingPermission") // hasForegroundLocationPermission()済みで呼ぶ
    private fun startLocationUpdates() {
        val currentPolicy = policy
        val request =
            LocationRequest.Builder(currentPolicy.priority, currentPolicy.intervalMillis)
                .setMinUpdateIntervalMillis(currentPolicy.minUpdateIntervalMillis)
                // OS 側の距離フィルタ。しきい値未満の移動ではコールバック自体が配送されないため、
                // 「停止中は省電力」が距離しきい値によっても担保される。
                .setMinUpdateDistanceMeters(currentPolicy.distanceThresholdMeters)
                .build()
        fusedLocationClient.requestLocationUpdates(request, locationCallback, Looper.getMainLooper())
    }

    @android.annotation.SuppressLint("MissingPermission")
    private fun requestSingleLocationForTimeCap() {
        if (!hasForegroundLocationPermission(this)) return
        val currentPolicy = policy
        fusedLocationClient.getCurrentLocation(currentPolicy.priority, null)
            .addOnSuccessListener { location ->
                if (location != null) {
                    handleLocationFix(location, forcedByTimeCap = true)
                }
            }
    }

    private fun handleLocationFix(location: Location, forcedByTimeCap: Boolean) {
        val currentPolicy = policy

        if (location.hasAccuracy() && location.accuracy > currentPolicy.maxAcceptedAccuracyMeters) {
            // 精度が粗すぎる fix は破棄する（LocationSamplingPolicy.maxAcceptedAccuracyMeters のdoc参照）。
            return
        }

        // fusedLocationClient.requestLocationUpdates 側の setMinUpdateDistanceMeters により、
        // 通常経路のコールバックはすでに距離しきい値を満たしている。時間上限による強制記録
        // （forcedByTimeCap）は距離を問わず記録する。
        Log.d(
            TAG,
            "位置記録: session=$sessionId forcedByTimeCap=$forcedByTimeCap " +
                "accuracy=${location.accuracy}m",
        )
        recordPoint(location)

        handler.removeCallbacks(timeCapRunnable)
        handler.postDelayed(timeCapRunnable, currentPolicy.timeCapMillis)
    }

    private fun recordPoint(location: Location) {
        val possibleMock =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                location.isMock
            } else {
                @Suppress("DEPRECATION")
                location.isFromMockProvider
            }
        dbHelper.insertPoint(
            sessionId = sessionId,
            // T048: 単調時計。Location 自身が持つ fix 時刻のelapsedRealtimeナノ秒版を使う
            // （コールバック配送時に SystemClock.elapsedRealtimeNanos() を取り直すと、
            // バッチ配送時にfixの実際の取得時刻とずれるため）。
            elapsedRealtimeNanos = location.elapsedRealtimeNanos,
            wallClockUnixMillis = location.time,
            latitude = location.latitude,
            longitude = location.longitude,
            accuracyMeters = if (location.hasAccuracy()) location.accuracy else null,
            possibleMockLocation = possibleMock,
        )
    }

    private fun buildNotification(): Notification {
        val contentIntent =
            PendingIntent.getActivity(
                this,
                0,
                Intent(this, MainActivity::class.java),
                PendingIntent.FLAG_IMMUTABLE,
            )
        // 常駐通知の文言・アイコン: DESIGN.md には foreground service 通知固有のトークン定義が
        // まだない（要確認・PR本文に記載）。暫定でアプリアイコンと中立的な文言を使う。
        return NotificationCompat.Builder(this, NOTIFICATION_CHANNEL_ID)
            .setContentTitle(getString(R.string.location_tracking_notification_title))
            .setContentText(getString(R.string.location_tracking_notification_text))
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentIntent(contentIntent)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .build()
    }

    private fun createNotificationChannel() {
        // minSdk=24 だが android.app.NotificationChannel は API 26 から。
        // NotificationChannelCompat/NotificationManagerCompat を使うと API 26 未満では
        // 何もせず安全にスキップされる（クラスの直接参照による NoClassDefFoundError を避ける）。
        val channel =
            NotificationChannelCompat.Builder(
                NOTIFICATION_CHANNEL_ID,
                NotificationManagerCompat.IMPORTANCE_LOW,
            )
                .setName(getString(R.string.location_tracking_notification_channel_name))
                .build()
        NotificationManagerCompat.from(this).createNotificationChannel(channel)
    }

    companion object {
        private const val TAG = "LocationTrackingService"
        private const val NOTIFICATION_CHANNEL_ID = "location_tracking"
        private const val NOTIFICATION_ID = 1001

        /**
         * フォアグラウンド位置権限（`ACCESS_FINE_LOCATION` または `ACCESS_COARSE_LOCATION`）が
         * 付与されているか。**`ACCESS_BACKGROUND_LOCATION` は確認しない**（要求もしない）。
         */
        fun hasForegroundLocationPermission(context: Context): Boolean {
            val fine =
                ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_FINE_LOCATION) ==
                    PackageManager.PERMISSION_GRANTED
            val coarse =
                ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_COARSE_LOCATION) ==
                    PackageManager.PERMISSION_GRANTED
            return fine || coarse
        }

        /**
         * サービスの起動リクエスト。権限が無い場合でも [Context.startForegroundService] 自体は
         * 呼べてしまうため、権限チェックは [LocationTrackingService.onStartCommand] 側で
         * 行い、そこで即座に `stopSelf()` する（受け入れ基準「権限なしで起動しない」）。
         */
        fun start(context: Context) {
            val intent = Intent(context, LocationTrackingService::class.java)
            ContextCompat.startForegroundService(context, intent)
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, LocationTrackingService::class.java))
        }
    }
}
