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
}
