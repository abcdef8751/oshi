package dev.rp.oshi

import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.android.TransparencyMode
import io.flutter.embedding.engine.FlutterEngine

/**
 * Hosts the capture overlay: a transparent, no-animation activity in its own
 * task, excluded from recents.
 *
 * It renders the crop screen and the result sheet while the user's app stays
 * visible behind them; finishing returns straight to that app. `main()` picks
 * the overlay UI from [getInitialRoute].
 */
class CaptureActivity : FlutterActivity() {

    private var capturePath: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        // Read the extra before super.onCreate(): the engine (and our channel)
        // is configured inside it.
        capturePath = intent?.getStringExtra(CapturePending.EXTRA_CAPTURE_PATH)
        super.onCreate(savedInstanceState)
        @Suppress("DEPRECATION")
        overridePendingTransition(0, 0)
    }

    override fun getInitialRoute(): String = ROUTE_CAPTURE

    /** The window is clear so the app underneath shows through. */
    override fun getTransparencyMode(): TransparencyMode = TransparencyMode.transparent

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        CaptureOverlayChannel(this, flutterEngine, capturePath)
    }

    override fun finish() {
        super.finish()
        @Suppress("DEPRECATION")
        overridePendingTransition(0, 0)
    }

    companion object {
        /** Must match the constant in `lib/overlay/overlay_app.dart`. */
        const val ROUTE_CAPTURE = "/capture"
    }
}
