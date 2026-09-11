package io.flutter.plugin.common

class MethodCall(
    val method: String,
    val arguments: Any?,
) {
    @Suppress("UNCHECKED_CAST")
    fun <T> argument(key: String): T? = (arguments as? Map<*, *>)?.get(key) as T?
}
