import 'package:flutter_test/flutter_test.dart';
import 'package:oshi/data/models.dart';

void main() {
  group('ScanResult.fromJson', () {
    test('reads the three fields', () {
      final result = ScanResult.fromJson(const <String, dynamic>{
        'detected_language': ' ja ',
        'original_text': 'こんにちは',
        'translation': 'Hello',
      });
      expect(result.detectedLanguage, 'ja');
      expect(result.originalText, 'こんにちは');
      expect(result.translation, 'Hello');
    });

    test('tolerates missing or wrongly typed fields without throwing', () {
      final result = ScanResult.fromJson(const <String, dynamic>{
        'detected_language': 42,
        'original_text': null,
      });
      expect(result.detectedLanguage, '');
      expect(result.originalText, '');
      expect(result.translation, '');
      expect(result.isTranslationIdentical, isTrue);
    });

    test('round-trips through toJson', () {
      const result = ScanResult(
        detectedLanguage: 'zh-Hans',
        originalText: '你好\n世界',
        translation: 'Hello\nworld',
      );
      expect(ScanResult.fromJson(result.toJson()).toJson(), result.toJson());
    });
  });

  test('withTranslation keeps language and original text', () {
    const result = ScanResult(
      detectedLanguage: 'ja',
      originalText: 'a',
      translation: 'b',
    );
    expect(result.withTranslation('c').translation, 'c');
    expect(result.withTranslation('c').originalText, 'a');
    expect(result.withTranslation('c').detectedLanguage, 'ja');
  });
}
