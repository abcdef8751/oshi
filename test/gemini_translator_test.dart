import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:oshi/data/prompts.dart';
import 'package:oshi/services/gemini_translator.dart';
import 'package:oshi/services/translator.dart';

const String _apiKey = 'test-api-key-do-not-log';

const Map<String, dynamic> _scanJson = <String, dynamic>{
  'detected_language': 'ja',
  'original_text': 'こんにちは世界',
  'translation': 'Hello world',
};

Map<String, dynamic> _envelope(String text) => <String, dynamic>{
  'candidates': <Map<String, dynamic>>[
    <String, dynamic>{
      'content': <String, dynamic>{
        'parts': <Map<String, dynamic>>[
          <String, dynamic>{'text': text},
        ],
      },
      'finishReason': 'STOP',
    },
  ],
};

http.Response _jsonResponse(Object body, {int status = 200}) => http.Response(
  jsonEncode(body),
  status,
  headers: <String, String>{'content-type': 'application/json'},
);

Map<String, dynamic> _requestBody(http.Request request) =>
    jsonDecode(request.body) as Map<String, dynamic>;

List<Map<String, dynamic>> _requestParts(http.Request request) {
  final contents = _requestBody(request)['contents'] as List;
  return ((contents.first as Map)['parts'] as List)
      .cast<Map<String, dynamic>>();
}

GeminiFlashLiteTranslator _translator(
  MockClientHandler handler, {
  Duration timeout = const Duration(seconds: 30),
}) => GeminiFlashLiteTranslator(
  apiKey: _apiKey,
  timeout: timeout,
  httpClient: MockClient(handler),
);

/// Renders a PNG with a solid background and a lighter quadrant so it compresses
/// realistically at large sizes.
Future<Uint8List> _makePng(int width, int height) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
    ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    ui.Paint()..color = const ui.Color(0xFF2E5A88),
  );
  canvas.drawRect(
    ui.Rect.fromLTWH(0, 0, width / 2, height / 2),
    ui.Paint()..color = const ui.Color(0xFFF2F2F2),
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  picture.dispose();
  return data!.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
}

Future<ui.Image> _decodePng(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  codec.dispose();
  return frame.image;
}

