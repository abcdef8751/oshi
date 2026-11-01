package dev.rp.oshi

import android.app.PendingIntent
import android.content.Intent
import android.graphics.drawable.Icon
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import android.util.Log

/**
 * Quick Settings entry point. Like the notification it only launches
 * [CaptureTriggerActivity]; the tile never touches the screenshot API itself.
 *
 * This code runs in SystemUI's process, so every entrance is wrapped in
 * try/catch: an exception here would take down the system UI.
 */
class CaptureTileService : TileService() {

    override fun onStartListening() {
        super.onStartListening()
        // Listening implies the tile exists on this device; reconcile the flag
        // in case it was added before Oshi ever saw onTileAdded.
        TileState.setAdded(this, true)
        try {
            val tile = qsTile ?: return
            tile.label = getString(R.string.tile_label)
            tile.icon = Icon.createWithResource(this, R.drawable.ic_tile)
            tile.state = Tile.STATE_INACTIVE
            tile.updateTile()
        } catch (t: Throwable) {
            Log.w(TAG, "Could not update capture tile", t)
        }
    }

    override fun onTileAdded() {
        super.onTileAdded()
        TileState.setAdded(this, true)
    }

    override fun onTileRemoved() {
        super.onTileRemoved()
        TileState.setAdded(this, false)
    }

    override fun onClick() {
        super.onClick()
        try {
            val intent = Intent(this, CaptureTriggerActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                val pendingIntent = PendingIntent.getActivity(
                    this,
                    REQUEST_CODE,
                    intent,
                    PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
                )
                startActivityAndCollapse(pendingIntent)
            } else {
                @Suppress("DEPRECATION")
                startActivityAndCollapse(intent)
            }
        } catch (t: Throwable) {
            Log.w(TAG, "Could not start capture from tile", t)
        }
    }

    private companion object {
        private const val TAG = "OshiCaptureTile"
        private const val REQUEST_CODE = 2001
    }
}
