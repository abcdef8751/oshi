package dev.rp.oshi

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.graphics.PixelFormat
import android.provider.Settings
import android.util.Log
import android.view.Gravity
import android.view.WindowManager
import io.flutter.FlutterInjector
import io.flutter.embedding.android.FlutterView
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor.DartEntrypoint
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Hosts the crop + result UI in a `TYPE_APPLICATION_OVERLAY` window so a
 * capture never pulls Oshi to the foreground.
 *
 * The overlay runs its own Flutter engine with the `overlayMain` entrypoint and
 * talks to this object over `oshi/overlay`. The engine is kept warm between
 * captures; only the view is added and removed.
 */
object CaptureOverlayController : MethodChannel.MethodCallHandler {

    private const val TAG = "OshiOverlay"
    private const val CHANNEL_NAME = "oshi/overlay"

    private var appContext: Context? = null
    private var engine: FlutterEngine? = null
    private var channel: MethodChannel? = null
    private var view: FlutterView? = null
    private var windowManager: WindowManager? = null
    private var pendingPath: String? = null

    /** The OS setting the user must grant from system settings. */
    fun isPermitted(context: Context): Boolean = Settings.canDrawOverlays(context)

    /**
     * Shows the overlay for [imagePath]. Returns false when the permission is
     * missing or the window could not be added, so the caller can fall back to
     * the activity-based flow.
     */
    fun show(context: Context, imagePath: String): Boolean {
        if (!isPermitted(context)) return false
        val app = context.applicationContext
        val flutterEngine = ensureEngine(app) ?: return false
        windowManager = app.getSystemService(WindowManager::class.java)

        pendingPath = imagePath
        if (view == null && !attachView(app, flutterEngine)) {
            pendingPath = null
            return false
        }
        // Delivered when Dart is already listening; otherwise Dart pulls the
        // pending path with "ready" after its first frame.
        channel?.invokeMethod("show", mapOf("path" to imagePath))
        return true
    }

    /** Removes the window but keeps the engine for the next capture. */
    fun hide() {
        val current = view ?: return
        view = null
        try {
            windowManager?.removeView(current)
        } catch (t: Throwable) {
            Log.w(TAG, "Could not remove overlay view", t)
        }
        try {
            current.detachFromFlutterEngine()
        } catch (t: Throwable) {
            Log.w(TAG, "Could not detach overlay engine", t)
        }
    }

    fun destroy() {
        hide()
        try {
            channel?.setMethodCallHandler(null)
            engine?.destroy()
        } catch (t: Throwable) {
            Log.w(TAG, "Could not destroy overlay engine", t)
        }
        engine = null
        channel = null
    }

    private fun ensureEngine(context: Context): FlutterEngine? {
        appContext = context.applicationContext
        engine?.let { return it }
        return try {
            val created = FlutterEngine(context)
            created.dartExecutor.executeDartEntrypoint(
                DartEntrypoint(
                    FlutterInjector.instance().flutterLoader().findAppBundlePath(),
                    "overlayMain",
                ),
            )
            val methodChannel =
                MethodChannel(created.dartExecutor.binaryMessenger, CHANNEL_NAME)
            methodChannel.setMethodCallHandler(this)
            channel = methodChannel
            engine = created
            created
        } catch (t: Throwable) {
            Log.e(TAG, "Could not start the overlay engine", t)
            null
        }
    }

    private fun attachView(context: Context, flutterEngine: FlutterEngine): Boolean {
        return try {
            val overlayView = FlutterView(context).apply {
                attachToFlutterEngine(flutterEngine)
            }
            val params = WindowManager.LayoutParams(
                WindowManager.LayoutParams.MATCH_PARENT,
                WindowManager.LayoutParams.MATCH_PARENT,
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
                    WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS or
                    WindowManager.LayoutParams.FLAG_HARDWARE_ACCELERATED,
                PixelFormat.TRANSLUCENT,
            ).apply {
                gravity = Gravity.TOP or Gravity.START
                // Layout over the bars; the Flutter UI handles its own insets.
                fitInsetsTypes = 0
            }
            windowManager?.addView(overlayView, params)
            view = overlayView
            true
        } catch (t: Throwable) {
            Log.e(TAG, "Could not add the overlay window", t)
            false
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            // Dart announces it can receive "show" and drains a cold-start path.
            "ready" -> {
                val path = pendingPath
                pendingPath = null
                // Read Flutter's preferences directly so the overlay starts in
                // the user's default language without a plugin dependency.
                val prefs = appContext?.getSharedPreferences(
                    "FlutterSharedPreferences",
                    Context.MODE_PRIVATE,
                )
                result.success(
                    mapOf(
                        "path" to path,
                        "targetLang" to prefs?.getString("flutter.target_lang", "en"),
                    ),
                )
            }
            "dismiss" -> {
                hide()
                result.success(null)
            }
            "copy" -> {
                val text = call.argument<String>("text")
                result.success(text != null && copyToClipboard(text))
            }
            else -> result.notImplemented()
        }
    }

    private fun copyToClipboard(text: String): Boolean {
        val context = appContext ?: return false
        return try {
            val manager = context.getSystemService(ClipboardManager::class.java) ?: return false
            manager.setPrimaryClip(ClipData.newPlainText("Oshi", text))
            true
        } catch (t: Throwable) {
            Log.w(TAG, "Could not copy to the clipboard", t)
            false
        }
    }
}
