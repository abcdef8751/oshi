import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:http/http.dart' as http;

import '../data/gemini_client.dart';
import '../data/models.dart';
import '../data/prompts.dart';
import 'translator.dart';

/// Longest image edge (px) sent to Gemini. Larger crops cost more, take longer
/// and OCR no better at this model's input resolution.
const int kMaxImageEdge = 1536;

/// [Translator] backed by `gemini-3.5-flash-lite`'s `generateContent` endpoint.
///
/// One multimodal call does OCR + translation; changing the target language
/// later is a cheaper text-only call that never resends the image.
class GeminiFlashLiteTranslator implements Translator {
  GeminiFlashLiteTranslator({
    required String apiKey,
    http.Client? httpClient,
    Duration timeout = const Duration(seconds: 30),
    Uri? baseUri,
  }) : _client = GeminiClient(
         apiKey: apiKey,
         httpClient: httpClient,
         timeout: timeout,
         baseUri: baseUri,
       );

  final GeminiClient _client;

  /// Closes the HTTP client if this translator created it.
  void close() => _client.close();

  @override
  Future<ScanResult> analyzeImage(
    Uint8List png, {
    required String targetCode,
    required String targetName,
  }) async {
    final imageBytes = await downscalePng(png);
    final envelope = await _client.generateContent(
      parts: <Map<String, dynamic>>[
        <String, dynamic>{
          'inlineData': <String, dynamic>{
            'mimeType': 'image/png',
            'data': base64Encode(imageBytes),
          },
        },
        <String, dynamic>{
          'text': buildAnalyzePrompt(
            targetName: targetName,
            targetCode: targetCode,
          ),
        },
      ],
      generationConfig: <String, dynamic>{
        'temperature': 0.1,
        'responseMimeType': 'application/json',
        'responseSchema': kAnalyzeResponseSchema,
      },
    );
    return parseScanResult(extractCandidateText(envelope));
  }

  @override
  Future<String> translateText(
    String originalText, {
    required String targetCode,
    required String targetName,
  }) async {
    final prompt = buildTranslatePrompt(
      targetName: targetName,
      targetCode: targetCode,
    );
    final envelope = await _client.generateContent(
      parts: <Map<String, dynamic>>[
        <String, dynamic>{'text': '$prompt\n\n$originalText'},
      ],
      generationConfig: <String, dynamic>{'temperature': 0.1},
    );
    return extractCandidateText(envelope).trim();
  }
}

/// Shrinks [bytes] so its long edge is at most [maxEdge], returning a PNG.
///
/// Never upscales: an already-small image comes back byte-identical. If the
/// image cannot be decoded, the original bytes are returned so callers fail
/// later with a server/parse error rather than a local exception.
Future<Uint8List> downscalePng(
  Uint8List bytes, {
  int maxEdge = kMaxImageEdge,
}) async {
  if (bytes.isEmpty || maxEdge <= 0) return bytes;

  ui.ImmutableBuffer? buffer;
  ui.ImageDescriptor? descriptor;
  ui.Codec? codec;
  ui.Image? image;
  try {
    buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    descriptor = await ui.ImageDescriptor.encoded(buffer);

    final width = descriptor.width;
    final height = descriptor.height;
    if (width <= 0 || height <= 0) return bytes;

    final longEdge = math.max(width, height);
    if (longEdge <= maxEdge) return bytes;

    final scale = maxEdge / longEdge;
    final targetWidth = math.max(1, (width * scale).round());
    final targetHeight = math.max(1, (height * scale).round());

    codec = await ui.instantiateImageCodec(
      bytes,
      targetWidth: targetWidth,
      targetHeight: targetHeight,
    );
    final frame = await codec.getNextFrame();
    image = frame.image;
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) return bytes;
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  } catch (_) {
    // Undecodable input: let the API answer instead of failing locally.
    return bytes;
  } finally {
    image?.dispose();
    codec?.dispose();
    descriptor?.dispose();
    buffer?.dispose();
  }
}
