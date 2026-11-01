package dev.rp.oshi

import android.content.Intent
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var captureHandler: CaptureChannelHandler? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // A restored task replays the original launch intent; the capture it
        // points at is long consumed (and latest.png may hold a newer shot).
        if (savedInstanceState == null) {
            handleCaptureIntent(intent)
            if (CapturePending.hasPending()) {
                // Appear like an overlay, not an app launch.
                @Suppress("DEPRECATION")
                overridePendingTransition(0, 0)
            }
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == CaptureNotifications.PERMISSION_REQUEST_CODE) {
            // Posting is a no-op if the user denied, so just try again.
            CaptureNotifications.post(this, this)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        captureHandler = CaptureChannelHandler(this, flutterEngine)
        // The trigger activity may have parked a capture before the engine was
        // ready; let Dart know it can drain.
        if (CapturePending.hasPending()) {
            captureHandler?.notifyCaptureAvailable()
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleCaptureIntent(intent)
    }

    private fun handleCaptureIntent(intent: Intent?) {
        if (intent == null) return
        val path = intent.getStringExtra(CapturePending.EXTRA_CAPTURE_PATH)
        val error = intent.getStringExtra(CapturePending.EXTRA_CAPTURE_ERROR)
        if (path == null && error == null) return
        intent.removeExtra(CapturePending.EXTRA_CAPTURE_PATH)
        intent.removeExtra(CapturePending.EXTRA_CAPTURE_ERROR)
        CapturePending.set(path, error)
        captureHandler?.notifyCaptureAvailable()
    }
}
