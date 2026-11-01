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
        detectedLanguage: (json['detected_language'] as String?)?.trim() ?? '',
        originalText: (json['original_text'] as String?) ?? '',
        translation: (json['translation'] as String?) ?? '',
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'detected_language': detectedLanguage,
        'original_text': originalText,
        'translation': translation,
      };

  @override
  String toString() =>
      'ScanResult($detectedLanguage, ${originalText.length} chars)';
}
