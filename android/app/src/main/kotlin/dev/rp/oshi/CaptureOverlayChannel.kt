package dev.rp.oshi

import android.app.Activity
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.provider.Settings
import android.util.Log
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/** The "Display over other apps" permission, which gates the overlay capture. */
object OverlayPermission {
    fun isPermitted(context: Context): Boolean = Settings.canDrawOverlays(context)
}

/**
 * Dart-facing half of the capture overlay, bound to a [CaptureActivity].
 *
 * The activity renders the crop UI in its own, excluded-from-recents task with
 * a transparent window, so the user's app stays visible behind the result
 * sheet and Oshi never comes to the foreground.
 */
class CaptureOverlayChannel(
    private val activity: Activity,
    engine: FlutterEngine,
    private val imagePath: String?,
) : MethodChannel.MethodCallHandler {

    private val channel = MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL_NAME)

    init {
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "ready" -> result.success(
                mapOf(
                    // The intent extra is the fast path; CapturePending covers
                    // a task restore or a missed extra.
                    "path" to (imagePath ?: CapturePending.drain()?.first),
                    // Read Flutter's preferences directly so the overlay starts in
                    // the user's default language.
                    "targetLang" to activity
                        .getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                        .getString("flutter.target_lang", "en"),
                ),
            )
            "dismiss" -> {
                result.success(null)
                activity.finish()
            }
            "copy" -> {
                val text = call.argument<String>("text")
                result.success(text != null && copyToClipboard(text))
            }
            // Should not happen in an activity-hosted overlay, but a frozen
            // window is worse than the fallback.
            "stalled" -> {
                Log.w(TAG, "Overlay reported a stalled surface; falling back")
                result.success(null)
                fallbackToApp()
            }
            else -> result.notImplemented()
        }
    }

    private fun copyToClipboard(text: String): Boolean {
        return try {
            val manager =
                activity.getSystemService(Context.CLIPBOARD_SERVICE) as? ClipboardManager
                    ?: return false
            manager.setPrimaryClip(ClipData.newPlainText("Oshi", text))
            true
        } catch (t: Throwable) {
            Log.w(TAG, "Could not copy to the clipboard", t)
            false
        }
    }

    private fun fallbackToApp() {
        val path = imagePath
        try {
            activity.startActivity(
                Intent(activity, MainActivity::class.java).apply {
                    addFlags(
                        Intent.FLAG_ACTIVITY_NEW_TASK or
                            Intent.FLAG_ACTIVITY_SINGLE_TOP or
                            Intent.FLAG_ACTIVITY_CLEAR_TOP,
                    )
                    if (path != null) putExtra(CapturePending.EXTRA_CAPTURE_PATH, path)
                },
            )
        } catch (t: Throwable) {
            Log.e(TAG, "Could not fall back to MainActivity", t)
            CapturePending.set(path, null)
        } finally {
            activity.finish()
        }
    }

    private companion object {
        const val TAG = "OshiOverlay"
        const val CHANNEL_NAME = "oshi/overlay"
    }
}
