/// One Gemini analyze call: transcription, detected language, translation.
///
/// Immutable and JSON-serialisable so it can be cached for the session and
/// round-tripped in tests.
class ScanResult {
  const ScanResult({
    required this.detectedLanguage,
    required this.originalText,
    required this.translation,
  });

  /// BCP-47 code reported by the model, e.g. `ja`, `zh-Hans`.
  final String detectedLanguage;

  /// Exact transcription of the captured region.
  final String originalText;

  /// Translation of [originalText] into the requested target language.
  final String translation;

  /// True when the model had nothing to translate (already in target, or
  /// trivial/identical output). The UI hides the original/translation toggle.
  bool get isTranslationIdentical =>
      translation.trim() == originalText.trim();

  ScanResult withTranslation(String newTranslation) => ScanResult(
        detectedLanguage: detectedLanguage,
        originalText: originalText,
        translation: newTranslation,
      );

  factory ScanResult.fromJson(Map<String, dynamic> json) => ScanResult(
        detectedLanguage: _string(json['detected_language']).trim(),
        originalText: _string(json['original_text']),
        translation: _string(json['translation']),
      );

  /// Tolerates a model that returns a number/null where a string is expected,
  /// so parse errors surface as [TranslatorException] and not a [TypeError].
  static String _string(Object? value) => value is String ? value : '';

  Map<String, dynamic> toJson() => <String, dynamic>{
        'detected_language': detectedLanguage,
        'original_text': originalText,
        'translation': translation,
      };

  @override
  String toString() =>
      'ScanResult($detectedLanguage, ${originalText.length} chars)';
}
