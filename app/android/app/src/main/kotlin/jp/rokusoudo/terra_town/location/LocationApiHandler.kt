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
 * ## ⚠️ 権限チェックを呼び出し側（このクラス）で行う理由（重要・要確認事項の回避策）
 * [LocationTrackingService.onStartCommand] は権限が無い場合 `startForeground()` を
 * 呼ばずに `stopSelf()` する実装だが、**呼び出し側が既に `Context#startForegroundService()`
 * を呼んでしまっている**ため、システムは一定時間内の `startForeground()` 呼び出しを
 * 要求しており、権限が無い経路ではこれを満たせず
 * `ForegroundServiceDidNotStartInTimeException` でプロセスごと強制終了される
 * （2026-09-11・Pixel 7a・PR #128 レビューコメントで確認済み）。
 *
 * この修正コミット（`17dead3`。`Companion.start()` 側に権限チェックを移す）は
 * `feature/issue-123-kotlin-location-fgs` ブランチに存在するが、**PR #128 が main へ
 * マージされた時点のコミットには含まれていない**（2026-09-11・本 Issue の実装時に
 * 発覚。PR #128 の `mergedAt` より後のタイムスタンプでブランチに追加コミットが
 * 積まれており、再マージされていない。Issue #124 の PR 本文「要確認」に記録）。
 *
 * 本 Issue のスコープは [LocationTrackingService] 本体の挙動を変えないことだが、
 * **Pigeon 経由の起動要求に限っては**、[LocationTrackingService.start] を呼ぶ前に
 * ここで [LocationTrackingService.hasForegroundLocationPermission] を確認することで、
 * `Context#startForegroundService()` 自体を呼ばずに済み、上記のクラッシュを回避できる。
 * これは [LocationTrackingService] のコードを1行も変更せずに実現できる
 * （呼び出し側の判断を追加しているだけ）。
 *
 * **既存のデバッグ用 adb Intent**（`MainActivity.handleDebugLocationServiceIntent`）は
 * この権限確認を経由しないため、main 上では権限拒否状態のまま adb Intent 経由で
 * 起動すると今もクラッシュする。秘書セッションの実機確認手順は本ハンドラ（Pigeon の
 * `startTracking`）経由で行うこと。
 */
class LocationApiHandler(private val context: Context) : LocationTrackingHostApi {

    override fun startTracking(): TrackingStartResult {
        if (!LocationTrackingService.hasForegroundLocationPermission(context)) {
            // Context#startForegroundService() 自体を呼ばない。クラスdoc参照。
            return TrackingStartResult(outcome = TrackingStartOutcome.PERMISSION_DENIED)
        }
        LocationTrackingService.start(context)
        return TrackingStartResult(outcome = TrackingStartOutcome.STARTED)
    }

    override fun stopTracking() {
        LocationTrackingService.stop(context)
    }

    override fun getTrackingStatus(): TrackingStatus {
        val sessionId = LocationTrackingService.runningSessionId
        return TrackingStatus(isRunning = sessionId != null, sessionId = sessionId)
    }
}
