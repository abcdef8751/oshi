import 'dart:async';

import 'package:flutter/services.dart';

/// Error codes surfaced by the native side as `PlatformException.code`.
class CaptureErrorCodes {
  static const String secureWindow = 'SECURE_WINDOW';
  static const String noAccessibilityAccess = 'NO_ACCESSIBILITY_ACCESS';
  static const String intervalTimeShort = 'INTERVAL_TIME_SHORT';
  static const String internalError = 'INTERNAL_ERROR';
}

/// A capture handed over by the native trigger path (notification tap, QS
/// tile, in-app debug button).
class PendingCapture {
  const PendingCapture({this.path, this.error});

  /// Absolute path to a PNG in the app cache, or null when [error] is set.
  final String? path;

  /// One of [CaptureErrorCodes], or null on success.
  final String? error;

  bool get isEmpty => path == null && error == null;
}

/// Dart side of the `oshi/capture` method channel.
///
/// Non-final so widget tests can substitute a fake.
class CaptureChannel {
  CaptureChannel({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel('oshi/capture');

  final MethodChannel _channel;

  Future<bool> isAccessibilityEnabled() async {
    final result = await _channel.invokeMethod<bool>('isAccessibilityEnabled');
    return result ?? false;
  }

  Future<void> openAccessibilitySettings() =>
      _channel.invokeMethod<void>('openAccessibilitySettings');

  /// Captures the screen synchronously from Dart. Only used by the in-app
  /// debug button; the notification/tile path never goes through Dart.
  ///
  /// Throws [PlatformException] with a [CaptureErrorCodes] code on failure.
  Future<String> takeScreenshot() async {
    final path = await _channel.invokeMethod<String>('takeScreenshot');
    if (path == null) {
      throw PlatformException(
        code: CaptureErrorCodes.internalError,
        message: 'Capture returned no path',
      );
    }
    return path;
  }

  Future<void> postNotification() =>
      _channel.invokeMethod<void>('postNotification');

  Future<void> cancelNotification() =>
      _channel.invokeMethod<void>('cancelNotification');

  /// `StatusBarManager.isTileAdded` (API 33+); false on older versions or when
  /// the platform call fails.
  Future<bool> isTileAdded() async {
    try {
      final result = await _channel.invokeMethod<bool>('isTileAdded');
      return result ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<void> openTileSettings() =>
      _channel.invokeMethod<void>('openTileSettings');

  /// Pulls and clears the capture the native side is holding for us.
  ///
  /// The trigger activity writes the PNG to disk, starts [MainActivity], and
  /// parks the path in [CapturePending]. Dart drains it on start/resume.
  Future<PendingCapture> getPendingCapture() async {
    final result = await _channel.invokeMapMethod<String, dynamic>(
      'getPendingCapture',
    );
    if (result == null) return const PendingCapture();
    return PendingCapture(
      path: result['path'] as String?,
      error: result['error'] as String?,
    );
  }

  /// Whether the floating-overlay permission is granted.
  Future<bool> isOverlayPermitted() async {
    try {
      final result = await _channel.invokeMethod<bool>('isOverlayPermitted');
      return result ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Opens the system "Display over other apps" screen for this app.
  Future<void> openOverlaySettings() =>
      _channel.invokeMethod<void>('openOverlaySettings');

  /// Moves Oshi's task to the back, revealing whatever the user was doing
  /// before the capture. Used when a capture-triggered flow finishes so the
  /// overlay feels like a system tool rather than an app switch.
  Future<void> returnToPreviousApp() =>
      _channel.invokeMethod<void>('returnToPreviousApp');

  /// Fires when the native side wants us to drain [getPendingCapture].
  void setCaptureAvailableHandler(void Function() handler) {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onCaptureAvailable') handler();
      return null;
    });
  }
}
