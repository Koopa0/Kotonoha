package android.app

import android.content.ContentResolver
import android.content.Intent

open class Activity {
    val contentResolver: ContentResolver = ContentResolver()

    fun startActivityForResult(
        intent: Intent,
        requestCode: Int,
    ) {
    }

    companion object {
        const val RESULT_OK = -1
        const val RESULT_CANCELED = 0
    }
}
