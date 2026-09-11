package jp.rokusoudo.terra_town.location

import com.uber.h3core.H3Core
import java.io.IOException

/**
 * 緯度経度 → H3 インデックス変換を行う Kotlin 側の実装（Issue #108）。
 *
 * ## なぜ Kotlin 側に寄せたか（Issue #107・#108 の経緯）
 * Issue #107（2026-09-10 代表決定）では「位置トラッキング基盤（Issue #10）と
 * GPS偽装対策（Issue #9）が `future` で着手できない間の暫定として、緯度経度→H3の
 * 変換は Dart 側（`h3_flutter`）で行う」とされていた。`specs/001-mvp/plan.md` §2 は
 * 最終形として「位置記録の保存を Kotlin 側からローカルDBへ直接書き込む形で実装し、
 * Dart は読むだけにする」と定めており、位置記録 foreground service（T046〜T048・
 * `LocationTrackingService`）の実装に伴い、本 Issue（#108）でこの変換ロジックを
 * Kotlin 側へ寄せた。呼び出し元は [LocationTrackingService.recordPoint] であり、
 * 記録対象として精度・距離のゲートを通過した位置だけを変換する（ゲート判定自体は
 * 変更しない）。
 *
 * ## `com.uber:h3:4.5.0`（h3-java）を採用した理由
 * - Maven Central（2026-08-14 リリース）。`tools/pack-builder` が使う `h3-py` と
 *   同じ 4.5.0（H3 v4 世代のAPI）であり、`docs/terrain.md` §4.2 の「生成側と実行側で
 *   同じバージョン世代を使う」方針と一致する。
 * - **重要な制約**: jar に同梱されるネイティブライブラリ（`libh3-java.so`）は
 *   `android-arm64`・`android-arm`・`linux-x64` 等のみで、**`android-x86_64` は
 *   同梱されていない**（2026-09-11 に jar の中身を実測確認済み）。そのため
 *   **x86_64 エミュレータでは [locate] の初期化が失敗する**。実機（arm64/arm）と
 *   本リポジトリの JVM 単体テスト実行環境（WSL・linux-x64）では問題にならない。
 *
 * ## 解像度は11で固定（`docs/terrain.md` §3.1・§4.2 代表決定・2026-09-08 Issue #38）
 * `tools/pack-builder/config.py` の `H3_RESOLUTION` と必ず一致させること。解像度が
 * 食い違うと、同じ緯度経度でも生成側と実行側で異なる `hex_id` になり、パックの
 * `hex_terrain` を引けなくなる（開示が静かに機能しなくなる）。本ファイルの単体テスト
 * （`H3HexIndexerTest`・`h3-py` 生成のフィクスチャとの全点突き合わせ）が、この不一致を
 * 機械的に検知する実質的なチェックになっている。
 *
 * ## `H3Core` はプロセス内で1回だけロードし共有する
 * h3-java 4.5.0 のソースコード（`H3Core.java` クラスdoc）に
 * "This class is thread safe and can be used as a singleton." と明記されている。
 * `H3Core.newInstance()` はダイナミックライブラリのロード等のコストを伴うため、
 * 呼び出しごとではなくプロセス全体で1回だけ生成して使い回す（`by lazy` は
 * デフォルトで `LazyThreadSafetyMode.SYNCHRONIZED` であり、複数スレッドから
 * 同時に初回アクセスされても2重初期化にならない）。
 *
 * ## Android フレームワークに依存しない（重要・JVM単体テストが動く理由）
 * 本ファイルは `android.util.Log` 等の Android フレームワーククラスを一切参照しない。
 * AGP の JVM 単体テスト（`testDebugUnitTest`）はモック版の `android.jar`
 * （未モックのメソッドは呼ぶと例外を投げる）をクラスパスに使うため、Android
 * フレームワーク API を呼ぶコードは単体テストで実行できない。[H3HexIndexer] を
 * 純粋な Kotlin + h3-java だけに保つことで、`H3HexIndexerTest`
 * （`app/android/app/src/test/kotlin/`）がエミュレータ・実機なしに JVM 上でそのまま
 * 実行できる。
 */
object H3HexIndexer {
    /**
     * H3 の解像度。`tools/pack-builder/config.py` の `H3_RESOLUTION` と必ず一致させること
     * （クラスdoc参照）。
     */
    const val RESOLUTION: Int = 11

    private val h3: H3Core by lazy {
        try {
            H3Core.newInstance()
        } catch (e: IOException) {
            // 判断に迷った点（PR本文にも記載）: ネイティブライブラリのロード失敗を
            // 呼び出し元（LocationTrackingService.recordPoint）で握りつぶして
            // 位置の記録自体をスキップする案もあったが、それは「開示が静かに壊れる」
            // という本プロジェクトが繰り返し避けてきた失敗様式（Issue #50・#58等）と
            // 同種になる。fail-loud（例外を投げてクラッシュさせる）を選んだ。
            // 実機（arm64/arm）での動作確認は本Issueのスコープ外（秘書セッションが
            // 実機確認を行う。PR本文「実機確認は未実施」参照）。
            throw IllegalStateException(
                "H3Core の初期化に失敗しました（H3Core.newInstance()）。" +
                    "既知の原因: com.uber:h3:4.5.0 の jar には android-x86_64 ネイティブ " +
                    "（libh3-java.so）が同梱されていないため、x86_64 エミュレータでは " +
                    "常に失敗します（android-arm64/android-arm の実機では発生しない想定）。",
                e,
            )
        }
    }

    /**
     * [latitude]・[longitude] が属する H3 セルのインデックス（解像度 [RESOLUTION]）を返す。
     *
     * `tools/pack-builder` の `h3.latlng_to_cell(lat, lon, 11)` → `h3.str_to_int(...)` と
     * 同一の値を返すことを [H3HexIndexerTest] で検証している。
     */
    fun locate(latitude: Double, longitude: Double): Long = h3.latLngToCell(latitude, longitude, RESOLUTION)
}
