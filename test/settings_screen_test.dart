import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:oshi/core/settings.dart';
import 'package:oshi/core/theme.dart';
import 'package:oshi/features/settings/settings_screen.dart';
import 'package:oshi/native/capture_channel.dart';

/// Method-channel-free stand-in that records every call.
class FakeCaptureChannel extends CaptureChannel {
  FakeCaptureChannel({
    this.accessibilityEnabled = false,
    this.tileAdded = false,
    this.throwOnPost = false,
    this.throwOnCancel = false,
    this.throwOnAccessibilityQuery = false,
  });

  bool accessibilityEnabled;
  bool tileAdded;
  bool throwOnPost;
  bool throwOnCancel;
  bool throwOnAccessibilityQuery;

  int accessibilityQueryCount = 0;
  int openAccessibilitySettingsCount = 0;
  int takeScreenshotCount = 0;
  int postNotificationCount = 0;
  int cancelNotificationCount = 0;
  int tileQueryCount = 0;
  int openTileSettingsCount = 0;
  int getPendingCaptureCount = 0;
  int setCaptureAvailableHandlerCount = 0;

  @override
  Future<bool> isAccessibilityEnabled() async {
    accessibilityQueryCount++;
    if (throwOnAccessibilityQuery) {
      throw PlatformException(code: CaptureErrorCodes.internalError);
    }
    return accessibilityEnabled;
  }

  @override
  Future<void> openAccessibilitySettings() async {
    openAccessibilitySettingsCount++;
  }

  @override
  Future<String> takeScreenshot() async {
    takeScreenshotCount++;
    return '/tmp/captures/latest.png';
  }

  @override
  Future<void> postNotification() async {
    postNotificationCount++;
    if (throwOnPost) {
      throw PlatformException(code: CaptureErrorCodes.internalError);
    }
  }

  @override
  Future<void> cancelNotification() async {
    cancelNotificationCount++;
    if (throwOnCancel) {
      throw PlatformException(code: CaptureErrorCodes.internalError);
    }
  }

  @override
  Future<bool> isTileAdded() async {
    tileQueryCount++;
    return tileAdded;
  }

  @override
  Future<void> openTileSettings() async {
    openTileSettingsCount++;
  }

  @override
  Future<PendingCapture> getPendingCapture() async {
    getPendingCaptureCount++;
    return const PendingCapture();
  }

  @override
  void setCaptureAvailableHandler(void Function() handler) {
    setCaptureAvailableHandlerCount++;
  }
}

Future<Settings> pumpSettingsScreen(
  WidgetTester tester,
  FakeCaptureChannel channel, {
  Settings? settings,
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final resolved = settings ?? Settings.memory();
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark(),
      home: SettingsScreen(settings: resolved, captureChannel: channel),
    ),
  );
  await tester.pumpAndSettle();
  return resolved;
}

void main() {
  testWidgets('disabled accessibility shows Enable capture and opens settings',
      (tester) async {
    final channel = FakeCaptureChannel(
      accessibilityEnabled: false,
      tileAdded: true,
    );
    await pumpSettingsScreen(tester, channel);

    expect(find.text('Accessibility service'), findsOneWidget);
    expect(find.text('Required to take screenshots'), findsOneWidget);
    expect(find.text('Enable capture'), findsOneWidget);

    await tester.tap(find.text('Enable capture'));
    await tester.pumpAndSettle();

    expect(channel.openAccessibilitySettingsCount, 1);
  });

  testWidgets('enabled accessibility shows Enabled and no enable button',
      (tester) async {
    final channel = FakeCaptureChannel(
      accessibilityEnabled: true,
      tileAdded: true,
    );
    await pumpSettingsScreen(tester, channel);

    expect(find.text('Enabled'), findsOneWidget);
    expect(find.text('Enable capture'), findsNothing);
    expect(find.byIcon(Icons.check_circle), findsNWidgets(2));
  });

  testWidgets('tile card opens tile settings and remembers the prompt',
      (tester) async {
    final channel = FakeCaptureChannel(
      accessibilityEnabled: true,
      tileAdded: false,
    );
    final settings = await pumpSettingsScreen(tester, channel);

    expect(settings.tilePromptShown, isFalse);
    expect(find.text('Add the Quick Settings tile'), findsOneWidget);

    await tester.tap(find.text('Add tile'));
    await tester.pumpAndSettle();

    expect(channel.openTileSettingsCount, 1);
    expect(settings.tilePromptShown, isTrue);
    // The highlighted prompt gives way to the quiet "not added" row.
    expect(find.text('Add the Quick Settings tile'), findsNothing);
    expect(find.text('Quick Settings tile — Not added'), findsOneWidget);
  });

  testWidgets('language picker updates the stored target language',
      (tester) async {
    final channel = FakeCaptureChannel(
      accessibilityEnabled: true,
      tileAdded: true,
    );
    final settings = await pumpSettingsScreen(tester, channel);
    expect(settings.targetLangCode, 'en');

    await tester.tap(find.text('Default target language'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('language-option-ja')));
    await tester.pumpAndSettle();

    expect(settings.targetLangCode, 'ja');
    expect(find.text('Japanese · 日本語'), findsOneWidget);
  });

  testWidgets('toggling the notification off cancels and persists',
      (tester) async {
    final channel = FakeCaptureChannel(
      accessibilityEnabled: true,
      tileAdded: true,
    );
    final settings = await pumpSettingsScreen(
      tester,
      channel,
      settings: Settings.memory(notificationEnabled: true),
    );

    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();

    expect(channel.cancelNotificationCount, 1);
    expect(channel.postNotificationCount, 0);
    expect(settings.notificationEnabled, isFalse);
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
      isFalse,
    );
  });

  testWidgets('failed postNotification keeps switch off and shows a SnackBar',
      (tester) async {
    final channel = FakeCaptureChannel(
      accessibilityEnabled: true,
      tileAdded: true,
      throwOnPost: true,
    );
    final settings = await pumpSettingsScreen(
      tester,
      channel,
      settings: Settings.memory(notificationEnabled: false),
    );

    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();

    expect(channel.postNotificationCount, 1);
    expect(channel.cancelNotificationCount, 0);
    expect(settings.notificationEnabled, isFalse);
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
      isFalse,
    );
    expect(find.text('Could not update the notification'), findsOneWidget);
  });

  testWidgets('failed accessibility query degrades to Unknown', (tester) async {
    final channel = FakeCaptureChannel(
      throwOnAccessibilityQuery: true,
      tileAdded: true,
    );
    await pumpSettingsScreen(tester, channel);

    expect(find.text('Unknown'), findsOneWidget);
    expect(find.text('Enable capture'), findsOneWidget);
  });
}
