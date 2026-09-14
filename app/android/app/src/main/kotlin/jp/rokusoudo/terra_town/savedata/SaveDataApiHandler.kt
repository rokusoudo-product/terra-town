package jp.rokusoudo.terra_town.savedata

import android.app.Activity
import android.content.Intent
import android.net.Uri
import kotlin.coroutines.Continuation
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext

/**
 * [SaveDataFileHostApi]（Pigeon 生成・`SaveDataApi.g.kt`）の実装（Issue #180・T105）。
 *
 * `pigeons/save_data_api.dart` のドキュメント参照。SAF（Storage Access Framework）の
 * `ACTION_CREATE_DOCUMENT`／`ACTION_OPEN_DOCUMENT` を `startActivityForResult` で起動し、
 * `MainActivity.onActivityResult`（[onActivityResult]）が結果を受け取るまで
 * `suspendCancellableCoroutine` で Dart 側の呼び出しを一時停止する。
 *
 * ## 同時に1件までしか扱わない
 * 保存・読み込みのどちらも、ユーザーがピッカーを閉じるまで Dart 側は次の呼び出しを
 * 行わない設計（設定画面は確認ダイアログ等で二重起動を防ぐ）ため、本ハンドラは
 * リクエストごとに1つの継続（[saveUriContinuation]／[openUriContinuation]）しか
 * 保持しない。万一2件目の呼び出しが先に来た場合は、実装バグとして気づけるよう
 * [IllegalStateException] で fail-loud にする（`LocationTrackDatabaseHelper.
 * selectPointsAfter` の NULL `hex_id` と同じ方針）。
 */
class SaveDataApiHandler(private val activity: Activity) : SaveDataFileHostApi {

    /** [ACTION_CREATE_DOCUMENT] の結果待ちの継続。ピッカー表示中のみ非null。 */
    private var saveUriContinuation: Continuation<Uri?>? = null

    /** [ACTION_OPEN_DOCUMENT] の結果待ちの継続。ピッカー表示中のみ非null。 */
    private var openUriContinuation: Continuation<Uri?>? = null

    override suspend fun saveTextFile(suggestedFileName: String, contents: String): Boolean {
        val uri = suspendCancellableCoroutine<Uri?> { continuation ->
            if (saveUriContinuation != null) {
                continuation.resumeWithException(
                    IllegalStateException("saveTextFile が多重に呼び出されました（実装バグ）。"),
                )
                return@suspendCancellableCoroutine
            }
            val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                type = "application/json"
                putExtra(Intent.EXTRA_TITLE, suggestedFileName)
            }
            saveUriContinuation = continuation
            try {
                activity.startActivityForResult(intent, REQUEST_CODE_CREATE_DOCUMENT)
            } catch (error: Throwable) {
                saveUriContinuation = null
                continuation.resumeWithException(error)
            }
        }
        if (uri == null) {
            return false // ユーザーがピッカーをキャンセルした。
        }
        withContext(Dispatchers.IO) {
            activity.contentResolver.openOutputStream(uri, "wt")?.use { output ->
                output.write(contents.toByteArray(Charsets.UTF_8))
            } ?: throw IllegalStateException(
                "選択された保存先を開けませんでした（ContentResolver.openOutputStream が null）。",
            )
        }
        return true
    }

    override suspend fun openTextFile(): String? {
        val uri = suspendCancellableCoroutine<Uri?> { continuation ->
            if (openUriContinuation != null) {
                continuation.resumeWithException(
                    IllegalStateException("openTextFile が多重に呼び出されました（実装バグ）。"),
                )
                return@suspendCancellableCoroutine
            }
            val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                // OS 側の MIME フィルタに頼らない（`pigeons/save_data_api.dart`
                // `openTextFile` ドキュメント参照）。
                type = "*/*"
            }
            openUriContinuation = continuation
            try {
                activity.startActivityForResult(intent, REQUEST_CODE_OPEN_DOCUMENT)
            } catch (error: Throwable) {
                openUriContinuation = null
                continuation.resumeWithException(error)
            }
        }
        if (uri == null) {
            return null // ユーザーがピッカーをキャンセルした。
        }
        return withContext(Dispatchers.IO) {
            activity.contentResolver.openInputStream(uri)?.use { input ->
                input.readBytes().toString(Charsets.UTF_8)
            } ?: throw IllegalStateException(
                "選択されたファイルを開けませんでした（ContentResolver.openInputStream が null）。",
            )
        }
    }

    /**
     * `MainActivity.onActivityResult` から呼ばれる（Issue #180）。
     *
     * [Activity.RESULT_OK] かつ `data?.data` が非nullの場合のみ Uri を渡し、それ以外
     * （キャンセル・異常終了）は `null` を渡す（[saveTextFile]/[openTextFile] の
     * ドキュメント「キャンセルした場合」参照）。
     */
    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        when (requestCode) {
            REQUEST_CODE_CREATE_DOCUMENT -> {
                val continuation = saveUriContinuation ?: return
                saveUriContinuation = null
                val uri = if (resultCode == Activity.RESULT_OK) data?.data else null
                continuation.resume(uri)
            }
            REQUEST_CODE_OPEN_DOCUMENT -> {
                val continuation = openUriContinuation ?: return
                openUriContinuation = null
                val uri = if (resultCode == Activity.RESULT_OK) data?.data else null
                continuation.resume(uri)
            }
        }
    }

    companion object {
        // Flutter エンジン自体・他プラグインのリクエストコードと衝突しない値
        // （権限リクエストは `onRequestPermissionsResult` 経由でありこことは別系統。
        // `permission_handler` 等が使う `onActivityResult` のリクエストコードとの
        // 衝突を避けるため、通常使われない大きめの値を採る）。
        private const val REQUEST_CODE_CREATE_DOCUMENT = 20441
        private const val REQUEST_CODE_OPEN_DOCUMENT = 20442
    }
}
