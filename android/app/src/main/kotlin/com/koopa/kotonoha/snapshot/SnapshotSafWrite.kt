package com.koopa.kotonoha.snapshot

import java.io.OutputStream

/// Confirmed SAF write. A null stream or any throw is failure — never a
/// URI / path standing in for bytes that did not land.
object SnapshotSafWrite {
    const val SAVED = "saved"
    const val FAILED = "failed"

    fun write(
        openStream: () -> OutputStream?,
        bytes: ByteArray,
    ): String {
        val stream =
            try {
                openStream()
            } catch (_: Exception) {
                return FAILED
            } ?: return FAILED
        return try {
            stream.use { out ->
                out.write(bytes)
                out.flush()
            }
            SAVED
        } catch (_: Exception) {
            FAILED
        }
    }
}
