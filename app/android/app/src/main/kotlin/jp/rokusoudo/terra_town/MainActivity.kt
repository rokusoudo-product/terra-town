package jp.rokusoudo.terra_town

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import jp.rokusoudo.terra_town.location.LocationApiHandler
import jp.rokusoudo.terra_town.location.LocationTrackingHostApi

class MainActivity : FlutterActivity() {
    /**
     * Pigeon の [LocationTrackingHostApi]（`pigeons/location_api.dart`・Issue #124・T049）を
     * Dart 側の呼び出しに応答できるよう登録する。位置記録サービスの起動・停止・状態問い合わせに
     * 加え、位置データ本体（`getLocationPoints`）も本チャンネル経由で渡す
     * （Issue #131・`LocationApiHandler` docs参照）。
     *
     * 【2026-09-12・Issue #142（T059）で削除】以前は本メソッドの前段に、実機で
     * サービスを手動起動するための `adb shell am start` デバッグ Intent ハンドラ
     * （`handleDebugLocationServiceIntent`）があった。起動・停止・権限リクエストの
     * 製品UI（`app/lib/features/permissions/tracking_control_button.dart`）が
     * 実装されたことで、そのフックはコメントで予告されていたとおり不要になったため
     * 削除した（Kotlin 側の実装・Pigeon API 自体は変更していない）。
     */
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        LocationTrackingHostApi.setUp(
            flutterEngine.dartExecutor.binaryMessenger,
            LocationApiHandler(applicationContext),
        )
    }
}
