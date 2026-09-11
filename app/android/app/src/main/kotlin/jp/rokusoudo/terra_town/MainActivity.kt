package jp.rokusoudo.terra_town

import android.content.Intent
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import jp.rokusoudo.terra_town.location.LocationTrackingService

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handleDebugLocationServiceIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleDebugLocationServiceIntent(intent)
    }

    /**
     * 【Issue #123・実機検証のための一時的なフック。T059（権限リクエストUI・位置記録の
     * 開始/停止ボタン）実装時に削除すること】
     *
     * Pigeon/`NativePositionProvider`（Issue #124）も、開始/停止のUI（T059）もまだ
     * 存在しないため、代表が実機でサービスを起動する経路が無い。デバッグビルドに限り、
     * `adb shell am start` の boolean extra でサービスの開始/停止を指示できるようにする。
     *
     * 起動（権限付与後）:
     * ```
     * adb shell pm grant jp.rokusoudo.terra_town android.permission.ACCESS_FINE_LOCATION
     * adb shell pm grant jp.rokusoudo.terra_town android.permission.POST_NOTIFICATIONS
     * adb shell am start -n jp.rokusoudo.terra_town/.MainActivity \
     *   --ez terra_town.debug.startLocationService true
     * ```
     * 停止:
     * ```
     * adb shell am start -n jp.rokusoudo.terra_town/.MainActivity \
     *   --ez terra_town.debug.stopLocationService true
     * ```
     * 詳細・確認手順は `docs/location-track-db.md` を参照。
     */
    private fun handleDebugLocationServiceIntent(intent: Intent?) {
        if (!BuildConfig.DEBUG || intent == null) return
        if (intent.getBooleanExtra("terra_town.debug.startLocationService", false)) {
            LocationTrackingService.start(this)
        }
        if (intent.getBooleanExtra("terra_town.debug.stopLocationService", false)) {
            LocationTrackingService.stop(this)
        }
    }
}
