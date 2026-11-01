import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oshi/app.dart';
import 'package:oshi/core/settings.dart';
import 'package:oshi/data/models.dart';
import 'package:oshi/native/capture_channel.dart';
import 'package:oshi/services/translator.dart';

class FakeCaptureChannel extends CaptureChannel {
  FakeCaptureChannel({
    this.accessibility = true,
    this.tileAdded = true,
    this.pending,
    this.screenshotPath,
  });

  bool accessibility;
  bool tileAdded;
  PendingCapture? pending;
  String? screenshotPath;
  int screenshots = 0;
  int posted = 0;
  int cancelled = 0;
  int openedSettings = 0;
  int returnedToPreviousApp = 0;
  void Function()? captureAvailable;

  @override
  Future<bool> isAccessibilityEnabled() async => accessibility;

  @override
  Future<bool> isTileAdded() async => tileAdded;

  @override
  Future<void> openAccessibilitySettings() async => openedSettings++;

  @override
  Future<void> postNotification() async => posted++;

  @override
  Future<void> cancelNotification() async => cancelled++;

  @override
  Future<void> openTileSettings() async {}

  @override
  Future<String> takeScreenshot() async {
    screenshots++;
    final path = screenshotPath;
    if (path == null) {
      throw PlatformException(code: CaptureErrorCodes.internalError);
    }
    return path;
  }

  @override
  Future<PendingCapture> getPendingCapture() async {
    final value = pending;
    pending = null;
    return value ?? const PendingCapture();
  }

  @override
  Future<void> returnToPreviousApp() async => returnedToPreviousApp++;

  @override
  void setCaptureAvailableHandler(void Function() handler) {
    captureAvailable = handler;
  }
}

class FakeTranslator implements Translator {
  FakeTranslator({
    this.result = const ScanResult(
      detectedLanguage: 'ja',
      originalText: 'こんにちは',
      translation: 'Hello',
    ),
  });

  final ScanResult result;
  int analyzeCalls = 0;
  int translateCalls = 0;

  @override
  Future<ScanResult> analyzeImage(
    Uint8List png, {
    required String targetCode,
    required String targetName,
  }) async {
    analyzeCalls++;
    return result;
  }

  @override
  Future<String> translateText(
    String originalText, {
    required String targetCode,
    required String targetName,
  }) async {
    translateCalls++;
    return '[$targetCode] $originalText';
  }
}

/// Generates a real PNG on disk through the engine.
Future<String> _writeTestPng(
  WidgetTester tester,
  Directory dir, {
  int width = 600,
  int height = 400,
}) async {
  final path = await tester.runAsync(() async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      Paint()..color = const Color(0xFFFFFFFF),
    );
    canvas.drawRect(
      Rect.fromLTWH(20, 20, width / 2, height / 3),
      Paint()..color = const Color(0xFF000000),
    );
    final picture = recorder.endRecording();
    final image = await picture.toImage(width, height);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    picture.dispose();
    final file = File('${dir.path}/shot.png');
    await file.writeAsBytes(bytes!.buffer.asUint8List(), flush: true);
    return file.path;
  });
  return path!;
}

/// Pumps real async work (file IO, image decode, HTTP-free futures) alongside
/// fake frames until [condition] is true.
Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  int attempts = 120,
}) async {
  for (var i = 0; i < attempts; i++) {
    if (condition()) return;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump(const Duration(milliseconds: 16));
  }
  fail('condition was not met after $attempts attempts');
}

Finder _filledButtonWithText(String text) => find.ancestor(
      of: find.text(text),
      matching: find.byWidgetPredicate((widget) => widget is FilledButton),
    );

bool _useEnabled(WidgetTester tester) {
  final finder = _filledButtonWithText('Use');
  if (finder.evaluate().isEmpty) return false;
  return (tester.widget(finder.first) as FilledButton).onPressed != null;
}

