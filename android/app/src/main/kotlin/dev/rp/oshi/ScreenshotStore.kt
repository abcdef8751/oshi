package dev.rp.oshi

import android.graphics.Bitmap
import java.io.File
import java.io.FileOutputStream
import java.io.IOException

/**
 * Writes captures to the app cache so the Flutter engine can read them back.
 *
 * The trigger path hands a file path to [MainActivity] instead of a bitmap
 * because an activity started from SystemUI cannot return a value.
 */
object ScreenshotStore {
    private const val CAPTURE_DIR = "captures"
    private const val LATEST_FILE_NAME = "latest.png"

    /** `cacheDir/captures/latest.png`, whether or not it exists yet. */
    fun latestFile(cacheDir: File): File = File(File(cacheDir, CAPTURE_DIR), LATEST_FILE_NAME)

    /**
     * Compresses [bitmap] to PNG (quality 100) and atomically replaces the
     * previous capture. The bitmap itself is not recycled here; the caller owns
     * its lifetime.
     *
     * @return the file that now holds the capture.
     */
    @Throws(IOException::class)
    fun writeLatest(cacheDir: File, bitmap: Bitmap): File {
        val dir = File(cacheDir, CAPTURE_DIR)
        if (!dir.isDirectory && !dir.mkdirs()) {
            throw IOException("Could not create capture directory: $dir")
        }
        val target = File(dir, LATEST_FILE_NAME)
        val temp = File(dir, "$LATEST_FILE_NAME.tmp")
        try {
            FileOutputStream(temp).use { out ->
                if (!bitmap.compress(Bitmap.CompressFormat.PNG, 100, out)) {
                    throw IOException("PNG compression failed")
                }
                out.flush()
            }
            if (!temp.renameTo(target)) {
                throw IOException("Could not replace $target")
            }
        } finally {
            temp.delete()
        }
        return target
    }
}
