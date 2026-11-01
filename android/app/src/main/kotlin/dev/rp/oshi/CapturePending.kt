package dev.rp.oshi

/**
 * One-shot hand-off between [CaptureTriggerActivity] (which owns the bitmap)
 * and [MainActivity] (which owns the Flutter engine).
 *
 * The trigger writes a PNG to the cache, starts MainActivity with the path as
 * an extra, and this object bridges the gap for the case where the extra is
 * consumed before Dart is listening. [CaptureChannelHandler.getPendingCapture]
 * drains it.
 */
object CapturePending {
    const val EXTRA_CAPTURE_PATH = "dev.rp.oshi.extra.CAPTURE_PATH"
    const val EXTRA_CAPTURE_ERROR = "dev.rp.oshi.extra.CAPTURE_ERROR"

    @Volatile
    private var path: String? = null

    @Volatile
    private var error: String? = null

    @Synchronized
    fun set(newPath: String?, newError: String? = null) {
        path = newPath
        error = newError
    }

    @Synchronized
    fun hasPending(): Boolean = path != null || error != null

    /** Returns `(path, error)` and clears both, or null when nothing is pending. */
    @Synchronized
    fun drain(): Pair<String?, String?>? {
        if (path == null && error == null) return null
        val result = Pair(path, error)
        path = null
        error = null
        return result
    }
}
