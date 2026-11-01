import 'dart:typed_data';

import 'package:oshi/data/models.dart';
import 'package:oshi/services/translator.dart';

typedef TranslateHandler =
    String Function(String originalText, String targetCode);

/// Configurable in-memory [Translator] for widget tests.
///
/// Fields are intentionally mutable so a test can flip a configured error into
/// a success between attempts (retry flows).
class FakeTranslator implements Translator {
  FakeTranslator({
    this.analyzeResult,
    this.translateHandler,
    this.analyzeError,
    this.translateError,
    this.analyzeDelay = Duration.zero,
    this.translateDelay = Duration.zero,
  });

  ScanResult? analyzeResult;
  TranslateHandler? translateHandler;
  Object? analyzeError;
  Object? translateError;
  Duration analyzeDelay;
  Duration translateDelay;

  int analyzeCalls = 0;
  int translateCalls = 0;

  final List<String> analyzeTargetCodes = <String>[];
  final List<String> analyzeTargetNames = <String>[];
  final List<String> translateTexts = <String>[];
  final List<String> translateTargetCodes = <String>[];
  final List<String> translateTargetNames = <String>[];

  Uint8List? lastPng;

  @override
  Future<ScanResult> analyzeImage(
    Uint8List png, {
    required String targetCode,
    required String targetName,
  }) async {
    analyzeCalls++;
    lastPng = png;
    analyzeTargetCodes.add(targetCode);
    analyzeTargetNames.add(targetName);

    if (analyzeDelay > Duration.zero) {
      await Future<void>.delayed(analyzeDelay);
    }
    final error = analyzeError;
    if (error != null) throw error;

    final result = analyzeResult;
    if (result == null) {
      throw StateError('FakeTranslator.analyzeResult is not set');
    }
    return result;
  }

  @override
  Future<String> translateText(
    String originalText, {
    required String targetCode,
    required String targetName,
  }) async {
    translateCalls++;
    translateTexts.add(originalText);
    translateTargetCodes.add(targetCode);
    translateTargetNames.add(targetName);

    if (translateDelay > Duration.zero) {
      await Future<void>.delayed(translateDelay);
    }
    final error = translateError;
    if (error != null) throw error;

    final handler = translateHandler;
    if (handler != null) return handler(originalText, targetCode);
    return '[$targetCode] $originalText';
  }
}