void main() {
  late Directory tempDir;
  late String shotPath;
  late List<MethodCall> clipboardCalls;

  setUp(() {
    clipboardCalls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') clipboardCalls.add(call);
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    tempDir = await Directory.systemTemp.createTemp('oshi_shell_test');
  });

  tearDownAll(() async {
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  Widget app({
    String apiKey = 'test-key',
    FakeCaptureChannel? channel,
    FakeTranslator? translator,
    bool noTranslator = false,
    Settings? settings,
  }) {
    return OshiApp(
      apiKey: apiKey,
      captureChannel: channel ?? FakeCaptureChannel(),
      translator: noTranslator ? null : (translator ?? FakeTranslator()),
      settings: settings ?? Settings.memory(),
    );
  }

  testWidgets('home shows readiness rows and the debug capture button',
      (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(find.text('Grab text from anywhere.'), findsOneWidget);
    expect(find.text('Accessibility service'), findsOneWidget);
    expect(find.text('Enabled'), findsOneWidget);
    expect(find.text('Quick Settings tile'), findsOneWidget);
    expect(find.text('Added'), findsOneWidget);
    expect(find.text('Gemini key'), findsOneWidget);
    expect(find.text('Loaded from .env'), findsOneWidget);
    expect(find.text('Capture now (debug)'), findsOneWidget);
  });

  testWidgets('missing API key disables capture and explains why',
      (tester) async {
    await tester.pumpWidget(app(apiKey: '', noTranslator: true));
    await tester.pumpAndSettle();

    final button = _filledButtonWithText('Capture now (debug)');
    expect(button, findsOneWidget);
    expect((tester.widget(button) as FilledButton).onPressed, isNull);
    expect(find.textContaining('No Gemini API key found'), findsOneWidget);
  });

  testWidgets('a disabled accessibility service offers the enable CTA',
      (tester) async {
    final channel = FakeCaptureChannel(accessibility: false);
    await tester.pumpWidget(app(channel: channel));
    await tester.pumpAndSettle();

    expect(find.text('Required for capture'), findsOneWidget);
    await tester.tap(find.text('Enable capture'));
    await tester.pumpAndSettle();
    expect(channel.openedSettings, 1);
  });

  testWidgets('a protected-window capture error surfaces as a snack bar',
      (tester) async {
    final channel = FakeCaptureChannel(
      pending: const PendingCapture(error: CaptureErrorCodes.secureWindow),
    );
    await tester.pumpWidget(app(channel: channel));
    await tester.pumpAndSettle();

    expect(
      find.text('This screen is protected (DRM / banking app)'),
      findsOneWidget,
    );
  });

  testWidgets('debug capture opens the crop screen and cancel returns home',
      (tester) async {
    shotPath = await _writeTestPng(tester, tempDir);
    final channel = FakeCaptureChannel(screenshotPath: shotPath);
    await tester.pumpWidget(app(channel: channel));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Capture now (debug)'));
    // The hint only renders once the frozen screenshot has decoded.
    await _pumpUntil(
      tester,
      () => find.text('Drag to select text').evaluate().isNotEmpty,
    );

    expect(channel.screenshots, 1);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('Grab text from anywhere.'), findsOneWidget);
  });

  testWidgets('notification callback pushes the crop screen while open',
      (tester) async {
    shotPath = await _writeTestPng(tester, tempDir);
    final channel = FakeCaptureChannel();
    await tester.pumpWidget(app(channel: channel));
    await tester.pumpAndSettle();

    // The notification/tile path: native queues a capture and invokes the
    // channel callback, which must drain and open the overlay.
    channel.pending = PendingCapture(path: shotPath);
    channel.captureAvailable!();

    await _pumpUntil(
      tester,
      () => find.text('Drag to select text').evaluate().isNotEmpty,
    );
    expect(find.text('Drag to select text'), findsOneWidget);
  });

  testWidgets('a second capture during the crop screen is not dropped',
      (tester) async {
    shotPath = await _writeTestPng(tester, tempDir);
    final channel = FakeCaptureChannel();
    await tester.pumpWidget(app(channel: channel));
    await tester.pumpAndSettle();

    channel.pending = PendingCapture(path: shotPath);
    channel.captureAvailable!();
    await _pumpUntil(
      tester,
      () => find.text('Drag to select text').evaluate().isNotEmpty,
    );

    // Second tap while the first crop is still on screen.
    channel.pending = PendingCapture(path: shotPath);
    channel.captureAvailable!();
    await tester.pump(const Duration(milliseconds: 300));

    // Cancelling the first one lets the queued capture through.
    await tester.tap(find.text('Cancel'));
    await _pumpUntil(
      tester,
      () => find.text('Drag to select text').evaluate().isNotEmpty,
    );
    expect(find.text('Drag to select text'), findsOneWidget);
  });

  testWidgets('finishing a capture flow returns to the previous app',
      (tester) async {
    shotPath = await _writeTestPng(tester, tempDir);
    final channel = FakeCaptureChannel(pending: PendingCapture(path: shotPath));
    await tester.pumpWidget(app(channel: channel));

    await _pumpUntil(
      tester,
      () => find.text('Drag to select text').evaluate().isNotEmpty,
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(channel.returnedToPreviousApp, 1);
    // Oshi's own home screen is what is shown before the task goes back.
    expect(find.text('Grab text from anywhere.'), findsOneWidget);
  });

  testWidgets('the debug button does not bounce the user out of Oshi',
      (tester) async {
    shotPath = await _writeTestPng(tester, tempDir);
    final channel = FakeCaptureChannel(screenshotPath: shotPath);
    await tester.pumpWidget(app(channel: channel));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Capture now (debug)'));
    await _pumpUntil(
      tester,
      () => find.text('Drag to select text').evaluate().isNotEmpty,
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(channel.returnedToPreviousApp, 0);
  });

  testWidgets('the ongoing notification is posted on launch when enabled',
      (tester) async {
    final channel = FakeCaptureChannel();
    await tester.pumpWidget(app(channel: channel));
    await tester.pumpAndSettle();
    expect(channel.posted, 1);
  });

  testWidgets('the ongoing notification is not posted when disabled',
      (tester) async {
    final channel = FakeCaptureChannel();
    await tester.pumpWidget(
      app(channel: channel, settings: Settings.memory(notificationEnabled: false)),
    );
    await tester.pumpAndSettle();
    expect(channel.posted, 0);
  });

  testWidgets('pending capture -> crop -> default selection -> result sheet',
      (tester) async {
    shotPath = await _writeTestPng(tester, tempDir);
    final translator = FakeTranslator();
    final channel = FakeCaptureChannel(pending: PendingCapture(path: shotPath));
    await tester.pumpWidget(app(channel: channel, translator: translator));

    await _pumpUntil(
      tester,
      () => find.text('Drag to select text').evaluate().isNotEmpty,
    );
    // Wait for the file decode so the default selection becomes usable.
    await _pumpUntil(tester, () => _useEnabled(tester));

    await tester.tap(find.text('Use'));
    // The transcription is shown first; the translation is one tap away.
    await _pumpUntil(tester, () => find.text('こんにちは').evaluate().isNotEmpty);
    // Let the modal sheet finish sliding in before tapping its actions.
    await tester.pump(const Duration(milliseconds: 500));

    expect(translator.analyzeCalls, 1);
    expect(find.textContaining('detected:'), findsOneWidget);

    // Copying confirms inline and leaves the sheet open.
    await tester.tap(find.text('Copy'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(clipboardCalls, hasLength(1));
    expect(
      (clipboardCalls.single.arguments as Map<String, dynamic>)['text'],
      'こんにちは',
    );
    expect(find.text('Copied'), findsOneWidget);
    expect(find.text('こんにちは'), findsOneWidget);

    // Toggling shows the translation without leaving the sheet.
    await tester.tap(find.text('Translation'));
    await tester.pump();
    expect(find.text('Hello'), findsOneWidget);
  });
}
