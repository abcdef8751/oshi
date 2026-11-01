package dev.rp.oshi

import android.accessibilityservice.AccessibilityService
import android.content.Intent
import android.graphics.Bitmap
import android.util.Log
import android.view.Display
import android.view.accessibility.AccessibilityEvent

/**
 * Accessibility service that exists solely to own [takeScreenshot].
 *
 * It does not read window content (`canRetrieveWindowContent="false"` in the
 * service config); we only need pixels the user explicitly asked for.
 */
class CaptureAccessibilityService : AccessibilityService() {

    /** Result of a single capture request. */
    sealed class CaptureResult {
        class Success(val bitmap: Bitmap) : CaptureResult()
        class Failure(val code: String) : CaptureResult()
    }

    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) = Unit

    override fun onInterrupt() = Unit

    override fun onUnbind(intent: Intent?): Boolean {
        clearInstance(this)
        return super.onUnbind(intent)
    }

    override fun onDestroy() {
        clearInstance(this)
        super.onDestroy()
    }

    /**
     * Grabs a frame from [displayId] and hands the caller an ARGB_8888 copy.
     *
     * The callback always runs on the main thread (the executor we pass to
     * [takeScreenshot] is [mainExecutor]). The hardware buffer is closed before
     * the callback fires, so the bitmap is safe to keep.
     */
    fun capture(
        displayId: Int = Display.DEFAULT_DISPLAY,
        callback: (CaptureResult) -> Unit,
    ) {
        takeScreenshot(
            displayId,
            mainExecutor,
            object : AccessibilityService.TakeScreenshotCallback {
                override fun onSuccess(screenshot: AccessibilityService.ScreenshotResult) {
                    val buffer = screenshot.hardwareBuffer
                    if (buffer == null) {
                        callback(CaptureResult.Failure(CaptureErrorCodes.INTERNAL_ERROR))
                        return
                    }
                    val bitmap = try {
                        Bitmap.wrapHardwareBuffer(buffer, screenshot.colorSpace)
                            ?.copy(Bitmap.Config.ARGB_8888, false)
                    } catch (t: Throwable) {
                        Log.e(TAG, "Could not copy screenshot", t)
                        null
                    } finally {
                        buffer.close()
                    }
                    if (bitmap == null) {
                        callback(CaptureResult.Failure(CaptureErrorCodes.INTERNAL_ERROR))
                    } else {
                        callback(CaptureResult.Success(bitmap))
                    }
                }

                override fun onFailure(errorCode: Int) {
                    callback(CaptureResult.Failure(mapError(errorCode)))
                }
            },
        )
    }

    companion object {
        private const val TAG = "OshiCaptureService"

        /** The currently connected service, or null when accessibility is off. */
        @Volatile
        var instance: CaptureAccessibilityService? = null
            private set

        private fun clearInstance(service: CaptureAccessibilityService) {
            if (instance === service) instance = null
        }

        /** Maps an `AccessibilityService.ERROR_TAKE_SCREENSHOT_*` to a contract code. */
        fun mapError(errorCode: Int): String = when (errorCode) {
            AccessibilityService.ERROR_TAKE_SCREENSHOT_SECURE_WINDOW ->
                CaptureErrorCodes.SECURE_WINDOW
            AccessibilityService.ERROR_TAKE_SCREENSHOT_INTERVAL_TIME_SHORT ->
                CaptureErrorCodes.INTERVAL_TIME_SHORT
            AccessibilityService.ERROR_TAKE_SCREENSHOT_NO_ACCESSIBILITY_ACCESS ->
                CaptureErrorCodes.NO_ACCESSIBILITY_ACCESS
            else -> CaptureErrorCodes.INTERNAL_ERROR
        }
    }
}
