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
     * fused location provider の優先度。
     *
     * ## 【2026-09-11 実機検証で判明した設計の矛盾・代表決定（案A）による変更】
     * 当初は NFR-1「常時高精度GPSを使わない」に基づき既定を
     * [Priority.PRIORITY_BALANCED_POWER_ACCURACY] にしていたが、実機（Pixel 7a）で
     * **記録が1件も行われない**不具合が見つかった（PR #128 コメント「問題2」）。
     *
     * 原因は優先度と精度ゲート（[maxAcceptedAccuracyMeters]、既定30m）の**両立不可能な組み合わせ**:
     * - Android 公式ドキュメントは `PRIORITY_BALANCED_POWER_ACCURACY` の精度を
     *   「ブロック単位（約100m）」としており、GPS を使わず Wi-Fi/基地局測位に留まることが多い。
     * - 実機の `dumpsys location` でも fused=100.0m・network=56.3m・gps(屋内)=156.9m と、
     *   **全プロバイダが精度ゲート（30m）を超えていた**。
     * - `docs/terrain.md` のヘクス解像度が約50mであるため、約100mの精度では開示判定にすら使えない。
     *
     * **代表決定（2026-09-11・案A）**: [Priority.PRIORITY_HIGH_ACCURACY] に変更する。
     * 理由: このサービスは常駐サービスではなく、**アプリから明示的に起動したとき
     * （`LocationTrackingService.Companion.start`）だけ動作し、`START_NOT_STICKY` で
     * システムによる自動再起動もしない**。したがって「常時」高精度GPSを使うわけではなく、
     * plan.md §7 の**意図**（アプリを使っていないときに電池を消費し続けない）は守られる、
     * というのが代表の判断である。**この PR では `plan.md` §7 の文言自体は変更しない**
     * （改定案は PR 本文に記載し、代表承認を得てから別 PR で反映する。plan.md はゲート②承認済み）。
     *
     * [distanceThresholdMeters]（15m）・[maxAcceptedAccuracyMeters]（30m）は据え置く。
     * `PRIORITY_HIGH_ACCURACY` なら屋外で通常 5〜15m 程度の精度になることが期待され、
     * 30mゲートとも両立するはず**だが、これはドキュメント・一般的傾向からの推測であり、
     * 実測していない**。実際の値は T015（1時間の実歩行）で確認し、必要ならしきい値・優先度の
     * 組み合わせを見直す。それでも電池消費が許容できない場合は、歩行検出による
     * 優先度切り替え（案B）に進む段階的な進め方とする（PR #128 本文参照）。
     */
    val priority: Int = DEFAULT_PRIORITY,

    /**
     * この精度（半径メートル）より粗い fix は記録しない。
     *
     * 既定値は距離しきい値の2倍（暫定・机上の値）。[DEFAULT_PRIORITY] を
     * `PRIORITY_HIGH_ACCURACY` に変更した後も、この30mというゲート自体は変えていない
     * （2026-09-11 代表決定・上記 [priority] のdoc参照）。高精度GPSであれば屋外で
     * 通常このしきい値内に収まると見込むが、**これは推測であり T015 の実測で確定する**。
     * 屋内・トンネル等では依然として超えることがあり、その場合は意図通り破棄される
     * （破棄時はログに精度と累計破棄件数を出す。`LocationTrackingService.handleLocationFix`
     * 参照・PR #128 コメント「問題3」）。
     */
    val maxAcceptedAccuracyMeters: Float = distanceThresholdMeters * 2f,
) {
    companion object {
        const val DEFAULT_DISTANCE_THRESHOLD_METERS: Float = 15f
        const val DEFAULT_TIME_CAP_MILLIS: Long = 5 * 60 * 1000L // 5分
        const val DEFAULT_INTERVAL_MILLIS: Long = 15 * 1000L // 15秒
        const val DEFAULT_MIN_UPDATE_INTERVAL_MILLIS: Long = 5 * 1000L // 5秒

        // 2026-09-11 代表決定（案A）: PRIORITY_BALANCED_POWER_ACCURACY → PRIORITY_HIGH_ACCURACY。
        // 理由・矛盾の詳細は [priority] のdocコメント参照。
        val DEFAULT_PRIORITY: Int = Priority.PRIORITY_HIGH_ACCURACY

        /**
         * 現在有効な方針。[LocationTrackingService] はこの値だけを参照する。
         * 差し替えは呼び出し側（将来の設定画面・テスト）の責務。
         */
        @Volatile
        var currentPolicy: LocationSamplingPolicy = LocationSamplingPolicy()
    }
}
