package com.koopa.kotonoha.snapshot

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.OutputStream
import java.util.concurrent.Executor
import java.util.concurrent.Executors

/// SAF create-document + [SnapshotSafWrite]. Cancel is an explicit
/// `cancelled`; a null stream or write throw is `failed`. A document URI
/// is never returned as success.
class SnapshotSafStore private constructor(
    private val launchPicker: (Intent, Int) -> Unit,
    private val openStream: (Uri) -> OutputStream?,
    private val write: (openStream: () -> OutputStream?, bytes: ByteArray) -> String,
    private val postToMain: (Runnable) -> Unit,
    private val ioExecutor: Executor,
) : MethodChannel.MethodCallHandler {
    private var pendingResult: SnapshotSafReply? = null
    private var pendingBytes: ByteArray? = null

    override fun onMethodCall(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        if (call.method != "save") {
            result.notImplemented()
            return
        }
        val name = call.argument<String>("suggestedName")
        val bytes = call.argument<ByteArray>("bytes")
        requestSave(name, bytes, ChannelReply(result))
    }

    internal fun requestSave(
        name: String?,
        bytes: ByteArray?,
        reply: SnapshotSafReply,
    ) {
        if (pendingResult != null) {
            reply.success(SnapshotSafWrite.FAILED)
            return
        }
        if (name.isNullOrEmpty() || bytes == null) {
            reply.success(SnapshotSafWrite.FAILED)
            return
        }
        pendingResult = reply
        pendingBytes = bytes
        val intent =
            Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                type = "application/json"
                putExtra(Intent.EXTRA_TITLE, name)
            }
        try {
            launchPicker(intent, REQUEST_CREATE)
        } catch (_: Exception) {
            val failed = pendingResult
            clearPending()
            failed?.success(SnapshotSafWrite.FAILED)
        }
    }

    fun onActivityResult(
        requestCode: Int,
        resultCode: Int,
        data: Intent?,
    ): Boolean {
        if (requestCode != REQUEST_CREATE) return false
        val reply = pendingResult
        val bytes = pendingBytes
        if (reply == null) return true
        if (resultCode != Activity.RESULT_OK) {
            clearPending()
            reply.success(CANCELLED)
            return true
        }
        val uri = data?.data
        if (uri == null || bytes == null) {
            clearPending()
            reply.success(SnapshotSafWrite.FAILED)
            return true
        }
        ioExecutor.execute {
            val outcome =
                write(
                    { openStream(uri) },
                    bytes,
                )
            postToMain {
                if (pendingResult !== reply) return@postToMain
                clearPending()
                reply.success(outcome)
            }
        }
        return true
    }

    private fun clearPending() {
        pendingResult = null
        pendingBytes = null
    }

    internal interface SnapshotSafReply {
        fun success(value: String)
    }

    private class ChannelReply(
        private val result: MethodChannel.Result,
    ) : SnapshotSafReply {
        override fun success(value: String) {
            result.success(value)
        }
    }

    companion object {
        const val CHANNEL = "kotonoha/snapshot_saf"
        const val CANCELLED = "cancelled"
        const val REQUEST_CREATE = 0x51AF

        fun attach(activity: Activity): SnapshotSafStore =
            SnapshotSafStore(
                launchPicker = { intent, code ->
                    @Suppress("DEPRECATION")
                    activity.startActivityForResult(intent, code)
                },
                openStream = { uri -> activity.contentResolver.openOutputStream(uri) },
                write = SnapshotSafWrite::write,
                postToMain = { runnable -> Handler(Looper.getMainLooper()).post(runnable) },
                ioExecutor = Executors.newSingleThreadExecutor(),
            )

        internal fun forTest(
            launchPicker: (Intent, Int) -> Unit,
            openStream: (Uri) -> OutputStream?,
            write: (openStream: () -> OutputStream?, bytes: ByteArray) -> String =
                SnapshotSafWrite::write,
            postToMain: (Runnable) -> Unit = { it.run() },
            ioExecutor: Executor = Executors.newSingleThreadExecutor(),
        ): SnapshotSafStore =
            SnapshotSafStore(
                launchPicker = launchPicker,
                openStream = openStream,
                write = write,
                postToMain = postToMain,
                ioExecutor = ioExecutor,
            )
    }
}
