package dev.rp.oshi

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * Restores the ongoing capture notification after a reboot or an app update.
 *
 * There is no activity here, so the runtime notification permission cannot be
 * requested; when it is missing (or notifications are switched off in Oshi's
 * settings) this does nothing.
 */
class BootReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED &&
            intent.action != Intent.ACTION_MY_PACKAGE_REPLACED
        ) {
            return
        }
        try {
            if (!isNotificationEnabled(context)) return
            CaptureNotifications.post(context)
        } catch (t: Throwable) {
            Log.w(TAG, "Could not restore capture notification", t)
        }
    }

    private fun isNotificationEnabled(context: Context): Boolean {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        // shared_preferences stores Dart keys behind a "flutter." prefix.
        return prefs.getBoolean(KEY_NOTIFICATION_ENABLED, true)
    }

    private companion object {
        private const val TAG = "OshiBootReceiver"
        private const val PREFS_NAME = "FlutterSharedPreferences"
        private const val KEY_NOTIFICATION_ENABLED = "flutter.notification_enabled"
    }
}
