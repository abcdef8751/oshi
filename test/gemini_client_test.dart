import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:oshi/data/gemini_client.dart';
import 'package:oshi/data/prompts.dart';
import 'package:oshi/services/translator.dart';

const String _apiKey = 'test-api-key-do-not-log';

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

http.Response _errorResponse(
  int status,
  String message, {
  List<Map<String, dynamic>> details = const <Map<String, dynamic>>[],
}) => _jsonResponse(<String, dynamic>{
  'error': <String, dynamic>{
    'code': status,
    'message': message,
    'status': 'ERROR',
    if (details.isNotEmpty) 'details': details,
  },
}, status: status);

void main() {
  group('GeminiClient request shape', () {
    test('POSTs parts and generationConfig to the model endpoint', () async {
      late http.Request captured;
      final client = GeminiClient(
        apiKey: _apiKey,
        httpClient: MockClient((request) async {
          captured = request;
          return _jsonResponse(_envelope('{"ok":true}'));
        }),
      );

      await client.generateContent(
        parts: <Map<String, dynamic>>[
          <String, dynamic>{
            'inlineData': <String, dynamic>{
              'mimeType': 'image/png',
              'data': 'AAAA',
            },
          },
          <String, dynamic>{'text': 'prompt'},
        ],
        generationConfig: <String, dynamic>{
          'temperature': 0.1,
          'responseMimeType': 'application/json',
          'responseSchema': kAnalyzeResponseSchema,
        },
      );

      expect(captured.method, 'POST');
      expect(captured.url, kGeminiGenerateContentUri);
      expect(
        captured.url.toString(),
        'https://generativelanguage.googleapis.com/v1beta/models/'
        'gemini-3.5-flash-lite:generateContent',
      );
      expect(captured.headers['x-goog-api-key'], _apiKey);
      expect(captured.headers['content-type'], startsWith('application/json'));

      final body = jsonDecode(captured.body) as Map<String, dynamic>;
      final contents = body['contents'] as List;
      expect(contents, hasLength(1));
      final parts = (contents.first as Map)['parts'] as List;
      expect(parts, hasLength(2));
      expect((parts[0] as Map)['inlineData'], <String, dynamic>{
        'mimeType': 'image/png',
        'data': 'AAAA',
      });
      expect((parts[1] as Map)['text'], 'prompt');

      final config = body['generationConfig'] as Map;
      expect(config['temperature'], 0.1);
      expect(config['responseMimeType'], 'application/json');
      expect(config['responseSchema'], kAnalyzeResponseSchema);
    });

    test('omits generationConfig when not supplied', () async {
      late http.Request captured;
      final client = GeminiClient(
        apiKey: _apiKey,
        httpClient: MockClient((request) async {
          captured = request;
          return _jsonResponse(_envelope('hello'));
        }),
      );

      await client.generateContent(
        parts: <Map<String, dynamic>>[
          <String, dynamic>{'text': 'only text'},
        ],
      );

      final body = jsonDecode(captured.body) as Map<String, dynamic>;
      expect(body.containsKey('generationConfig'), isFalse);
    });

    test('honours a custom baseUri', () async {
      final custom = Uri.parse(
        'https://example.test/v1beta/models/test-model:generateContent',
      );
      late Uri capturedUrl;
      final client = GeminiClient(
        apiKey: _apiKey,
        baseUri: custom,
        httpClient: MockClient((request) async {
          capturedUrl = request.url;
          return _jsonResponse(_envelope('ok'));
        }),
      );

      await client.generateContent(
        parts: <Map<String, dynamic>>[
          <String, dynamic>{'text': 'hi'},
        ],
      );

      expect(capturedUrl, custom);
    });
  });

  group('GeminiClient error mapping', () {
    test('400 -> badRequest with Google message and key hint', () async {
      var calls = 0;
      final client = GeminiClient(
        apiKey: _apiKey,
        httpClient: MockClient((_) async {
          calls++;
          return _errorResponse(
            400,
            'API key not valid. Please pass a valid API key.',
          );
        }),
      );

      await expectLater(
        client.generateContent(
          parts: <Map<String, dynamic>>[
            <String, dynamic>{'text': 'hi'},
          ],
        ),
        throwsA(
          isA<TranslatorException>()
              .having((e) => e.kind, 'kind', TranslatorErrorKind.badRequest)
              .having(
                (e) => e.message,
                'message',
                allOf(
                  contains('API key not valid'),
                  contains('GEMINI_API_KEY'),
                  isNot(contains(_apiKey)),
                ),
              ),
        ),
      );
      expect(calls, 1, reason: '4xx must never be retried');
    });

    test('429 -> rateLimited with RetryInfo delay and no retry', () async {
      var calls = 0;
      final client = GeminiClient(
        apiKey: _apiKey,
        httpClient: MockClient((_) async {
          calls++;
          return _errorResponse(
            429,
            'You exceeded your current quota.',
            details: <Map<String, dynamic>>[
              <String, dynamic>{
                '@type': 'type.googleapis.com/google.rpc.RetryInfo',
                'retryDelay': '12s',
              },
            ],
          );
        }),
      );

      await expectLater(
        client.generateContent(
          parts: <Map<String, dynamic>>[
            <String, dynamic>{'text': 'hi'},
          ],
        ),
        throwsA(
          isA<TranslatorException>()
              .having((e) => e.kind, 'kind', TranslatorErrorKind.rateLimited)
              .having(
                (e) => e.retryAfter,
                'retryAfter',
                const Duration(seconds: 12),
              ),
        ),
      );
      expect(calls, 1, reason: '429 must not be retried');
    });

    test('429 without RetryInfo has no retryAfter', () async {
      final client = GeminiClient(
        apiKey: _apiKey,
        httpClient: MockClient(
          (_) async => _errorResponse(429, 'Quota exceeded.'),
        ),
      );

      await expectLater(
        client.generateContent(
          parts: <Map<String, dynamic>>[
            <String, dynamic>{'text': 'hi'},
          ],
        ),
        throwsA(
          isA<TranslatorException>()
              .having((e) => e.kind, 'kind', TranslatorErrorKind.rateLimited)
              .having((e) => e.retryAfter, 'retryAfter', isNull),
        ),
      );
    });

    test('500 is retried exactly once then throws server', () async {
      var calls = 0;
      final client = GeminiClient(
        apiKey: _apiKey,
        httpClient: MockClient((_) async {
          calls++;
          return _errorResponse(500, 'Internal error.');
        }),
      );

      await expectLater(
        client.generateContent(
          parts: <Map<String, dynamic>>[
            <String, dynamic>{'text': 'hi'},
          ],
        ),
        throwsA(
          isA<TranslatorException>()
              .having((e) => e.kind, 'kind', TranslatorErrorKind.server)
              .having((e) => e.message, 'message', contains('Internal error')),
        ),
      );
      expect(calls, 2);
    });

    test('500 then 200 succeeds with one retry', () async {
      var calls = 0;
      final client = GeminiClient(
        apiKey: _apiKey,
        httpClient: MockClient((_) async {
          calls++;
          if (calls == 1) return _errorResponse(503, 'Unavailable.');
          return _jsonResponse(_envelope('recovered'));
        }),
      );

      final envelope = await client.generateContent(
        parts: <Map<String, dynamic>>[
          <String, dynamic>{'text': 'hi'},
        ],
      );

      expect(calls, 2);
      expect(extractCandidateText(envelope), 'recovered');
    });

    test('socket failure -> network after one retry', () async {
      var calls = 0;
      final client = GeminiClient(
        apiKey: _apiKey,
        httpClient: MockClient((_) async {
          calls++;
          throw const SocketException('no route to host');
        }),
      );

      await expectLater(
        client.generateContent(
          parts: <Map<String, dynamic>>[
            <String, dynamic>{'text': 'hi'},
          ],
        ),
        throwsA(
          isA<TranslatorException>()
              .having((e) => e.kind, 'kind', TranslatorErrorKind.network)
              .having((e) => e.message, 'message', contains('no route')),
        ),
      );
      expect(calls, 2);
    });

    test('timeout -> network and applies per attempt', () async {
      var calls = 0;
      final client = GeminiClient(
        apiKey: _apiKey,
        timeout: const Duration(milliseconds: 20),
        httpClient: MockClient((_) async {
          calls++;
          await Future<void>.delayed(const Duration(milliseconds: 150));
          return _jsonResponse(_envelope('late'));
        }),
      );

      await expectLater(
        client.generateContent(
          parts: <Map<String, dynamic>>[
            <String, dynamic>{'text': 'hi'},
          ],
        ),
        throwsA(
          isA<TranslatorException>()
              .having((e) => e.kind, 'kind', TranslatorErrorKind.network)
              .having((e) => e.message, 'message', contains('within')),
        ),
      );
      expect(calls, 2);
    });

    test('invalid JSON on 200 -> unknown', () async {
      final client = GeminiClient(
        apiKey: _apiKey,
        httpClient: MockClient(
          (_) async => http.Response('<html>not json</html>', 200),
        ),
      );

      await expectLater(
        client.generateContent(
          parts: <Map<String, dynamic>>[
            <String, dynamic>{'text': 'hi'},
          ],
        ),
        throwsA(
          isA<TranslatorException>().having(
            (e) => e.kind,
            'kind',
            TranslatorErrorKind.unknown,
          ),
        ),
      );
    });

    test('missing candidates -> unknown', () async {
      final client = GeminiClient(
        apiKey: _apiKey,
        httpClient: MockClient(
          (_) async => _jsonResponse(<String, dynamic>{'foo': 'bar'}),
        ),
      );

      await expectLater(
        client.generateContent(
          parts: <Map<String, dynamic>>[
            <String, dynamic>{'text': 'hi'},
          ],
        ),
        throwsA(
          isA<TranslatorException>()
              .having((e) => e.kind, 'kind', TranslatorErrorKind.unknown)
              .having((e) => e.message, 'message', contains('no candidates')),
        ),
      );
    });
  });

  group('extractCandidateText', () {
    test('concatenates every text part', () {
      final envelope = <String, dynamic>{
        'candidates': <Map<String, dynamic>>[
          <String, dynamic>{
            'content': <String, dynamic>{
              'parts': <Map<String, dynamic>>[
                <String, dynamic>{'text': 'Hello, '},
                <String, dynamic>{'text': 'world'},
                <String, dynamic>{'inlineData': <String, dynamic>{}},
              ],
            },
          },
        ],
      };

      expect(extractCandidateText(envelope), 'Hello, world');
    });

    test('throws unknown when there is no text', () {
      expect(
        () => extractCandidateText(<String, dynamic>{
          'candidates': <Map<String, dynamic>>[
            <String, dynamic>{'finishReason': 'SAFETY'},
          ],
        }),
        throwsA(
          isA<TranslatorException>()
              .having((e) => e.kind, 'kind', TranslatorErrorKind.unknown)
              .having((e) => e.message, 'message', contains('SAFETY')),
        ),
      );
    });
  });

  group('parseScanResult', () {
    test('parses plain JSON', () {
      final result = parseScanResult(
        '{"detected_language":"ja","original_text":"こんにちは",'
        '"translation":"Hello"}',
      );

      expect(result.detectedLanguage, 'ja');
      expect(result.originalText, 'こんにちは');
      expect(result.translation, 'Hello');
    });

    test('strips a bare fence', () {
      final result = parseScanResult(
        '```\n'
        '{"detected_language":"en","original_text":"Hi","translation":"Hi"}'
        '\n```',
      );

      expect(result.detectedLanguage, 'en');
      expect(result.translation, 'Hi');
      expect(result.isTranslationIdentical, isTrue);
    });

    test('strips a ```json fence', () {
      final result = parseScanResult(
        '```json\n'
        '{"detected_language":"zh-Hans","original_text":"你好",'
        '"translation":"Hello"}\n'
        '```',
      );

      expect(result.detectedLanguage, 'zh-Hans');
      expect(result.originalText, '你好');
      expect(result.translation, 'Hello');
    });

    test('recovers a fenced block after commentary', () {
      final result = parseScanResult(
        'Here is the JSON:\n'
        '```json\n'
        '{"detected_language":"de","original_text":"Hallo",'
        '"translation":"Hello"}\n'
        '```',
      );

      expect(result.detectedLanguage, 'de');
      expect(result.translation, 'Hello');
    });

    test('garbage throws a TranslatorException', () {
      expect(
        () => parseScanResult('sorry, I cannot read this image'),
        throwsA(
          isA<TranslatorException>().having(
            (e) => e.kind,
            'kind',
            TranslatorErrorKind.unknown,
          ),
        ),
      );
    });

    test('empty text throws a TranslatorException', () {
      expect(
        () => parseScanResult('   '),
        throwsA(
          isA<TranslatorException>()
              .having((e) => e.kind, 'kind', TranslatorErrorKind.unknown)
              .having((e) => e.message, 'message', contains('empty')),
        ),
      );
    });

    test('non-object JSON throws a TranslatorException', () {
      expect(
        () => parseScanResult('["not", "an", "object"]'),
        throwsA(
          isA<TranslatorException>().having(
            (e) => e.kind,
            'kind',
            TranslatorErrorKind.unknown,
          ),
        ),
      );
    });
  });
}
