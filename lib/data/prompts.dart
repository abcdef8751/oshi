/// Prompt text and response schema for the Gemini calls.
///
/// Kept as plain Dart (no Flutter imports) so the client, the translator and
/// unit tests can all share the exact strings that go over the wire.
library;

/// Instruction for the multimodal OCR + translate call (plan §5, call 1).
///
/// The model is asked to transcribe verbatim, detect the language as BCP-47 and
/// translate into [targetName] ([targetCode]) without adding commentary.
String buildAnalyzePrompt({
  required String targetName,
  required String targetCode,
}) {
  return 'You are an OCR + translation engine.\n'
      '1. Transcribe every character visible in the image exactly, preserving line breaks.\n'
      '   Do not summarize, correct, or add anything. Join hyphenated line breaks only when\n'
      '   the text is a single sentence.\n'
      '2. Identify the primary language as a BCP-47 code (e.g. "ja", "zh-Hans", "en").\n'
      '3. Translate the transcription into $targetName ($targetCode).\n'
      '   - If the text is already in $targetName, return the transcription as the translation.\n'
      '   - Keep names, numbers, and formatting; do not add commentary.';
}

/// Instruction for the text-only retranslate call (plan §5, call 2).
///
/// The caller appends the cached transcription after this line; the model
/// answers with the translation alone.
String buildTranslatePrompt({
  required String targetName,
  required String targetCode,
}) {
  return 'Translate the following into $targetName ($targetCode). '
      'Output only the translation.';
}

/// Caps how much the model is allowed to "think" before answering.
///
/// Neither call needs reasoning: one reads pixels, the other rewrites a
/// sentence. Left unset the budget is dynamic — the same OCR prompt that costs
/// ~1.5k tokens with no thinking can occasionally spend 12k thought tokens and
/// 30s+ on one capture. Pinning it to `minimal` keeps cost and latency
/// predictable without changing the transcription.
const Map<String, dynamic> kThinkingConfig = <String, dynamic>{
  'thinkingLevel': 'minimal',
};

/// JSON schema for the analyze call, selected by `responseMimeType:
/// application/json`. Gemini's REST API expects the OpenAPI-style `OBJECT` /
/// `STRING` spelling, not JSON-Schema lowercase types.
const Map<String, dynamic> kAnalyzeResponseSchema = <String, dynamic>{
  'type': 'OBJECT',
  'properties': <String, dynamic>{
    'detected_language': <String, dynamic>{'type': 'STRING'},
    'original_text': <String, dynamic>{'type': 'STRING'},
    'translation': <String, dynamic>{'type': 'STRING'},
  },
  'required': <String>['detected_language', 'original_text', 'translation'],
};
