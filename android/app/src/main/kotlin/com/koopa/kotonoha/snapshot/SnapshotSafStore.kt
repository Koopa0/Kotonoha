package com.koopa.kotonoha.snapshot

import android.app.Activity
import android.content.Intent
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/// SAF create-document + [SnapshotSafWrite]. Cancel is an explicit
/// `cancelled`; a null stream or write throw is `failed`. A document URI
/// is never returned as success.
class SnapshotSafStore(
    private val activity: Activity,
    private val write: (openStream: () -> java.io.OutputStream?, bytes: ByteArray) -> String =
        SnapshotSafWrite::write,
) : MethodChannel.MethodCallHandler {
    private var pendingResult: MethodChannel.Result? = null
    private var pendingBytes: ByteArray? = null

    override fun onMethodCall(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        if (call.method != "save") {
            result.notImplemented()
            return
        }
        if (pendingResult != null) {
            result.success(SnapshotSafWrite.FAILED)
            return
        }
        val name = call.argument<String>("suggestedName")
        val bytes = call.argument<ByteArray>("bytes")
        if (name.isNullOrEmpty() || bytes == null) {
            result.success(SnapshotSafWrite.FAILED)
            return
        }
        pendingResult = result
        pendingBytes = bytes
        val intent =
            Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                type = "application/json"
                putExtra(Intent.EXTRA_TITLE, name)
            }
        activity.startActivityForResult(intent, REQUEST_CREATE)
    }

    fun onActivityResult(
        requestCode: Int,
        resultCode: Int,
        data: Intent?,
    ): Boolean {
        if (requestCode != REQUEST_CREATE) return false
        val reply = pendingResult
        val bytes = pendingBytes
        pendingResult = null
        pendingBytes = null
        if (reply == null) return true
        if (resultCode != Activity.RESULT_OK) {
            reply.success(CANCELLED)
            return true
        }
        val uri = data?.data
        if (uri == null || bytes == null) {
            reply.success(SnapshotSafWrite.FAILED)
            return true
        }
        val outcome =
            write(
                { activity.contentResolver.openOutputStream(uri) },
                bytes,
            )
        Handler(Looper.getMainLooper()).post { reply.success(outcome) }
        return true
    }

    companion object {
        const val CHANNEL = "kotonoha/snapshot_saf"
        const val CANCELLED = "cancelled"
        const val REQUEST_CREATE = 0x51AF
    }
}
