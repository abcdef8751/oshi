import 'dart:typed_data';

import '../data/models.dart';

/// Why a translation call failed, mapped to something the UI can render.
enum TranslatorErrorKind {
  /// 400 / invalid key / malformed request.
  badRequest,

  /// 429, free-tier quota exhausted.
  rateLimited,

  /// Socket, DNS, timeout, airplane mode.
  network,

  /// 5xx.
  server,

  /// Anything else (bad JSON, unexpected shape).
  unknown,
}

class TranslatorException implements Exception {
  const TranslatorException(
    this.kind,
    this.message, {
    this.retryAfter,
  });

  final TranslatorErrorKind kind;
  final String message;

  /// Populated from Gemini's `RetryInfo` when a 429 tells us how long to wait.
  final Duration? retryAfter;

  @override
  String toString() => 'TranslatorException($kind): $message';
}

/// Contract the UI codes against. `GeminiFlashLiteTranslator` is the only
/// production implementation; tests inject fakes.
abstract class Translator {
  /// One multimodal call: transcribe the PNG at [png] and translate it into
  /// `targetName` (`targetCode`). Returns `null`-free [ScanResult].
  Future<ScanResult> analyzeImage(
    Uint8List png, {
    required String targetCode,
    required String targetName,
  });

  /// Text-only retranslation of an already-transcribed string into the new
  /// target. Must not resend the image.
  Future<String> translateText(
    String originalText, {
    required String targetCode,
    required String targetName,
  });
}

/// Human-readable label for the provider chip in the result sheet.
const String kProviderLabel = 'Gemini 3.5 Flash-Lite';
