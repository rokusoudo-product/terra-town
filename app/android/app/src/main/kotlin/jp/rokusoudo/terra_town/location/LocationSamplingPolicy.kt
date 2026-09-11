package jp.rokusoudo.terra_town.location

import com.google.android.gms.location.Priority

/**
 * 位置記録のサンプリング方針（Issue #123・T046。Issue #10 代表回答「距離フィルタ主体
 * （例: 10〜20m移動ごと記録）＋時間上限」の実装値）。
 *
 * ## 距離しきい値は暫定値である（重要）
 * [distanceThresholdMeters] の初期値・根拠は [DEFAULT_DISTANCE_THRESHOLD_METERS] のドキュメント
 * コメントを参照。**実機計測（`specs/001-mvp/tasks.md` T015・R3：1時間の実歩行で電池と測位品質を
 * 計測）で確定するまでの暫定値であり、この値だけを見て「決定済み」と誤解しないこと。**
 *
 * ## 「設定値として変更できる」の実現方法
 * 本 Issue の時点では設定UIが無い（T059はスコープ外）ため、[currentPolicy] を差し替える
 * ことが「変更手段」にあたる。将来 T059 やバランス調整用の設定画面ができた場合は、
 * SharedPreferences 等から読み込んだ値で [currentPolicy] を上書きする実装を追加すればよい
 * （[LocationTrackingService] 側のロジックは [LocationSamplingPolicy] のフィールドしか参照しない
 * ため変更不要）。
 */
data class LocationSamplingPolicy(
    /**
     * 距離フィルタのしきい値（メートル）。この距離以上移動したときに記録する。
     *
     * 【暫定値・根拠】Issue #10 代表回答の範囲「10〜20m」の中央付近である 15m を採用。
     * - 10m 寄りにすると、市街地の GPS/Wi-Fi 測位ノイズ（水平精度が十数mになることが珍しくない）
     *   により、実際には動いていないのに移動したと誤検出しやすくなる。
     * - 20m 寄りにすると、`docs/terrain.md` のヘクス解像度（約50m）に対して記録の粒度が粗くなる。
     * 実機計測なしの机上の折衷であり、**T015（1時間の実歩行計測）で確定するまでの暫定値**。
     */
    val distanceThresholdMeters: Float = DEFAULT_DISTANCE_THRESHOLD_METERS,

    /**
     * 距離条件を満たさなくても強制的に記録する時間上限（ミリ秒）。
     * 停止中（省電力のため位置取得自体を間引いている間）でも、記録の空白が際限なく
     * 広がらないようにするための上限。Issue #10「距離フィルタ主体＋時間上限」のうち後者。
     * こちらも暫定値。T015 で見直す。
     */
    val timeCapMillis: Long = DEFAULT_TIME_CAP_MILLIS,

    /**
     * fused location provider への要求間隔（ミリ秒）。距離しきい値未満の移動では
     * コールバックが配送されないため、実質的にはこの間隔が「何秒ごとに移動量を確認するか」を決める。
     */
    val intervalMillis: Long = DEFAULT_INTERVAL_MILLIS,

    /** 上記 [intervalMillis] より短い間隔でのコールバックは受け取らない（電池保護の下限）。 */
    val minUpdateIntervalMillis: Long = DEFAULT_MIN_UPDATE_INTERVAL_MILLIS,

    /**
     * fused location provider の優先度。NFR-1「常時高精度GPSを使わない」に基づき、
     * 既定は [Priority.PRIORITY_BALANCED_POWER_ACCURACY]（GPS単独より低電力・精度は粗くなりうる）。
     * T015 で [Priority.PRIORITY_HIGH_ACCURACY] との比較実測を行うこと。
     */
    val priority: Int = DEFAULT_PRIORITY,

    /**
     * この精度（半径メートル）より粗い fix は記録しない。
     *
     * [DEFAULT_PRIORITY] が低電力優先のため、Wi-Fi/セル基地局測位由来の粗い fix
     * （accuracy が数十〜100m規模になることがある）が混じりうる。これを
     * [distanceThresholdMeters] に照らすと「精度誤差だけで移動したと誤判定される」おそれがあるため、
     * 精度が粗すぎる fix はそもそも記録しない。既定値は距離しきい値の2倍（暫定・机上の値）。
     */
    val maxAcceptedAccuracyMeters: Float = distanceThresholdMeters * 2f,
) {
    companion object {
        const val DEFAULT_DISTANCE_THRESHOLD_METERS: Float = 15f
        const val DEFAULT_TIME_CAP_MILLIS: Long = 5 * 60 * 1000L // 5分
        const val DEFAULT_INTERVAL_MILLIS: Long = 15 * 1000L // 15秒
        const val DEFAULT_MIN_UPDATE_INTERVAL_MILLIS: Long = 5 * 1000L // 5秒
        val DEFAULT_PRIORITY: Int = Priority.PRIORITY_BALANCED_POWER_ACCURACY

        /**
         * 現在有効な方針。[LocationTrackingService] はこの値だけを参照する。
         * 差し替えは呼び出し側（将来の設定画面・テスト）の責務。
         */
        @Volatile
        var currentPolicy: LocationSamplingPolicy = LocationSamplingPolicy()
    }
}
