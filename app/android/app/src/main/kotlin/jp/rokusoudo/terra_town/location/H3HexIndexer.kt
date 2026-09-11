package jp.rokusoudo.terra_town.location

import com.uber.h3core.H3Core
import java.util.Locale

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
 * 実行できる。ただし [System.getProperty] で実行環境（JVM/Android）を見分ける必要は
 * ある（次項）。
 *
 * ## ⚠️ 実行環境によって H3Core の初期化方法を分けている（重要・実装中に発覚した問題）
 * h3-java には初期化方法が2つある:
 * - [H3Core.newInstance]（`H3CoreLoader.loadNatives()`）: ネイティブを**クラスパス
 *   リソース**（例: `/android-arm64/libh3-java.so`）として `getResourceAsStream` で
 *   読み出し、一時ファイルに書き出してから `System.load(絶対パス)` する方式。
 * - [H3Core.newSystemInstance]（`H3CoreLoader.loadSystemNatives()`）: OS標準の
 *   ライブラリ検索パスから `System.loadLibrary("h3-java")` で読み込む方式（＝
 *   「システムに既にインストール済みのネイティブを使う」用途のAPI）。
 *
 * 当初は Android でも [H3Core.newInstance] を使い、AGP の `jniLibs.srcDir`
 * （`build.gradle.kts` の `extractH3NativeLibs` タスク）で `.so` を APK に同梱すれば
 * 動くと想定していたが、これは誤りだった。**`jniLibs.srcDir` で同梱した `.so` は
 * `lib/<ABI>/`（Android標準の共有ライブラリ検索パス）に配置されるだけであり、
 * `getResourceAsStream("/android-arm64/libh3-java.so")` が探す「クラスパス上の
 * リソースパス」とは全く別物**（前者はAndroidの `PackageManager` が
 * `nativeLibraryDir` に展開する実ファイル、後者はAPK内のリソースエントリ）。
 * 実際、`unzip -l app-debug.apk` で確認すると `lib/arm64-v8a/libh3-java.so` は
 * 存在するが `android-arm64/libh3-java.so`（先頭スラッシュを除いたリソースパス）は
 * 存在しない（AGPが `.so` 拡張子のファイルを通常の Java リソースマージから常に
 * 除外し、`jniLibs` 側のパイプラインだけに回すため）。したがって Android で
 * [H3Core.newInstance] を呼ぶと必ず失敗する。
 *
 * **正しい組み合わせ**: `jniLibs.srcDir` で `.so` を `lib/<ABI>/` に同梱すれば、
 * Android が実行時に `ApplicationInfo.nativeLibraryDir` へ自動展開し、
 * `System.loadLibrary("h3-java")`（＝ [H3Core.newSystemInstance]）が標準の
 * JNI 検索パスでそれを見つけて読み込める。そのため本オブジェクトは、
 * 実行環境が Android の場合は [H3Core.newSystemInstance]、そうでない場合
 * （本リポジトリの JVM 単体テスト＝WSL・linux-x64）は従来どおり
 * [H3Core.newInstance]（クラスパスリソース経由。jar内の `linux-x64/libh3-java.so`
 * がそのまま使える）を呼ぶよう分岐する。Android かどうかの判定は
 * `H3CoreLoader.detectOs` と同じ方法（`System.getProperty("java.vendor")` に
 * "android" を含むか）を用いる。
 *
 * **⚠️ 実機未検証（PR本文にも明記）**: この分岐ロジック自体は h3-java の公開APIの
 * 意図（`newSystemInstance` のJavadoc「システムに既にインストール済みのネイティブを
 * 使う」）とAndroidの標準的なネイティブライブラリ展開の仕組みから導いた設計だが、
 * 実機で `System.loadLibrary("h3-java")` が実際に成功することは未確認。秘書セッションが
 * 実機で確認し、失敗する場合はカスタムローダー（`getResourceAsStream` の代わりに
 * `nativeLibraryDir` から直接 `System.load` する等）への切り替えを検討すること。
 */
object H3HexIndexer {
    /**
     * H3 の解像度。`tools/pack-builder/config.py` の `H3_RESOLUTION` と必ず一致させること
     * （クラスdoc参照）。
     */
    const val RESOLUTION: Int = 11

    /**
     * 実行環境が Android かどうか。`H3CoreLoader.detectOs`（h3-java内部実装）と
     * 同じ判定方法（`java.vendor` に "android" を含むか）を使う。
     */
    private val isAndroidRuntime: Boolean =
        System.getProperty("java.vendor")?.lowercase(Locale.ENGLISH)?.contains("android") == true

    private val h3: H3Core by lazy {
        try {
            // クラスdoc「実行環境によって H3Core の初期化方法を分けている」参照。
            if (isAndroidRuntime) H3Core.newSystemInstance() else H3Core.newInstance()
        } catch (e: Throwable) {
            // 判断に迷った点（PR本文にも記載）: ネイティブライブラリのロード失敗を
            // 呼び出し元（LocationTrackingService.recordPoint）で握りつぶして
            // 位置の記録自体をスキップする案もあったが、それは「開示が静かに壊れる」
            // という本プロジェクトが繰り返し避けてきた失敗様式（Issue #50・#58等）と
            // 同種になる。fail-loud（例外を投げてクラッシュさせる）を選んだ。
            // Throwable で受けているのは、newInstance() が投げる IOException（checked）と
            // newSystemInstance() が投げる UnsatisfiedLinkError（Error のサブクラス。
            // unchecked）の両方を同じ経路で包み直すため。
            // 実機（arm64/arm）での動作確認は本Issueのスコープ外（秘書セッションが
            // 実機確認を行う。PR本文「実機確認は未実施」参照）。
            throw IllegalStateException(
                "H3Core の初期化に失敗しました（isAndroidRuntime=$isAndroidRuntime）。" +
                    "Android実機の場合は build.gradle.kts の extractH3NativeLibs タスクで " +
                    "libh3-java.so が正しくAPKに同梱されているか確認してください。" +
                    "x86_64エミュレータの場合はcom.uber:h3:4.5.0にandroid-x86_64ネイティブが" +
                    "同梱されていないため常に失敗します（既知の制約）。",
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
