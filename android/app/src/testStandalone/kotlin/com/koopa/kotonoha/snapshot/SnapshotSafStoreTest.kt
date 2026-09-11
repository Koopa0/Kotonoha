package com.koopa.kotonoha.snapshot

import android.app.Activity
import android.content.Intent
import android.net.Uri
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.ByteArrayOutputStream
import java.io.IOException
import java.io.OutputStream
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executor
import java.util.concurrent.TimeUnit

/// Official [SnapshotSafStore] routing compiled against the host
/// Activity / Channel stubs in `testStandalone/stubs`.
///
/// This is a host compile, not `testDebugUnitTest` and not a device
/// injection. Android's mockable `android.jar` would throw on
/// `Uri.parse` / `Intent` here — keep this class out of `src/test`.
class SnapshotSafStoreTest {
    private val payload = byteArrayOf(9, 8, 7)
    private val testUri = Uri.parse("content://downloads/kotonoha-progress.json")

    @Test
    fun launchFailureReleasesPendingSoRetryCanOpenPickerAgain() {
        var starts = 0
        val store =
            SnapshotSafStore.forTest(
                launchPicker = { _, _ ->
                    starts++
                    if (starts == 1) throw SecurityException("picker blocked")
                },
                openStream = { ByteArrayOutputStream() },
                ioExecutor = ImmediateExecutor,
            )
        val first = CapturingReply()
        val second = CapturingReply()

        store.requestSave("progress.json", payload, first)
        store.requestSave("progress.json", payload, second)

        assertEquals(2, starts)
        assertEquals(SnapshotSafWrite.FAILED, first.value)
        assertNull(second.value)
    }

    @Test
    fun channelSaveLaunchThrowThenRetryOpensPickerAgain() {
        var starts = 0
        val store =
            SnapshotSafStore.forTest(
                launchPicker = { _, _ ->
                    starts++
                    if (starts == 1) throw SecurityException("picker blocked")
                },
                openStream = { ByteArrayOutputStream() },
                ioExecutor = ImmediateExecutor,
            )

        val first = ChannelResult()
        store.onMethodCall(saveCall(), first)
        assertEquals(1, starts)
        assertEquals(SnapshotSafWrite.FAILED, first.value)

        val second = ChannelResult()
        store.onMethodCall(saveCall(), second)
        assertEquals(2, starts)
        assertNull(second.value)
    }

    @Test
    fun concurrentSaveWhilePendingReturnsFailedWithoutStartingAgain() {
        var starts = 0
        val store =
            SnapshotSafStore.forTest(
                launchPicker = { _, _ -> starts++ },
                openStream = { ByteArrayOutputStream() },
                ioExecutor = ImmediateExecutor,
            )
        val first = CapturingReply()
        val busy = CapturingReply()

        store.requestSave("progress.json", payload, first)
        store.requestSave("progress.json", payload, busy)

        assertEquals(1, starts)
        assertNull(first.value)
        assertEquals(SnapshotSafWrite.FAILED, busy.value)
    }

    @Test
    fun cancelClearsPending() {
        val store =
            SnapshotSafStore.forTest(
                launchPicker = { _, _ -> },
                openStream = { ByteArrayOutputStream() },
                ioExecutor = ImmediateExecutor,
            )
        val reply = CapturingReply()
        store.requestSave("progress.json", payload, reply)

        assertTrue(
            store.onActivityResult(
                SnapshotSafStore.REQUEST_CREATE,
                Activity.RESULT_CANCELED,
                null,
            ),
        )

        assertEquals(SnapshotSafStore.CANCELLED, reply.value)
    }

    @Test
    fun nullStreamAfterPickerIsFailed() {
        val store =
            SnapshotSafStore.forTest(
                launchPicker = { _, _ -> },
                openStream = { null },
                ioExecutor = ImmediateExecutor,
            )
        val reply = CapturingReply()
        store.requestSave("progress.json", payload, reply)

        store.onActivityResult(
            SnapshotSafStore.REQUEST_CREATE,
            Activity.RESULT_OK,
            Intent().setData(testUri),
        )

        assertEquals(SnapshotSafWrite.FAILED, reply.value)
    }

    @Test
    fun writeThrowAfterPickerIsFailed() {
        val store =
            SnapshotSafStore.forTest(
                launchPicker = { _, _ -> },
                openStream = { ThrowingStream() },
                ioExecutor = ImmediateExecutor,
            )
        val reply = CapturingReply()
        store.requestSave("progress.json", payload, reply)

        store.onActivityResult(
            SnapshotSafStore.REQUEST_CREATE,
            Activity.RESULT_OK,
            Intent().setData(testUri),
        )

        assertEquals(SnapshotSafWrite.FAILED, reply.value)
    }

