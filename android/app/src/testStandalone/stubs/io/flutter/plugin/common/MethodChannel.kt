package io.flutter.plugin.common

class MethodChannel {
    interface MethodCallHandler {
        fun onMethodCall(
            call: MethodCall,
            result: Result,
        )
    }

    interface Result {
        fun success(result: Any?)

        fun error(
            errorCode: String,
            errorMessage: String?,
            errorDetails: Any?,
        )

        fun notImplemented()
    }
}
