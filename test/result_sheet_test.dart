import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oshi/core/languages.dart';
import 'package:oshi/core/theme.dart';
import 'package:oshi/data/models.dart';
import 'package:oshi/features/result/result_sheet.dart';
import 'package:oshi/services/translator.dart';

import 'result_fake_translator.dart';

const ScanResult _result = ScanResult(
  detectedLanguage: 'es',
  originalText: 'Hola mundo',
  translation: 'Hello world',
);

Widget _app(Widget child) => MaterialApp(
  theme: AppTheme.dark(),
  home: Scaffold(body: child),
);

String _shownText(WidgetTester tester) {
  final selectable = tester.widget<SelectableText>(find.byType(SelectableText));
  return selectable.data ?? '';
}

void main() {
  testWidgets('initialResult renders immediately without calling analyze', (
    tester,
  ) async {
    final translator = FakeTranslator();

    await tester.pumpWidget(
      _app(
        ResultSheet(
          translator: translator,
          targetLanguage: ValueNotifier<AppLanguage>(kEnglish),
          initialResult: _result,
        ),
      ),
    );
    await tester.pump();

    expect(translator.analyzeCalls, 0);
    expect(translator.translateCalls, 0);
    expect(_shownText(tester), 'Hello world');
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets(
    'analyze path calls analyzeImage once, renders it and fires onResult',
    (tester) async {
      final translator = FakeTranslator(
        analyzeResult: _result,
        analyzeDelay: const Duration(milliseconds: 50),
      );
      final target = ValueNotifier<AppLanguage>(kEnglish);
      ScanResult? reported;

      await tester.pumpWidget(
        _app(
          ResultSheet(
            translator: translator,
            targetLanguage: target,
            imagePng: Uint8List.fromList(<int>[1, 2, 3]),
            onResult: (result) => reported = result,
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(translator.analyzeCalls, 1);

      await tester.pump(const Duration(milliseconds: 50));
      await tester.pumpAndSettle();

      expect(translator.analyzeCalls, 1);
      expect(translator.analyzeTargetCodes.single, 'en');
      expect(translator.lastPng, Uint8List.fromList(<int>[1, 2, 3]));
      expect(_shownText(tester), 'Hello world');
      expect(reported, same(_result));
      expect(find.byType(CircularProgressIndicator), findsNothing);
    },
  );

  testWidgets('toggle flips between the translation and the original', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        ResultSheet(
          translator: FakeTranslator(),
          targetLanguage: ValueNotifier<AppLanguage>(kEnglish),
          initialResult: _result,
        ),
      ),
    );
    await tester.pump();

    expect(_shownText(tester), 'Hello world');
    expect(find.text('Original'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('result-toggle')));
    await tester.pump();

    expect(_shownText(tester), 'Hola mundo');
    expect(find.text('Translation'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('result-toggle')));
    await tester.pump();

    expect(_shownText(tester), 'Hello world');
    expect(find.text('Original'), findsOneWidget);
  });

  testWidgets('toggle is absent when the translation equals the original', (
    tester,
  ) async {
    const identical = ScanResult(
      detectedLanguage: 'en',
      originalText: 'Same text',
      translation: 'Same text',
    );

    await tester.pumpWidget(
      _app(
        ResultSheet(
          translator: FakeTranslator(),
          targetLanguage: ValueNotifier<AppLanguage>(kEnglish),
          initialResult: identical,
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const ValueKey<String>('result-toggle')), findsNothing);
    expect(find.text('Original'), findsNothing);
    expect(_shownText(tester), 'Same text');
  });

  testWidgets(
    'copy sends the currently shown variant and keeps the sheet open',
    (tester) async {
      final calls = <MethodCall>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') calls.add(call);
        return null;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
      );

      await tester.pumpWidget(
        _app(
          ResultSheet(
            translator: FakeTranslator(),
            targetLanguage: ValueNotifier<AppLanguage>(kEnglish),
            initialResult: _result,
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey<String>('result-copy')));
      await tester.pump();

      expect(calls, hasLength(1));
      expect(
        (calls.single.arguments as Map<String, dynamic>)['text'],
        'Hello world',
      );

      await tester.tap(find.byKey(const ValueKey<String>('result-toggle')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey<String>('result-copy')));
      await tester.pump();

      expect(calls, hasLength(2));
      expect(
        (calls.last.arguments as Map<String, dynamic>)['text'],
        'Hola mundo',
      );
      expect(find.byType(ResultSheet), findsOneWidget);
    },
  );

  testWidgets('initial analyze failure shows Retry and succeeds on retry', (
    tester,
  ) async {
    final translator = FakeTranslator(
      analyzeError: const TranslatorException(
        TranslatorErrorKind.network,
        'offline',
      ),
    );

    await tester.pumpWidget(
      _app(
        ResultSheet(
          translator: translator,
          targetLanguage: ValueNotifier<AppLanguage>(kEnglish),
          imagePng: Uint8List.fromList(<int>[9, 9, 9]),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(translator.analyzeCalls, 1);
    expect(find.text('No connection'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('result-analyze-retry')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('result-analyze-close')),
      findsOneWidget,
    );
    expect(find.byType(SelectableText), findsNothing);

    translator.analyzeError = null;
    translator.analyzeResult = _result;

    await tester.tap(
      find.byKey(const ValueKey<String>('result-analyze-retry')),
    );
    await tester.pumpAndSettle();

    expect(translator.analyzeCalls, 2);
    expect(find.text('No connection'), findsNothing);
    expect(_shownText(tester), 'Hello world');
  });

  testWidgets('target change retranslates once and caches by language', (
    tester,
  ) async {
    final translator = FakeTranslator(
      translateHandler: (text, code) => '[$code] $text',
    );
    final target = ValueNotifier<AppLanguage>(kEnglish);

    await tester.pumpWidget(
      _app(
        ResultSheet(
          translator: translator,
          targetLanguage: target,
          initialResult: _result,
        ),
      ),
    );
    await tester.pump();

    target.value = kLanguages[1]; // Japanese
    await tester.pumpAndSettle();

    expect(translator.translateCalls, 1);
    expect(translator.translateTargetCodes.single, 'ja');
    expect(translator.translateTexts.single, 'Hola mundo');
    expect(_shownText(tester), '[ja] Hola mundo');

    // Back to the cached English translation: no second network call.
    target.value = kLanguages[0];
    await tester.pumpAndSettle();

    expect(translator.translateCalls, 1);
    expect(_shownText(tester), 'Hello world');
  });

  testWidgets('retranslate keeps the currently shown variant', (tester) async {
    final translator = FakeTranslator(
      translateHandler: (text, code) => '[$code] $text',
    );
    final target = ValueNotifier<AppLanguage>(kEnglish);

    await tester.pumpWidget(
      _app(
        ResultSheet(
          translator: translator,
          targetLanguage: target,
          initialResult: _result,
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey<String>('result-toggle')));
    await tester.pump();
    expect(_shownText(tester), 'Hola mundo');

    target.value = kLanguages[1];
    await tester.pumpAndSettle();

    // Still showing the original variant after the retranslation lands.
    expect(_shownText(tester), 'Hola mundo');
    expect(translator.translateCalls, 1);

    await tester.tap(find.byKey(const ValueKey<String>('result-toggle')));
    await tester.pump();
    expect(_shownText(tester), '[ja] Hola mundo');
  });

  testWidgets(
    'retranslate shows a thin progress bar without blanking the text',
    (tester) async {
      final translator = FakeTranslator(
        translateDelay: const Duration(milliseconds: 50),
        translateHandler: (text, code) => '[$code] $text',
      );
      final target = ValueNotifier<AppLanguage>(kEnglish);

      await tester.pumpWidget(
        _app(
          ResultSheet(
            translator: translator,
            targetLanguage: target,
            initialResult: _result,
          ),
        ),
      );
      await tester.pump();

      target.value = kLanguages[1];
      await tester.pump();

      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(_shownText(tester), 'Hello world');

      await tester.pump(const Duration(milliseconds: 50));
      await tester.pumpAndSettle();

      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(_shownText(tester), '[ja] Hola mundo');
    },
  );

  testWidgets('retranslate errors render inline and keep the old text', (
    tester,
  ) async {
    final translator = FakeTranslator(
      translateError: const TranslatorException(
        TranslatorErrorKind.server,
        'upstream',
      ),
    );
    final target = ValueNotifier<AppLanguage>(kEnglish);

    await tester.pumpWidget(
      _app(
        ResultSheet(
          translator: translator,
          targetLanguage: target,
          initialResult: _result,
        ),
      ),
    );
    await tester.pump();

    target.value = kLanguages[1];
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('result-retranslate-error')),
      findsOneWidget,
    );
    expect(find.text('Gemini is having trouble'), findsOneWidget);
    expect(_shownText(tester), 'Hello world');

    translator.translateError = null;
    translator.translateHandler = (text, code) => '[$code] $text';

    await tester.tap(
      find.byKey(const ValueKey<String>('result-retranslate-retry')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('result-retranslate-error')),
      findsNothing,
    );
    expect(_shownText(tester), '[ja] Hola mundo');
  });

  testWidgets('showResultSheet opens the modal sheet with a cached result', (
    tester,
  ) async {
    final translator = FakeTranslator();
    final target = ValueNotifier<AppLanguage>(kEnglish);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: FilledButton(
                onPressed: () {
                  showResultSheet(
                    context,
                    translator: translator,
                    targetLanguage: target,
                    initialResult: _result,
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.byType(ResultSheet), findsOneWidget);
    expect(_shownText(tester), 'Hello world');
    expect(translator.analyzeCalls, 0);
  });
}