String _inlineDataBase64(http.Request request) {
  final parts = _requestParts(request);
  final inlineData = parts.first['inlineData'] as Map<String, dynamic>;
  return inlineData['data'] as String;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('analyzeImage', () {
    test('sends inline image + analyze prompt and parses the result', () async {
      late http.Request captured;
      final png = await _makePng(96, 48);
      final translator = _translator((request) async {
        captured = request;
        return _jsonResponse(_envelope(jsonEncode(_scanJson)));
      });

      final result = await translator.analyzeImage(
        png,
        targetCode: 'ja',
        targetName: 'Japanese',
      );

      expect(result.detectedLanguage, 'ja');
      expect(result.originalText, 'こんにちは世界');
      expect(result.translation, 'Hello world');
      expect(result.isTranslationIdentical, isFalse);

      final parts = _requestParts(captured);
      expect(parts, hasLength(2));
      final inlineData = parts[0]['inlineData'] as Map<String, dynamic>;
      expect(inlineData['mimeType'], 'image/png');
      expect(inlineData['data'], isNotEmpty);
      expect(parts[1]['text'], contains('OCR + translation engine'));
      expect(
        parts[1]['text'],
        buildAnalyzePrompt(targetName: 'Japanese', targetCode: 'ja'),
      );

      final config = _requestBody(captured)['generationConfig'] as Map;
      expect(config['temperature'], 0.1);
      expect(config['responseMimeType'], 'application/json');
      expect(config['responseSchema'], kAnalyzeResponseSchema);
      expect(config['thinkingConfig'], kThinkingConfig);
    });

    test('sends the API key in the header only, never the body', () async {
      late http.Request captured;
      final png = await _makePng(16, 16);
      final translator = _translator((request) async {
        captured = request;
        return _jsonResponse(_envelope(jsonEncode(_scanJson)));
      });

      await translator.analyzeImage(
        png,
        targetCode: 'en',
        targetName: 'English',
      );

      expect(captured.headers['x-goog-api-key'], _apiKey);
      expect(captured.body, isNot(contains(_apiKey)));
      expect(captured.url.toString(), isNot(contains(_apiKey)));
    });

    test('never upscales a small PNG', () async {
      late Uint8List sent;
      final png = await _makePng(100, 50);
      final translator = _translator((request) async {
        sent = base64Decode(_inlineDataBase64(request));
        return _jsonResponse(_envelope(jsonEncode(_scanJson)));
      });

      await translator.analyzeImage(
        png,
        targetCode: 'ja',
        targetName: 'Japanese',
      );

      final image = await _decodePng(sent);
      expect(image.width, 100);
      expect(image.height, 50);
      image.dispose();
    });

    test('downscales a >1536px PNG to a 1536px long edge', () async {
      late Uint8List sent;
      final png = await _makePng(2000, 1000);
      final translator = _translator((request) async {
        sent = base64Decode(_inlineDataBase64(request));
        return _jsonResponse(_envelope(jsonEncode(_scanJson)));
      });

      await translator.analyzeImage(
        png,
        targetCode: 'ja',
        targetName: 'Japanese',
      );

      final image = await _decodePng(sent);
      expect(image.width, kMaxImageEdge);
      expect(image.height, 768); // 1000 * 1536 / 2000
      image.dispose();
    });

    test('downscales a tall PNG on its long edge too', () async {
      late Uint8List sent;
      final png = await _makePng(900, 2400);
      final translator = _translator((request) async {
        sent = base64Decode(_inlineDataBase64(request));
        return _jsonResponse(_envelope(jsonEncode(_scanJson)));
      });

      await translator.analyzeImage(
        png,
        targetCode: 'ja',
        targetName: 'Japanese',
      );

      final image = await _decodePng(sent);
      expect(image.height, kMaxImageEdge);
      expect(image.width, 576); // 900 * 1536 / 2400
      image.dispose();
    });

    test('sends the original bytes when the PNG cannot be decoded', () async {
      final garbage = Uint8List.fromList(
        List<int>.generate(64, (index) => index),
      );
      late String data;
      final translator = _translator((request) async {
        data = _inlineDataBase64(request);
        return _jsonResponse(_envelope(jsonEncode(_scanJson)));
      });

      await translator.analyzeImage(
        garbage,
        targetCode: 'ja',
        targetName: 'Japanese',
      );

      expect(data, base64Encode(garbage));
    });

    test('surfaces a rate-limited error to the caller', () async {
      final translator = _translator(
        (_) async => _jsonResponse(<String, dynamic>{
          'error': <String, dynamic>{
            'code': 429,
            'message': 'Quota exceeded.',
            'details': <Map<String, dynamic>>[
              <String, dynamic>{
                '@type': 'type.googleapis.com/google.rpc.RetryInfo',
                'retryDelay': '30s',
              },
            ],
          },
        }, status: 429),
      );
      final png = await _makePng(16, 16);

      await expectLater(
        translator.analyzeImage(png, targetCode: 'ja', targetName: 'Japanese'),
        throwsA(
          isA<TranslatorException>()
              .having((e) => e.kind, 'kind', TranslatorErrorKind.rateLimited)
              .having(
                (e) => e.retryAfter,
                'retryAfter',
                const Duration(seconds: 30),
              ),
        ),
      );
    });
  });

  group('translateText', () {
    test(
      'is text-only, includes the original, and returns trimmed text',
      () async {
        late http.Request captured;
        final translator = _translator((request) async {
          captured = request;
          return _jsonResponse(_envelope('  Bonjour le monde\n'));
        });

        const original = 'こんにちは世界';
        final translation = await translator.translateText(
          original,
          targetCode: 'fr',
          targetName: 'French',
        );

        expect(translation, 'Bonjour le monde');

        final parts = _requestParts(captured);
        expect(parts, hasLength(1));
        expect(parts.first.containsKey('inlineData'), isFalse);
        expect(parts.first.containsKey('text'), isTrue);

        final text = parts.first['text'] as String;
        expect(
          text,
          startsWith(
            buildTranslatePrompt(targetName: 'French', targetCode: 'fr'),
          ),
        );
        expect(text, contains(original));
        expect(text, contains('\n\n$original'));

        final body = _requestBody(captured);
        expect(body.toString(), isNot(contains('inlineData')));
        expect(body.toString(), isNot(contains('mimeType')));

        final config = body['generationConfig'] as Map;
        expect(config['temperature'], 0.1);
        expect(config.containsKey('responseSchema'), isFalse);
        expect(config.containsKey('responseMimeType'), isFalse);
        // Reasoning is pinned off for this call too: translating a cached
        // transcription never benefits from a thinking budget.
        expect(config['thinkingConfig'], kThinkingConfig);
      },
    );

    test('passes a long transcription through unchanged', () async {
      late String sentText;
      final translator = _translator((request) async {
        sentText = _requestParts(request).single['text'] as String;
        return _jsonResponse(_envelope('Hallo'));
      });

      final original = List<String>.generate(
        40,
        (index) => 'Zeile ${index + 1}: Grüße aus München.',
      ).join('\n');

      final translation = await translator.translateText(
        original,
        targetCode: 'de',
        targetName: 'German',
      );

      expect(translation, 'Hallo');
      expect(
        sentText,
        '${buildTranslatePrompt(targetName: 'German', targetCode: 'de')}'
        '\n\n$original',
      );
    });
  });

  group('downscalePng', () {
    test('returns the input bytes for an unchanged small image', () async {
      final png = await _makePng(40, 30);

      final result = await downscalePng(png);

      expect(result, same(png));
    });

    test('never upscales', () async {
      final png = await _makePng(1, 1);

      final result = await downscalePng(png);

      expect(result, same(png));
    });
  });
}
