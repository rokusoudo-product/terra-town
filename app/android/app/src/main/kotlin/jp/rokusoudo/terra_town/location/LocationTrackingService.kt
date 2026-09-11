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
 *   時間上限（[LocationSamplingPolicy.timeCapMillis]）。優先度（[LocationSamplingPolicy.priority]）の
 *   既定値・NFR-1「常時高精度GPSを使わない」との関係は [LocationSamplingPolicy] のdoc参照
 *   （2026-09-11 実機検証で `PRIORITY_BALANCED_POWER_ACCURACY` では精度ゲートと矛盾することが
 *   判明し、代表決定〔案A〕により `PRIORITY_HIGH_ACCURACY` に変更した）。
 * - 記録は Kotlin 側所有の [LocationTrackDatabaseHelper]（`location_track.sqlite`）に直接書き込む。
 *   Drift 管理下のゲーム状態DBには一切触れない（T047）。
 * - 時刻は `Location.getElapsedRealtimeNanos()`（単調時計）を使う（T048）。
 * - **フォアグラウンド位置のみ**。`ACCESS_BACKGROUND_LOCATION` は要求・使用しない
 *   （plan.md §10。while-in-use のフォアグラウンド権限のみで、アプリがバックグラウンドに
 *   回っても、または画面消灯しても、foreground service が動いている間は更新が届く。
 *   「フォアグラウンド位置」は「アプリの画面が前面にある」こととは異なる点に注意）。
 * - **権限確認は呼び出し側（[Companion.start]）が主。このクラス内（[onStartCommand]）の確認は
 *   二重の防御にすぎない**（2026-09-11 実機検証・PR #128 コメント「問題1」）。
 *   `Context.startForegroundService()` は一定時間内に `Service.startForeground()` を
 *   呼ぶことを Android から義務づけられており、権限が無いからと `startForeground()` を
 *   呼ばずに `stopSelf()` すると `ForegroundServiceDidNotStartInTimeException` で
 *   **プロセスごと強制終了される**。そのため権限の有無に関わらず必ず `startForeground()`
 *   （二重防御経路では例外を許容した上で）を先に呼んでから停止する。
 */
class LocationTrackingService : Service() {

    private val handler = Handler(Looper.getMainLooper())
    private lateinit var fusedLocationClient: FusedLocationProviderClient
    private lateinit var dbHelper: LocationTrackDatabaseHelper
    private lateinit var sessionId: String

    private val policy: LocationSamplingPolicy
        get() = LocationSamplingPolicy.currentPolicy

    // 【2026-09-11 実機検証（PR #128 コメント「問題3」）】精度ゲートで破棄した fix が
    // 何件あったかをログから追えるようにするためのカウンタ。T015（1時間の実歩行計測）で
    // 「精度不足で何件捨てられたか」を確認する材料にする。永続化はしない（デバッグ用）。
    private var discardedByAccuracyCount = 0

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
            // 【2026-09-11 実機検証（PR #128 コメント「問題1」）で判明した修正】
            // 本来は Companion.start() 側の確認で権限が無い限りここに来ないはずだが、
            // それでもここは「二重の防御」として残す（例: 将来の呼び出し経路の実装漏れに備える）。
            //
            // 以前の実装は startForeground() を一度も呼ばずに stopSelf() していたが、Android は
            // Context.startForegroundService() で起動されたサービスに「一定時間内に
            // startForeground() を呼ぶこと」を義務づけており、呼ばないまま停止すると
            // ForegroundServiceDidNotStartInTimeException でプロセスごと強制終了される
            // （「権限なしで起動を拒否したつもり」が実際は「アプリがクラッシュする」になっていた）。
            //
            // そのため、権限が無くても必ず startForeground() を先に呼んでから停止する。
            // Android 14 (API 34) 以降は FOREGROUND_SERVICE_TYPE_LOCATION の
            // startForeground() を位置権限なしで呼ぶと SecurityException になりうる
            // （要確認・実機未検証。ドキュメント上そう読める場合の防御）。その場合も
            // 例外を握りつぶし、**クラッシュしないことを最優先**にして stopSelf() する。
            Log.w(TAG, "ACCESS_FINE_LOCATION/ACCESS_COARSE_LOCATION が無いため起動を中止します（二重防御経路）")
            try {
                ServiceCompat.startForeground(
                    this,
                    NOTIFICATION_ID,
                    buildNotification(),
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION,
                )
            } catch (e: SecurityException) {
                Log.w(
                    TAG,
                    "権限なしでの startForeground() が SecurityException を投げました" +
                        "（Android 14+ で起こりうる想定内の例外・クラッシュを回避）",
                    e,
                )
            }
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
            // 【2026-09-11 実機検証で判明した問題3の修正】以前はここを黙って return しており、
            // 「記録が0件」の原因（優先度と精度ゲートの矛盾・PR #128 コメント「問題2」）の
            // 診断を難しくしていた。破棄した精度と累計破棄件数を必ずログに残す。
            discardedByAccuracyCount++
            Log.d(
                TAG,
                "位置破棄（精度不足）: session=$sessionId forcedByTimeCap=$forcedByTimeCap " +
                    "accuracy=${location.accuracy}m " +
                    "threshold=${currentPolicy.maxAcceptedAccuracyMeters}m " +
                    "discardedByAccuracyCount=$discardedByAccuracyCount",
            )
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
         * サービスの起動リクエスト。
         *
         * 【2026-09-11 実機検証（PR #128 コメント「問題1」）で修正】以前は権限チェックを
         * [LocationTrackingService.onStartCommand] 側だけで行っていた。しかし Android は
         * `Context.startForegroundService()` を呼んだ側に対し「一定時間内に
         * `Service.startForeground()` が呼ばれること」を保証する義務を課しており、
         * サービス側で権限が無いことを理由に `startForeground()` を呼ばず `stopSelf()` すると
         * `ForegroundServiceDidNotStartInTimeException` で **アプリのプロセスごと
         * 強制終了される**（実機で確認済み）。
         *
         * そのため、**権限確認はここ（呼び出し側）で行い、権限が無ければ
         * `startForegroundService()` 自体を呼ばない**ことを主経路にする。
         * [LocationTrackingService.onStartCommand] 側の確認は二重の防御として残すが、
         * そちらの経路でもクラッシュしない実装にしてある（同ファイルの `onStartCommand` 参照）。
         *
         * @return 起動を実際にリクエストしたら `true`。権限が無く起動をリクエストしなかった
         *   場合は `false`。**呼び出し側はこれを見て「起動しなかった」ことを把握できる**
         *   （権限要求UI・T059 が将来この戻り値を使ってダイアログ表示等に繋げる想定。
         *   T059 自体は本 Issue のスコープ外）。
         */
        fun start(context: Context): Boolean {
            if (!hasForegroundLocationPermission(context)) {
                Log.w(
                    TAG,
                    "ACCESS_FINE_LOCATION/ACCESS_COARSE_LOCATION が無いため " +
                        "startForegroundService() を呼ばずに起動を中止します",
                )
                return false
            }
            val intent = Intent(context, LocationTrackingService::class.java)
            ContextCompat.startForegroundService(context, intent)
            return true
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, LocationTrackingService::class.java))
        }
    }
}
