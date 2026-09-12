plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "jp.rokusoudo.terra_town"
    // Issue #142（T059）: `permission_handler_android`（14.1.0）が SDK 37 でのコンパイルを
    // 要求する（`flutter.compileSdkVersion` は本 Flutter バージョン時点で 36）。
    // Gradle のエラーメッセージが案内する対処（`compileSdk` を明示的に上書き）をそのまま採用。
    // 上位互換のため下位の `minSdk`/`targetSdk`（`flutter.minSdkVersion`/`flutter.targetSdkVersion`）
    // には影響しない。
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
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

    // Issue #108: com.uber:h3 の Android ネイティブ（jniLibs.srcDir 参照。下記
    // extractH3NativeLibs タスクのドキュメント参照）。
    sourceSets {
        getByName("main") {
            // AGP 9 の SourceSet API は Provider<Directory> を直接受け付けない
            // （"You cannot add Provider instances to the Android SourceSet API"）ため
            // .get().asFile で確定パスに変換して渡す。
            jniLibs.srcDir(layout.buildDirectory.dir("h3-jni-libs").get().asFile)
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

// Issue #108: com.uber:h3 の jar から Android 用ネイティブ（.so）だけを取り出すための
// 専用 configuration（implementation とは別に、jarファイル自体を zipTree で開くために
// 使う。implementation の依存グラフには影響しない）。
val h3Natives: Configuration by configurations.creating

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
    h3Natives("com.uber:h3:4.5.0")

    // Issue #108: このリポジトリ初めての Kotlin 単体テスト。JVM 単体テスト
    // （`app:testDebugUnitTest`）用。
    testImplementation("junit:junit:4.13.2")

    // Issue #108: v1→v2 スキーマ移行のテスト（`LocationTrackMigrationV1ToV2Test`）で、
    // Android の SQLiteOpenHelper ライフサイクル全体を動かす Robolectric は導入コストが
    // 重い・不安定になりやすいと判断し不採用（判断は PR 本文参照）。代わりに移行SQL自体
    // （ALTER TABLE・UPDATE・本番と同じ文字列定数）を xerial の sqlite-jdbc（JVM から
    // 直接使える純粋な SQLite 実装）に対して実行し検証する。テスト対象は移行SQL文
    // そのものであり、Android の SQLiteDatabase/SQLiteOpenHelper の実装や
    // onUpgrade の呼び出しタイミングそのものはテスト対象外（実機での検証は
    // 秘書セッションが上書きインストールで行う。PR本文参照）。
    testImplementation("org.xerial:sqlite-jdbc:3.53.4.0")
}

// Issue #108（重要・ビルド時にAPKへ実際に同梱されることを確認して判明した問題への対処）:
//
// com.uber:h3:4.5.0 のネイティブ（libh3-java.so）は、jar内で
// android-arm64/libh3-java.so・android-arm/libh3-java.so のようなパス
// （AndroidのABI名"arm64-v8a"・"armeabi-v7a"ではなく h3-java 独自の命名）に
// 置かれている。AGPの通常のリソースマージ（mergeDebugJavaResource等）は
// 拡張子 .so のファイル全般を「ネイティブライブラリはjniLibsパッケージング専用」
// として除外し、一方でネイティブライブラリのパッケージング（mergeDebugJniLibFolders等）は
// lib/<ABI>配下の.so（jar内）または jniLibs.srcDirs 配下 <ABI>配下の.so という
// Android ABI名のディレクトリ構造しか拾わない。結果として、
// implementation("com.uber:h3:4.5.0") を追加しただけでは
// .so がAPKに一切同梱されない（.dylib/.dll等 .so 以外の拡張子は
// 素通しでリソースとして残るため、unzip -l で見ると一見「動いているように」
// 誤読しやすい点に注意。実際に app-debug.apk を展開して確認し、
// android-arm64/libh3-java.so 等が失われていることを実測で発見した）。
//
// 対処: h3 jarから android-arm64・android-arm の.soだけを取り出し、
// Androidの正しいABI名（arm64-v8a・armeabi-v7a）のディレクトリへリネームして
// build/h3-jni-libs/ に展開し、android.sourceSets.main.jniLibs.srcDir
// （上記 android ブロック）でAGPに認識させる。android-x86_64 はそもそも
// jarに同梱されていないため対象外（H3HexIndexer のドキュメント参照）。
//
// 未検証（PR本文にも明記）: 本タスク自体はJVM単体テスト実行環境（linux-x64の
// ネイティブを直接ロードするJVMテスト）には関与しない。効果（実機でAndroidネイティブが
// 正しく読み込めるか）は秘書セッションの実機確認が必要。
//
// 【注記】このコメントは意図的に行コメント（//）にしている。Kotlinはブロックコメント
// （/* */）を入れ子として扱うため、本文中にファイルパスの例として "/*" を含む文字列
// （glob風の表記）を書くと、閉じ "*/" の数が対応せず後続のコード全体が静かにコメント
// として飲み込まれる事故が起きる（本Issueの実装中に実際に発生し、tasks.registerの
// 呼び出しが実行されないという症状で発覚した）。以後、このファイルでコード直前の
// 長文コメントは行コメントを使うこと。
val extractH3NativeLibs =
    tasks.register<Copy>("extractH3NativeLibs") {
        from({ h3Natives.map { file -> zipTree(file) } }) {
            include("android-arm64/libh3-java.so", "android-arm/libh3-java.so")
            eachFile {
                path =
                    when {
                        path.startsWith("android-arm64/") -> path.replaceFirst("android-arm64/", "arm64-v8a/")
                        path.startsWith("android-arm/") -> path.replaceFirst("android-arm/", "armeabi-v7a/")
                        else -> path
                    }
            }
            includeEmptyDirs = false
        }
        into(layout.buildDirectory.dir("h3-jni-libs"))
    }

// mergeXxxJniLibFolders（バリアントごとに生成される）が jniLibs.srcDirs を読み取る前に、
// 展開タスクを必ず完了させる。バリアント名を決め打ちにせず名前一致で広く拾う。
tasks.matching { it.name.contains("JniLibFolders") }.configureEach {
    dependsOn(extractH3NativeLibs)
}
