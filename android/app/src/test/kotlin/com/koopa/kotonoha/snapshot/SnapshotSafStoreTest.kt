package com.koopa.kotonoha.snapshot

import android.app.Activity
import android.content.Intent
import android.net.Uri
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.ByteArrayOutputStream
import java.io.OutputStream
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger

class SnapshotSafStoreTest {
    private val payload = byteArrayOf(9, 8, 7)
    private val testUri = Uri.parse("content://downloads/kotonoha-progress.json")

    private class CapturingReply : SnapshotSafStore.SnapshotSafReply {
        var value: String? = null

        override fun success(value: String) {
            this.value = value
        }
    }

    @Test
    fun launchFailureReleasesPendingSoRetryCanOpenPickerAgain() {
        var starts = 0
        val store =
            SnapshotSafStore.forTest(
                launchPicker = {
                    starts++
                    if (starts == 1) throw SecurityException("picker blocked")
                },
                openStream = { ByteArrayOutputStream() },
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
    fun concurrentSaveWhilePendingReturnsFailedWithoutStartingAgain() {
        var starts = 0
        val store =
            SnapshotSafStore.forTest(
                launchPicker = { starts++ },
                openStream = { ByteArrayOutputStream() },
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
            )
        val reply = CapturingReply()
        store.requestSave("progress.json", payload, reply)

        assertTrue(store.onActivityResult(SnapshotSafStore.REQUEST_CREATE, Activity.RESULT_CANCELED, null))

        assertEquals(SnapshotSafStore.CANCELLED, reply.value)
    }

    @Test
    fun nullStreamAfterPickerIsFailed() {
        val store =
            SnapshotSafStore.forTest(
                launchPicker = { _, _ -> },
                openStream = { null },
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
    fun slowWriteReturnsBeforeCompletionAndBlocksReentryUntilSaved() {
        val writeStarted = CountDownLatch(1)
        val releaseWrite = CountDownLatch(1)
        val sink = ByteArrayOutputStream()
        val slowStream =
            object : OutputStream() {
                override fun write(b: Int) {
                    writeStarted.countDown()
                    assertTrue(releaseWrite.await(2, TimeUnit.SECONDS))
                    sink.write(b)
                }

                override fun write(b: ByteArray, off: Int, len: Int) {
                    writeStarted.countDown()
                    assertTrue(releaseWrite.await(2, TimeUnit.SECONDS))
                    sink.write(b, off, len)
                }
            }
        var starts = 0
        val store =
            SnapshotSafStore.forTest(
                launchPicker = { starts++ },
                openStream = { slowStream },
            )
        val reply = CapturingReply()
        val busy = CapturingReply()

        store.requestSave("progress.json", payload, reply)
        assertTrue(
            store.onActivityResult(
                SnapshotSafStore.REQUEST_CREATE,
                Activity.RESULT_OK,
                Intent().setData(testUri),
            ),
        )
        assertTrue(writeStarted.await(2, TimeUnit.SECONDS))
        assertNull(reply.value)

        store.requestSave("progress.json", payload, busy)
        assertEquals(1, starts)
        assertEquals(SnapshotSafWrite.FAILED, busy.value)

        releaseWrite.countDown()
        Thread.sleep(200)

        assertEquals(SnapshotSafWrite.SAVED, reply.value)
        assertEquals(payload.toList(), sink.toByteArray().toList())
    }

    @Test
    fun handlerReturnsBeforeBackgroundWriteFinishes() {
        val writeGate = CountDownLatch(1)
        val handlerReturned = AtomicInteger(0)
        val store =
            SnapshotSafStore.forTest(
                launchPicker = { _, _ -> },
                openStream = {
                    object : OutputStream() {
                        override fun write(b: Int) {
                            writeGate.await()
                        }
                    }
                },
            )
        val reply = CapturingReply()
        store.requestSave("progress.json", payload, reply)

        val returned =
            store.onActivityResult(
                SnapshotSafStore.REQUEST_CREATE,
                Activity.RESULT_OK,
                Intent().setData(testUri),
            )
        handlerReturned.incrementAndGet()

        assertTrue(returned)
        assertEquals(1, handlerReturned.get())
        assertNull(reply.value)

        writeGate.countDown()
        Thread.sleep(200)
        assertEquals(SnapshotSafWrite.SAVED, reply.value)
    }

    @Test
    fun unknownRequestCodeIsIgnored() {
        val store =
            SnapshotSafStore.forTest(
                launchPicker = { _, _ -> },
                openStream = { ByteArrayOutputStream() },
            )
        assertFalse(store.onActivityResult(0, Activity.RESULT_OK, null))
    }
}
