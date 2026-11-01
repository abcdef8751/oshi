package dev.rp.oshi

import android.accessibilityservice.AccessibilityServiceInfo
import android.app.Activity
import android.app.StatusBarManager
import android.content.ActivityNotFoundException
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.drawable.Icon
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.util.Log
import android.view.accessibility.AccessibilityManager
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Dart-facing half of the capture pipeline (`oshi/capture`).
 *
 * Constructed by [MainActivity] in `configureFlutterEngine`; registers itself as
 * the channel handler immediately so Dart can call as soon as the first frame
 * is up.
 */
class CaptureChannelHandler(
    private val activity: Activity,
    engine: FlutterEngine,
) : MethodChannel.MethodCallHandler {

    private val mainHandler = Handler(Looper.getMainLooper())
    private val channel = MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL_NAME)

    init {
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isAccessibilityEnabled" -> result.success(isAccessibilityEnabled())
            "openAccessibilitySettings" -> openAccessibilitySettings(result)
            "takeScreenshot" -> takeScreenshot(result)
            "postNotification" -> {
                CaptureNotifications.post(activity, activity)
                result.success(null)
            }
            "cancelNotification" -> {
                CaptureNotifications.cancel(activity)
                result.success(null)
            }
            "isTileAdded" -> result.success(isTileAdded())
            "openTileSettings" -> openTileSettings(result)
            "getPendingCapture" -> result.success(pendingCapture())
            else -> result.notImplemented()
        }
    }

    /** Tells Dart that [CapturePending] now holds a fresh capture. */
    fun notifyCaptureAvailable() {
        try {
            channel.invokeMethod(METHOD_CAPTURE_AVAILABLE, null)
        } catch (t: Throwable) {
            // Engine detached (activity going away): Dart drains on next start.
            Log.w(TAG, "Could not notify Dart about a capture", t)
        }
    }

    private fun isAccessibilityEnabled(): Boolean {
        if (CaptureAccessibilityService.instance != null) return true

        val manager = activity.getSystemService(Context.ACCESSIBILITY_SERVICE) as? AccessibilityManager
        val enabledServices = manager
            ?.getEnabledAccessibilityServiceList(AccessibilityServiceInfo.FEEDBACK_ALL_MASK)
            .orEmpty()
        val listed = enabledServices.any { info ->
            val serviceInfo = info.resolveInfo?.serviceInfo ?: return@any false
            serviceInfo.packageName == activity.packageName &&
                serviceInfo.name == CaptureAccessibilityService::class.java.name
        }
        if (listed) return true

        // Fallback for OEMs whose AccessibilityManager list lags behind the
        // secure setting (and for the service being enabled but not connected).
        val flattened = Settings.Secure.getString(
            activity.contentResolver,
            Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES,
        )
        val expected = ComponentName(activity, CaptureAccessibilityService::class.java)
        return flattened
            ?.split(':')
            ?.any { ComponentName.unflattenFromString(it) == expected } == true
    }

    private fun openAccessibilitySettings(result: MethodChannel.Result) {
        val intent = Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        try {
            activity.startActivity(intent)
            result.success(null)
        } catch (t: ActivityNotFoundException) {
            Log.e(TAG, "Accessibility settings screen not found", t)
            result.error(CaptureErrorCodes.INTERNAL_ERROR, "Accessibility settings not found", null)
        } catch (t: Throwable) {
            Log.e(TAG, "Could not open accessibility settings", t)
            result.error(CaptureErrorCodes.INTERNAL_ERROR, t.message, null)
        }
    }

    private fun takeScreenshot(result: MethodChannel.Result) {
        val service = CaptureAccessibilityService.instance
        if (service == null) {
            result.error(
                CaptureErrorCodes.NO_ACCESSIBILITY_ACCESS,
                "Accessibility capture service is not connected",
                null,
            )
            return
        }
        // The callback is main-thread; a watchdog covers a service that dies
        // between the call and the callback (otherwise Dart hangs forever).
        var finished = false
        val watchdog = Runnable {
            if (finished) return@Runnable
            finished = true
            result.error(
                CaptureErrorCodes.INTERNAL_ERROR,
                "Screenshot timed out",
                null,
            )
        }
        mainHandler.postDelayed(watchdog, CAPTURE_TIMEOUT_MS)
        try {
            service.capture { outcome ->
                // The service's executor is the main thread, but keep the channel
                // contract explicit in case that ever changes.
                runOnMain {
                    if (finished) {
                        if (outcome is CaptureAccessibilityService.CaptureResult.Success) {
                            outcome.bitmap.recycle()
                        }
                        return@runOnMain
                    }
                    finished = true
                    mainHandler.removeCallbacks(watchdog)
                    when (outcome) {
                        is CaptureAccessibilityService.CaptureResult.Success -> {
                            try {
                                val file =
                                    ScreenshotStore.writeLatest(activity.cacheDir, outcome.bitmap)
                                result.success(file.absolutePath)
                            } catch (t: Throwable) {
                                Log.e(TAG, "Could not save screenshot", t)
                                result.error(
                                    CaptureErrorCodes.INTERNAL_ERROR,
                                    t.message ?: "Could not save screenshot",
                                    null,
                                )
                            } finally {
                                outcome.bitmap.recycle()
                            }
                        }
                        is CaptureAccessibilityService.CaptureResult.Failure -> {
                            result.error(outcome.code, messageFor(outcome.code), null)
                        }
                    }
                }
            }
        } catch (t: Throwable) {
            if (finished) return
            finished = true
            mainHandler.removeCallbacks(watchdog)
            Log.e(TAG, "Could not start screenshot", t)
            result.error(
                CaptureErrorCodes.INTERNAL_ERROR,
                t.message ?: "Could not capture the screen",
                null,
            )
        }
    }

    /**
     * There is no public API to query whether a tile is added (`isTileAdded`
     * is hidden), so [CaptureTileService] records it in [TileState] from its
     * own `onTileAdded` / `onTileRemoved` callbacks.
     */
    private fun isTileAdded(): Boolean = TileState.isAdded(activity)

    private fun openTileSettings(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU && requestTileAdd()) {
            result.success(null)
            return
        }
        try {
            activity.startActivity(
                Intent(ACTION_QUICK_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            )
            result.success(null)
        } catch (_: ActivityNotFoundException) {
            try {
                activity.startActivity(
                    Intent(Settings.ACTION_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                )
                result.success(null)
            } catch (fallback: Throwable) {
                Log.e(TAG, "Could not open quick settings", fallback)
                result.error(CaptureErrorCodes.INTERNAL_ERROR, fallback.message, null)
            }
        } catch (t: Throwable) {
            Log.e(TAG, "Could not open quick settings", t)
            result.error(CaptureErrorCodes.INTERNAL_ERROR, t.message, null)
        }
    }

    /**
     * API 33+ can ask the system to add the tile directly, which is one tap
     * instead of opening the Quick Settings editor.
     */
    private fun requestTileAdd(): Boolean {
        return try {
            val statusBarManager =
                activity.getSystemService(Context.STATUS_BAR_SERVICE) as? StatusBarManager
                    ?: return false
            statusBarManager.requestAddTileService(
                ComponentName(activity, CaptureTileService::class.java),
                activity.getString(R.string.tile_label),
                Icon.createWithResource(activity, R.drawable.ic_tile),
                activity.mainExecutor,
            ) { code ->
                if (code == StatusBarManager.TILE_ADD_REQUEST_RESULT_TILE_ADDED ||
                    code == StatusBarManager.TILE_ADD_REQUEST_RESULT_TILE_ALREADY_ADDED
                ) {
                    TileState.setAdded(activity, true)
                }
            }
            true
        } catch (t: Throwable) {
            Log.w(TAG, "Could not request the tile be added", t)
            false
        }
    }

    private fun pendingCapture(): Map<String, Any?> {
        val pending = CapturePending.drain() ?: return emptyMap()
        return mapOf(
            "path" to pending.first,
            "error" to pending.second,
        )
    }

    private fun runOnMain(block: () -> Unit) {
        if (Looper.myLooper() == Looper.getMainLooper()) {
            block()
        } else {
            mainHandler.post(block)
        }
    }

    private fun messageFor(code: String): String = when (code) {
        CaptureErrorCodes.SECURE_WINDOW -> "This screen is protected"
        CaptureErrorCodes.NO_ACCESSIBILITY_ACCESS -> "Accessibility capture is not enabled"
        CaptureErrorCodes.INTERVAL_TIME_SHORT -> "Screenshots were requested too soon"
        else -> "Could not capture the screen"
    }

    private companion object {
        const val TAG = "OshiCaptureChannel"
        const val CHANNEL_NAME = "oshi/capture"
        const val METHOD_CAPTURE_AVAILABLE = "onCaptureAvailable"
        const val ACTION_QUICK_SETTINGS = "android.settings.QUICK_SETTINGS"
        const val CAPTURE_TIMEOUT_MS = 3_000L
    }
}
