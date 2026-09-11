package android.os

class Handler(
    looper: Looper,
) {
    fun post(r: Runnable): Boolean {
        r.run()
        return true
    }
}
