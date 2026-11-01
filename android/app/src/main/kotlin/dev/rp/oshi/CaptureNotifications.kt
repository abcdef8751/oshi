package dev.rp.oshi

import android.Manifest
import android.app.Activity
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.util.Log

/**
 * Single source of truth for the ongoing "Capture text" notification, shared by
 * [CaptureChannelHandler] (Dart toggles it) and [BootReceiver] (restore after
 * boot / update).
 */
object CaptureNotifications {
    const val CHANNEL_ID = "oshi_capture"
    const val NOTIFICATION_ID = 1001
    const val PERMISSION_REQUEST_CODE = 1001

    private const val TAG = "OshiNotifications"

    /**
     * Posts the ongoing notification, or asks for `POST_NOTIFICATIONS` when
     * [activity] can show the dialog. Fails silently: notification trouble must
     * never surface as a Dart exception (nor crash a boot receiver).
     */
    fun post(context: Context, activity: Activity? = null) {
        try {
            if (!isPostAllowed(context)) {
                requestPermissionIfPossible(activity)
                return
            }
            val manager = context.getSystemService(NotificationManager::class.java) ?: return
            ensureChannel(context, manager)
            manager.notify(NOTIFICATION_ID, build(context))
        } catch (t: Throwable) {
            Log.w(TAG, "Could not post capture notification", t)
        }
    }

    fun cancel(context: Context) {
        try {
            context.getSystemService(NotificationManager::class.java)
                ?.cancel(NOTIFICATION_ID)
        } catch (t: Throwable) {
            Log.w(TAG, "Could not cancel capture notification", t)
        }
    }

    private fun isPostAllowed(context: Context): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED

    private fun requestPermissionIfPossible(activity: Activity?) {
        if (activity == null || activity.isFinishing) return
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return
        try {
            activity.requestPermissions(
                arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                PERMISSION_REQUEST_CODE,
            )
        } catch (t: Throwable) {
            Log.w(TAG, "Could not request notification permission", t)
        }
    }

    private fun ensureChannel(context: Context, manager: NotificationManager) {
        val channel = NotificationChannel(
            CHANNEL_ID,
            context.getString(R.string.notification_channel_name),
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = context.getString(R.string.notification_channel_description)
            setShowBadge(false)
        }
        manager.createNotificationChannel(channel)
    }

    private fun build(context: Context): Notification {
        val contentIntent = PendingIntent.getActivity(
            context,
            PERMISSION_REQUEST_CODE,
            Intent(context, CaptureTriggerActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        return Notification.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_capture)
            .setContentTitle(context.getString(R.string.notification_title))
            .setContentText(context.getString(R.string.notification_text))
            .setContentIntent(contentIntent)
            .setCategory(Notification.CATEGORY_SERVICE)
            .setOngoing(true)
            .setShowWhen(false)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .build()
    }
}
