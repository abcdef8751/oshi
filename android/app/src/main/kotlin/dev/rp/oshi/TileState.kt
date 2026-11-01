package dev.rp.oshi

import android.content.Context

/**
 * Remembers whether the Quick Settings tile is present.
 *
 * Android has no public `isTileAdded` query (`StatusBarManager.isTileAdded` is
 * hidden), so [CaptureTileService] maintains this flag from its own lifecycle
 * callbacks and [CaptureChannelHandler] reads it back for Dart.
 */
object TileState {
    private const val PREFS_NAME = "oshi_tile"
    private const val KEY_ADDED = "tile_added"

    fun setAdded(context: Context, added: Boolean) {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putBoolean(KEY_ADDED, added)
            .apply()
    }

    fun isAdded(context: Context): Boolean =
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getBoolean(KEY_ADDED, false)
}
