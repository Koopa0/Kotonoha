package android.net

class Uri(
    val spec: String,
) {
    override fun toString(): String = spec

    companion object {
        fun parse(spec: String): Uri = Uri(spec)
    }
}
