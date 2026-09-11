package android.content

import android.net.Uri

class Intent(
    val action: String? = null,
) {
    var type: String? = null
    private var dataUri: Uri? = null

    val data: Uri?
        get() = dataUri

    fun addCategory(category: String): Intent = this

    fun putExtra(
        name: String,
        value: String,
    ): Intent = this

    fun setData(uri: Uri?): Intent {
        dataUri = uri
        return this
    }

    companion object {
        const val ACTION_CREATE_DOCUMENT = "android.intent.action.CREATE_DOCUMENT"
        const val CATEGORY_OPENABLE = "android.intent.category.OPENABLE"
        const val EXTRA_TITLE = "android.intent.extra.TITLE"
    }
}
