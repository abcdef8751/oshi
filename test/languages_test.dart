import 'package:flutter_test/flutter_test.dart';
import 'package:oshi/core/languages.dart';

void main() {
  test('languageForCode resolves exact codes', () {
    expect(languageForCode('ja').name, 'Japanese');
    expect(languageForCode('zh-Hans').nativeName, '简体中文');
  });

  test('languageForCode maps the common regional Chinese variants', () {
    expect(languageForCode('zh-CN').code, 'zh-Hans');
    expect(languageForCode('zh_CN').code, 'zh-Hans');
    expect(languageForCode('zh-TW').code, 'zh-Hant');
    expect(languageForCode('zh-HK').code, 'zh-Hant');
    expect(languageForCode('pt-BR').code, 'pt');
    expect(languageForCode('ja-JP').code, 'ja');
  });

  test('unknown and null codes fall back to English', () {
    expect(languageForCode(null), kEnglish);
    expect(languageForCode(''), kEnglish);
    expect(languageForCode('xx-YY'), kEnglish);
  });

  test('detectedLanguageLabel renders endonyms and tolerates variants', () {
    expect(detectedLanguageLabel('ja'), '日本語');
    expect(detectedLanguageLabel('zh-CN'), '简体中文');
    expect(detectedLanguageLabel('zh-TW'), '繁體中文');
    expect(detectedLanguageLabel('und'), 'UND');
    expect(detectedLanguageLabel(''), '?');
  });

  test('the list has unique codes and starts with English', () {
    expect(kLanguages.first, kEnglish);
    expect(
      kLanguages.map((language) => language.code).toSet().length,
      kLanguages.length,
    );
  });
}
