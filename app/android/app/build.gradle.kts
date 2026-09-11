plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "jp.rokusoudo.terra_town"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    buildFeatures {
        // Issue #123: MainActivity のデバッグ専用フック（実機検証用。T059で削除予定）が
        // BuildConfig.DEBUG を参照するため有効化する（AGP 8+ の既定は false）。
        buildConfig = true
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "jp.rokusoudo.terra_town"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Issue #123 (T046): 位置記録 foreground service の fused location provider。
    implementation("com.google.android.gms:play-services-location:21.3.0")

    // Issue #123 (T046): Android 14 (API 34) の foregroundServiceType="location" 要件を
    // 満たすため ServiceCompat.startForeground(..., FOREGROUND_SERVICE_TYPE_LOCATION) を使う。
    // このオーバーロードは Flutter embedding が推移的に持ち込む androidx.core より新しいバージョンを
    // 要求するため明示的に依存を足す。
    implementation("androidx.core:core-ktx:1.13.1")

    // Issue #131: Pigeon 28.1.0 は @async の HostApi メソッドを Kotlin の suspend fun として
    // 生成し、生成コード（LocationApi.g.kt）自身が kotlinx.coroutines
    // （CoroutineScope(Dispatchers.Main).launch・suspendCancellableCoroutine）を import する。
    // Flutter embedding は coroutines を推移的に持ち込まないため明示的に依存を足す。
    // -android アーティファクトは -core を含み、Dispatchers.Main（Android の Looper 実装）を提供する。
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.9.0")

    // Issue #108: 緯度経度 → H3 インデックス変換を Kotlin 側（本 jar）に寄せる。
    // Maven Central 2026-08-14 リリース。jar に android-arm64/android-arm/linux-x64 等の
    // ネイティブ（libh3-java.so）を同梱しているが、**android-x86_64 は同梱されていない**
    // （2026-09-11 時点でjar内容を実測確認済み）。x86_64 エミュレータでは
    // `H3HexIndexer` の初期化（H3Core.newInstance()）が失敗する制約がある
    // （`H3HexIndexer` のドキュメント参照）。
    implementation("com.uber:h3:4.5.0")

    // Issue #108: このリポジトリ初めての Kotlin 単体テスト。JVM 単体テスト
    // （`app:testDebugUnitTest`）用。
    testImplementation("junit:junit:4.13.2")

    // Issue #108: v1→v2 スキーマ移行のテスト（`LocationTrackMigrationV1ToV2Test`）で、
    // Android の SQLiteOpenHelper ライフサイクル全体を動かす Robolectric は導入コストが
    // 重い・不安定になりやすいと判断し不採用（判断は PR 本文参照）。代わりに移行SQL自体
    // （ALTER TABLE・UPDATE・本番と同じ文字列定数）を xerial の sqlite-jdbc（JVM から
    // 直接使える純粋な SQLite 実装）に対して実行し検証する。**テスト対象は移行SQL文
    // そのものであり、Android の `SQLiteDatabase`/`SQLiteOpenHelper` の実装や
    // `onUpgrade` の呼び出しタイミングそのものはテスト対象外**（実機での検証は
    // 秘書セッションが上書きインストールで行う。PR本文参照）。
    testImplementation("org.xerial:sqlite-jdbc:3.53.4.0")
}
