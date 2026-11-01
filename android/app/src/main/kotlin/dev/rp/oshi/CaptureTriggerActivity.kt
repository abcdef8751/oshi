package dev.rp.oshi

import android.app.Activity
import android.content.Intent
import android.graphics.Bitmap
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.Log

/**
 * Invisible trampoline started by the ongoing notification or the Quick
 * Settings tile.
 *
 * On Android 12+ a notification cannot trampoline into a receiver, and the
 * shade is still animating away when the tap lands. Existing as an activity
 * both dismisses the shade and gives us a cheap place to wait 400 ms before
 * grabbing pixels. The capture is written to the cache and handed to
 * [MainActivity] as an intent extra; nothing is rendered here.
 */
class CaptureTriggerActivity : Activity() {

    private val handler = Handler(Looper.getMainLooper())
    private var destroyed = false
    private var retried = false

    private val captureRunnable = Runnable { attemptCapture() }

    /** Fires if the screenshot callback never arrives (service torn down mid-call). */
    private val watchdog = Runnable { finishWithError(CaptureErrorCodes.INTERNAL_ERROR) }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        scheduleCapture()
    }

    override fun onNewIntent(intent: Intent?) {
        super.onNewIntent(intent)
        setIntent(intent)
        // Tapping again while we are alive (singleTask) starts a fresh attempt.
        retried = false
        scheduleCapture()
    }

    override fun onDestroy() {
        destroyed = true
        handler.removeCallbacksAndMessages(null)
        super.onDestroy()
    }

    private fun scheduleCapture() {
        handler.removeCallbacks(captureRunnable)
        handler.postDelayed(captureRunnable, SHADE_COLLAPSE_DELAY_MS)
    }

    private fun attemptCapture() {
        if (destroyed || isFinishing) return
        val service = CaptureAccessibilityService.instance
        if (service == null) {
            finishWithError(CaptureErrorCodes.NO_ACCESSIBILITY_ACCESS)
            return
        }
        handler.removeCallbacks(watchdog)
        handler.postDelayed(watchdog, CAPTURE_TIMEOUT_MS)
        try {
            service.capture { outcome -> handleCaptureResult(outcome) }
        } catch (t: Throwable) {
            Log.e(TAG, "Could not start screenshot", t)
            finishWithError(CaptureErrorCodes.INTERNAL_ERROR)
        }
    }

    private fun handleCaptureResult(outcome: CaptureAccessibilityService.CaptureResult) {
        handler.removeCallbacks(watchdog)
        if (destroyed) {
            if (outcome is CaptureAccessibilityService.CaptureResult.Success) {
                outcome.bitmap.recycle()
            }
            return
        }
        when (outcome) {
            is CaptureAccessibilityService.CaptureResult.Success -> saveAndLaunch(outcome.bitmap)
            is CaptureAccessibilityService.CaptureResult.Failure -> {
                if (outcome.code == CaptureErrorCodes.INTERVAL_TIME_SHORT && !retried) {
                    retried = true
                    handler.removeCallbacks(captureRunnable)
                    handler.postDelayed(captureRunnable, SHADE_COLLAPSE_DELAY_MS)
                } else {
                    finishWithError(outcome.code)
                }
            }
        }
    }

    private fun saveAndLaunch(bitmap: Bitmap) {
        // A full-screen PNG encode takes long enough to stall the main thread;
        // do it on a worker so the app opens immediately.
        Thread {
            val file = try {
                ScreenshotStore.writeLatest(cacheDir, bitmap)
            } catch (t: Throwable) {
                Log.e(TAG, "Could not write capture", t)
                null
            } finally {
                bitmap.recycle()
            }
            runOnUiThread {
                if (destroyed) return@runOnUiThread
                if (file == null) {
                    finishWithError(CaptureErrorCodes.INTERNAL_ERROR)
                } else {
                    launchMainActivity(path = file.absolutePath, error = null)
                }
            }
        }.start()
    }

    private fun finishWithError(code: String) {
        launchMainActivity(path = null, error = code)
    }

    private fun launchMainActivity(path: String?, error: String?) {
        val intent = Intent(this, MainActivity::class.java).apply {
            addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP or
                    Intent.FLAG_ACTIVITY_NO_ANIMATION,
            )
            if (path != null) putExtra(CapturePending.EXTRA_CAPTURE_PATH, path)
            if (error != null) putExtra(CapturePending.EXTRA_CAPTURE_ERROR, error)
        }
        try {
            startActivity(intent)
        } catch (t: Throwable) {
            // Do not lose the capture if the launch is blocked; Dart drains this
            // on the next successful start.
            Log.e(TAG, "Could not launch MainActivity, parking the capture", t)
            CapturePending.set(path, error)
        } finally {
            finish()
        }
    }

    private companion object {
        private const val TAG = "OshiCaptureTrigger"

        /**
         * Time the notification shade needs to animate away before a screenshot
         * is free of it. Tune this on the target device first.
         */
        private const val SHADE_COLLAPSE_DELAY_MS = 400L

        /** If the capture callback never lands, fail instead of hanging invisible. */
        private const val CAPTURE_TIMEOUT_MS = 3_000L
    }
}
