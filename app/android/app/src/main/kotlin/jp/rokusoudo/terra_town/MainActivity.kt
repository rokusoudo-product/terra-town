package jp.rokusoudo.terra_town

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import jp.rokusoudo.terra_town.location.LocationApiHandler
import jp.rokusoudo.terra_town.location.LocationTrackingHostApi
import jp.rokusoudo.terra_town.savedata.SaveDataApiHandler
import jp.rokusoudo.terra_town.savedata.SaveDataFileHostApi

class MainActivity : FlutterActivity() {
    /**
     * [SaveDataApiHandler]（Issue #180・T105）は `startActivityForResult`/
     * [onActivityResult] という Activity のライフサイクルに紐づく API を使うため、
     * `configureFlutterEngine` を跨いでインスタンスを保持しておく必要がある
     * （`onActivityResult` からの委譲先として参照する）。
     */
    private var saveDataApiHandler: SaveDataApiHandler? = null

    /**
     * Pigeon の [LocationTrackingHostApi]（`pigeons/location_api.dart`・Issue #124・T049）を
     * Dart 側の呼び出しに応答できるよう登録する。位置記録サービスの起動・停止・状態問い合わせに
     * 加え、位置データ本体（`getLocationPoints`）・最大行id（`getMaxLocationPointId`・
     * Issue #180）も本チャンネル経由で渡す（Issue #131・`LocationApiHandler` docs参照）。
     *
     * 【2026-09-12・Issue #142（T059）で削除】以前は本メソッドの前段に、実機で
     * サービスを手動起動するための `adb shell am start` デバッグ Intent ハンドラ
     * （`handleDebugLocationServiceIntent`）があった。起動・停止・権限リクエストの
     * 製品UI（`app/lib/features/permissions/tracking_control_button.dart`）が
     * 実装されたことで、そのフックはコメントで予告されていたとおり不要になったため
     * 削除した（Kotlin 側の実装・Pigeon API 自体は変更していない）。
     *
     * 【2026-09-15・Issue #180 で追加】[SaveDataFileHostApi]（セーブデータの
     * エクスポート/インポートで使う SAF ファイル受け渡し）も同じ Flutter engine に
     * 登録する。`SaveDataApiHandler` は `Activity`（`this`）を保持する点が
     * `LocationApiHandler`（`applicationContext` のみ）と異なる
     * （`pigeons/save_data_api.dart` ドキュメント参照）。
     */
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        LocationTrackingHostApi.setUp(
            flutterEngine.dartExecutor.binaryMessenger,
            LocationApiHandler(applicationContext),
        )
        val handler = SaveDataApiHandler(this)
        saveDataApiHandler = handler
        SaveDataFileHostApi.setUp(flutterEngine.dartExecutor.binaryMessenger, handler)
    }

    /**
     * SAF のピッカー（`ACTION_CREATE_DOCUMENT`／`ACTION_OPEN_DOCUMENT`）の結果を
     * [SaveDataApiHandler] へ橋渡しする（Issue #180）。
     */
    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        saveDataApiHandler?.onActivityResult(requestCode, resultCode, data)
    }
}
