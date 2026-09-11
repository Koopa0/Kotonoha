package com.koopa.kotonoha.snapshot

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Test
import java.io.ByteArrayOutputStream
import java.io.IOException
import java.io.OutputStream

/// Pure JVM write verdicts. No Android types — safe for standard `src/test`.
class SnapshotSafWriteTest {
    private val payload = byteArrayOf(1, 2, 3, 4)

    @Test
    fun nullStreamIsFailedAndWritesNothing() {
        var opened = false
        val outcome =
            SnapshotSafWrite.write(
                {
                    opened = true
                    null
                },
                payload,
            )
        assertEquals(true, opened)
        assertEquals(SnapshotSafWrite.FAILED, outcome)
    }

    @Test
    fun openThrowIsFailed() {
        val outcome =
            SnapshotSafWrite.write(
                { throw IOException("provider crashed") },
                payload,
            )
        assertEquals(SnapshotSafWrite.FAILED, outcome)
    }

    @Test
    fun writeThrowIsFailed() {
        val outcome =
            SnapshotSafWrite.write(
                { ThrowingStream() },
                payload,
            )
        assertEquals(SnapshotSafWrite.FAILED, outcome)
    }

    @Test
    fun successfulWriteIsSavedAndEmitsExactBytes() {
        val sink = ByteArrayOutputStream()
        val outcome = SnapshotSafWrite.write({ sink }, payload)
        assertEquals(SnapshotSafWrite.SAVED, outcome)
        assertArrayEquals(payload, sink.toByteArray())
    }

    private class ThrowingStream : OutputStream() {
        override fun write(b: Int) {
            throw IOException("write failed")
        }
    }
}
