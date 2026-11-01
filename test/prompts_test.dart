import 'package:flutter_test/flutter_test.dart';
import 'package:oshi/data/prompts.dart';

void main() {
  group('buildAnalyzePrompt', () {
    test('interpolates the target name and code', () {
      final prompt = buildAnalyzePrompt(
        targetName: 'Japanese',
        targetCode: 'ja',
      );

      expect(prompt, contains('Japanese (ja)'));
      expect(prompt, contains('If the text is already in Japanese'));
      expect(prompt, isNot(contains('<TARGET_NAME>')));
      expect(prompt, isNot(contains('<TARGET_CODE>')));
    });

    test('matches the contract text', () {
      expect(
        buildAnalyzePrompt(targetName: 'Japanese', targetCode: 'ja'),
        'You are an OCR + translation engine.\n'
        '1. Transcribe every character visible in the image exactly, preserving line breaks.\n'
        '   Do not summarize, correct, or add anything. Join hyphenated line breaks only when\n'
        '   the text is a single sentence.\n'
        '2. Identify the primary language as a BCP-47 code (e.g. "ja", "zh-Hans", "en").\n'
        '3. Translate the transcription into Japanese (ja).\n'
        '   - If the text is already in Japanese, return the transcription as the translation.\n'
        '   - Keep names, numbers, and formatting; do not add commentary.',
      );
    });

    test('asks for verbatim OCR, BCP-47 and no commentary', () {
      final prompt = buildAnalyzePrompt(targetName: 'German', targetCode: 'de');

      expect(prompt, contains('preserving line breaks'));
      expect(prompt, contains('Join hyphenated line breaks'));
      expect(prompt, contains('BCP-47'));
      expect(prompt, contains('Keep names, numbers, and formatting'));
      expect(prompt.toLowerCase(), contains('do not add commentary'));
      expect(prompt.toLowerCase(), isNot(contains('summarize the text')));
    });
  });

  group('buildTranslatePrompt', () {
    test('interpolates the target and asks for translation only', () {
      final prompt = buildTranslatePrompt(
        targetName: 'French',
        targetCode: 'fr',
      );

      expect(prompt, contains('French (fr)'));
      expect(prompt, contains('Output only the translation'));
      expect(prompt, isNot(contains('<TARGET_NAME>')));
      expect(prompt, isNot(contains('<TARGET_CODE>')));
    });

    test('does not ask for JSON or an image', () {
      final prompt = buildTranslatePrompt(
        targetName: 'French',
        targetCode: 'fr',
      );

      expect(prompt.toLowerCase(), isNot(contains('json')));
      expect(prompt.toLowerCase(), isNot(contains('image')));
    });
  });

  group('kAnalyzeResponseSchema', () {
    test('is an OBJECT with the three required string fields', () {
      expect(kAnalyzeResponseSchema['type'], 'OBJECT');

      final properties =
          kAnalyzeResponseSchema['properties'] as Map<String, dynamic>;
      expect(properties.keys.toSet(), {
        'detected_language',
        'original_text',
        'translation',
      });
      for (final property in properties.values) {
        expect((property as Map<String, dynamic>)['type'], 'STRING');
      }

      expect((kAnalyzeResponseSchema['required'] as List).toSet(), {
        'detected_language',
        'original_text',
        'translation',
      });
    });
  });
}
