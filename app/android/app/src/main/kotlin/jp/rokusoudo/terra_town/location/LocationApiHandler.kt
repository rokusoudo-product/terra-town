package jp.rokusoudo.terra_town.location

import android.content.Context

/**
 * [LocationTrackingHostApi]（Pigeon 生成・`LocationApi.g.kt`）の実装（Issue #124・T049）。
 *
 * ## このハンドラの責務（位置データそのものは扱わない）
 * `pigeons/location_api.dart` のドキュメント参照。本ハンドラは位置記録
 * foreground service（[LocationTrackingService]・PR #128）の**起動・停止・状態問い合わせ**
 * だけを Dart 側へ橋渡しする。位置データ本体（緯度経度・時刻・精度）は
 * `location_track.sqlite` を直接読む `NativePositionProvider`（Dart側）の責務であり、
 * ここには一切現れない。
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
}
