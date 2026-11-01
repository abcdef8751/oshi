import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oshi/core/languages.dart';
import 'package:oshi/core/theme.dart';
import 'package:oshi/features/result/language_bar.dart';

Widget _app(Widget child) => MaterialApp(
  theme: AppTheme.dark(),
  home: Scaffold(
    body: Align(alignment: Alignment.bottomCenter, child: child),
  ),
);

void main() {
  testWidgets('renders a locked Auto source and the current target', (
    tester,
  ) async {
    final target = ValueNotifier<AppLanguage>(kEnglish);

    await tester.pumpWidget(
      _app(LanguageBar(targetLanguage: target, onRetranslate: () {})),
    );

    expect(find.text('Auto'), findsOneWidget);
    expect(find.text('English'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('language-bar-auto')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('language-bar-target')),
      findsOneWidget,
    );
  });

  testWidgets('tapping the target opens the picker and updates the notifier', (
    tester,
  ) async {
    final target = ValueNotifier<AppLanguage>(kEnglish);

    await tester.pumpWidget(
      _app(LanguageBar(targetLanguage: target, onRetranslate: () {})),
    );

    await tester.tap(find.byKey(const ValueKey<String>('language-bar-target')));
    await tester.pumpAndSettle();

    expect(find.text('Translate to'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('language-ja')));
    await tester.pumpAndSettle();

    expect(target.value.code, 'ja');
    expect(target.value.name, 'Japanese');
    expect(find.text('Japanese'), findsOneWidget);
    expect(find.text('日本語'), findsOneWidget);
  });

  testWidgets('reload icon invokes onRetranslate', (tester) async {
    final target = ValueNotifier<AppLanguage>(kEnglish);
    var reloads = 0;

    await tester.pumpWidget(
      _app(LanguageBar(targetLanguage: target, onRetranslate: () => reloads++)),
    );

    await tester.tap(find.byKey(const ValueKey<String>('language-bar-reload')));
    await tester.pump();

    expect(reloads, 1);
  });

  testWidgets('busy shows a thin progress indicator without hiding the bar', (
    tester,
  ) async {
    final target = ValueNotifier<AppLanguage>(kEnglish);

    await tester.pumpWidget(
      _app(
        LanguageBar(targetLanguage: target, onRetranslate: () {}, busy: true),
      ),
    );

    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.text('English'), findsOneWidget);
    expect(find.text('Auto'), findsOneWidget);
  });
}
