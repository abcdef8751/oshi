package dev.rp.oshi

/**
 * Native mirror of Dart's `CaptureErrorCodes`. These strings are part of the
 * frozen `oshi/capture` contract and must match exactly.
 */
internal object CaptureErrorCodes {
    const val SECURE_WINDOW = "SECURE_WINDOW"
    const val NO_ACCESSIBILITY_ACCESS = "NO_ACCESSIBILITY_ACCESS"
    const val INTERVAL_TIME_SHORT = "INTERVAL_TIME_SHORT"
    const val INTERNAL_ERROR = "INTERNAL_ERROR"
}