    @Test
    fun successfulWriteIsSaved() {
        val sink = ByteArrayOutputStream()
        val store =
            SnapshotSafStore.forTest(
                launchPicker = { _, _ -> },
                openStream = { sink },
                ioExecutor = ImmediateExecutor,
            )
        val reply = CapturingReply()
        store.requestSave("progress.json", payload, reply)

        store.onActivityResult(
            SnapshotSafStore.REQUEST_CREATE,
            Activity.RESULT_OK,
            Intent().setData(testUri),
        )

        assertEquals(SnapshotSafWrite.SAVED, reply.value)
        assertEquals(payload.toList(), sink.toByteArray().toList())
    }

    @Test
    fun missingDocumentUriIsFailedWithoutWrite() {
        var opened = 0
        val store =
            SnapshotSafStore.forTest(
                launchPicker = { _, _ -> },
                openStream = {
                    opened++
                    ByteArrayOutputStream()
                },
                ioExecutor = ImmediateExecutor,
            )
        val reply = CapturingReply()
        store.requestSave("progress.json", payload, reply)

        store.onActivityResult(
            SnapshotSafStore.REQUEST_CREATE,
            Activity.RESULT_OK,
            Intent(),
        )

        assertEquals(SnapshotSafWrite.FAILED, reply.value)
        assertEquals(0, opened)
    }

    @Test
    fun slowWriteReturnsBeforeCompletionAndBlocksReentryUntilSaved() {
        val writeStarted = CountDownLatch(1)
        val releaseWrite = CountDownLatch(1)
        val settled = CountDownLatch(1)
        val sink = ByteArrayOutputStream()
        val slowStream =
            object : OutputStream() {
                override fun write(b: Int) {
                    writeStarted.countDown()
                    assertTrue(releaseWrite.await(2, TimeUnit.SECONDS))
                    sink.write(b)
                }

                override fun write(
                    b: ByteArray,
                    off: Int,
                    len: Int,
                ) {
                    writeStarted.countDown()
                    assertTrue(releaseWrite.await(2, TimeUnit.SECONDS))
                    sink.write(b, off, len)
                }
            }
        var starts = 0
        val store =
            SnapshotSafStore.forTest(
                launchPicker = { _, _ -> starts++ },
                openStream = { slowStream },
                postToMain = { task ->
                    task.run()
                    settled.countDown()
                },
            )
        val reply = CapturingReply()
        val busy = CapturingReply()

        store.requestSave("progress.json", payload, reply)
        val returned =
            store.onActivityResult(
                SnapshotSafStore.REQUEST_CREATE,
                Activity.RESULT_OK,
                Intent().setData(testUri),
            )
        assertTrue(returned)
        assertTrue(writeStarted.await(2, TimeUnit.SECONDS))
        assertNull(reply.value)

        store.requestSave("progress.json", payload, busy)
        assertEquals(1, starts)
        assertEquals(SnapshotSafWrite.FAILED, busy.value)

        releaseWrite.countDown()
        assertTrue(settled.await(2, TimeUnit.SECONDS))
        assertEquals(SnapshotSafWrite.SAVED, reply.value)
        assertEquals(payload.toList(), sink.toByteArray().toList())
    }

    @Test
    fun unknownRequestCodeIsIgnored() {
        val store =
            SnapshotSafStore.forTest(
                launchPicker = { _, _ -> },
                openStream = { ByteArrayOutputStream() },
                ioExecutor = ImmediateExecutor,
            )
        assertFalse(store.onActivityResult(0, Activity.RESULT_OK, null))
    }

    private fun saveCall(): MethodCall =
        MethodCall(
            "save",
            mapOf(
                "suggestedName" to "progress.json",
                "bytes" to payload,
            ),
        )

    private class CapturingReply : SnapshotSafStore.SnapshotSafReply {
        var value: String? = null

        override fun success(value: String) {
            this.value = value
        }
    }

    private class ChannelResult : MethodChannel.Result {
        var value: Any? = null

        override fun success(result: Any?) {
            value = result
        }

        override fun error(
            errorCode: String,
            errorMessage: String?,
            errorDetails: Any?,
        ) {
            value = "error:$errorCode"
        }

        override fun notImplemented() {
            value = "notImplemented"
        }
    }

    private class ThrowingStream : OutputStream() {
        override fun write(b: Int) {
            throw IOException("write failed")
        }
    }

    private companion object {
        val ImmediateExecutor = Executor { command -> command.run() }
    }
}
