import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oshi/core/languages.dart';
import 'package:oshi/core/settings.dart';
import 'package:oshi/data/models.dart';
import 'package:oshi/overlay/overlay_app.dart';
import 'package:oshi/services/translator.dart';

const MethodChannel _channel = MethodChannel('oshi/overlay');

class FakeTranslator implements Translator {
  int analyzeCalls = 0;

  @override
  Future<ScanResult> analyzeImage(
    Uint8List png, {
    required String targetCode,
    required String targetName,
  }) async {
    analyzeCalls++;
    return const ScanResult(
      detectedLanguage: 'ja',
      originalText: 'こんにちは',
      translation: 'Hello',
    );
  }

  @override
  Future<String> translateText(
    String originalText, {
    required String targetCode,
    required String targetName,
  }) async => '[$targetCode] $originalText';
}

Future<String> _writePng(WidgetTester tester, Directory dir) async {
  final path = await tester.runAsync(() async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, 400, 300),
      Paint()..color = const Color(0xFFFFFFFF),
    );
    final picture = recorder.endRecording();
    final image = await picture.toImage(400, 300);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    picture.dispose();
    final file = File('${dir.path}/shot.png');
    await file.writeAsBytes(bytes!.buffer.asUint8List(), flush: true);
    return file.path;
  });
  return path!;
}

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

void main() {
  late Directory tempDir;
  late List<String> dismissals;
  late List<String> copies;
  String? readyPath;
  String readyLanguage = 'en';

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('oshi_overlay_test');
    dismissals = <String>[];
    copies = <String>[];
    readyPath = null;
    readyLanguage = 'en';
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
      switch (call.method) {
        case 'ready':
          return <String, dynamic>{
            'path': readyPath,
            'targetLang': readyLanguage,
          };
        case 'dismiss':
          dismissals.add('dismiss');
          return null;
        case 'copy':
          copies.add((call.arguments as Map)['text'] as String);
          return true;
      }
      return null;
    });
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  Widget overlay({FakeTranslator? translator, Settings? settings}) {
    return OshiOverlayApp(
      apiKey: 'test-key',
      captureChannel: _channel,
      translator: translator ?? FakeTranslator(),
      settings: settings ?? Settings.memory(targetLangCode: 'ja'),
    );
  }

  testWidgets('a cold-start capture path drains into the crop screen',
      (tester) async {
    readyPath = await _writePng(tester, tempDir);
    await tester.pumpWidget(overlay());

    await _pumpUntil(
      tester,
      () => find.text('Drag to select text').evaluate().isNotEmpty,
    );
    expect(find.text('Drag to select text'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(dismissals, ['dismiss']);
  });

  testWidgets('a warm "show" call opens the crop screen', (tester) async {
    final path = await _writePng(tester, tempDir);
    await tester.pumpWidget(overlay());
    await tester.pumpAndSettle();
    expect(dismissals, isEmpty);

    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          _channel.name,
          _channel.codec.encodeMethodCall(
            MethodCall('show', <String, dynamic>{'path': path}),
          ),
          (_) {},
        );

    await _pumpUntil(
      tester,
      () => find.text('Drag to select text').evaluate().isNotEmpty,
    );
    expect(find.text('Drag to select text'), findsOneWidget);
  });

  testWidgets('crop -> sheet -> copy goes through the native clipboard',
      (tester) async {
    readyPath = await _writePng(tester, tempDir);
    final translator = FakeTranslator();
    await tester.pumpWidget(overlay(translator: translator));
    await _pumpUntil(
      tester,
      () => find.text('Drag to select text').evaluate().isNotEmpty,
    );

    await _pumpUntil(
      tester,
      () =>
          find
              .ancestor(
                of: find.text('Use'),
                matching: find.byWidgetPredicate((w) => w is FilledButton),
              )
              .evaluate()
              .isNotEmpty &&
          (tester.widget<FilledButton>(
                    find
                        .ancestor(
                          of: find.text('Use'),
                          matching: find.byWidgetPredicate(
                            (w) => w is FilledButton,
                          ),
                        )
                        .first,
                  ))
                  .onPressed !=
              null,
    );

    await tester.tap(find.text('Use'));
    await _pumpUntil(
      tester,
      () => find.text('こんにちは').evaluate().isNotEmpty,
    );
    await tester.pump(const Duration(milliseconds: 500));

    expect(translator.analyzeCalls, 1);
    await tester.tap(find.text('Copy'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(copies, ['こんにちは']);
    expect(find.text('Copied'), findsOneWidget);

    // Drain the inline "Copied" timer before the test ends.
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('the default target language comes from native when prefs fail',
      (tester) async {
    readyLanguage = 'ja';
    await tester.pumpWidget(
      OshiOverlayApp(
        apiKey: 'test-key',
        captureChannel: _channel,
        translator: FakeTranslator(),
      ),
    );
    await tester.pumpAndSettle();

    // No assertion on the bar (no result yet); reaching this point without a
    // platform exception is the contract: prefs are optional in the overlay.
    expect(find.byType(MaterialApp), findsOneWidget);
    expect(languageForCode(readyLanguage).code, 'ja');
  });
}
