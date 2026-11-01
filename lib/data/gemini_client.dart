import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../services/translator.dart';
import 'models.dart';

/// Model id used for both calls. Verified live by the orchestrator.
const String kGeminiModel = 'gemini-3.5-flash-lite';

/// Production endpoint. Tests pass their own [Uri] instead.
final Uri kGeminiGenerateContentUri = Uri.parse(
  'https://generativelanguage.googleapis.com/v1beta/models/$kGeminiModel:generateContent',
);

/// Thin raw-HTTP wrapper around Gemini's `generateContent`.
///
/// We deliberately do not use the Dart SDK package so the request body (schema
/// and generation config) is exactly what we control. Failures are surfaced as
/// [TranslatorException] so the UI has one error type to handle.
class GeminiClient {
  GeminiClient({
    required String apiKey,
    http.Client? httpClient,
    this.timeout = const Duration(seconds: 30),
    Uri? baseUri,
  }) : _apiKey = apiKey,
       _http = httpClient ?? http.Client(),
       _ownsHttpClient = httpClient == null,
       _baseUri = baseUri ?? kGeminiGenerateContentUri;

  /// Per-attempt timeout; a retry gets its own full timeout.
  final Duration timeout;

  final String _apiKey;
  final http.Client _http;
  final bool _ownsHttpClient;
  final Uri _baseUri;

  /// Sends one `generateContent` request.
  ///
  /// [parts] are already in Gemini's wire format (e.g. `inlineData` + `text`).
  /// Returns the decoded JSON envelope. 5xx and transport failures are retried
  /// once; 4xx never is. The API key is only ever sent in the header.
  Future<Map<String, dynamic>> generateContent({
    required List<Map<String, dynamic>> parts,
    Map<String, dynamic>? generationConfig,
  }) async {
    final payload = <String, dynamic>{
      'contents': <Map<String, dynamic>>[
        <String, dynamic>{'parts': parts},
      ],
      if (generationConfig != null) 'generationConfig': generationConfig,
    };

    for (var attempt = 0; ; attempt++) {
      try {
        return await _send(payload);
      } on TranslatorException catch (error) {
        final retryable =
            error.kind == TranslatorErrorKind.server ||
            error.kind == TranslatorErrorKind.network;
        if (!retryable || attempt >= 1) rethrow;
      }
    }
  }

  /// Closes the underlying HTTP client when this instance created it.
  void close() {
    if (_ownsHttpClient) _http.close();
  }

  Future<Map<String, dynamic>> _send(Map<String, dynamic> payload) async {
    final http.Response response;
    try {
      response = await _http
          .post(
            _baseUri,
            headers: <String, String>{
              'x-goog-api-key': _apiKey,
              'content-type': 'application/json',
            },
            body: jsonEncode(payload),
          )
          .timeout(timeout);
    } on TimeoutException {
      throw TranslatorException(
        TranslatorErrorKind.network,
        'Gemini did not answer within ${timeout.inSeconds}s.',
      );
    } on SocketException catch (error) {
      throw TranslatorException(
        TranslatorErrorKind.network,
        'Could not reach Gemini: ${error.message}',
      );
    } on HandshakeException catch (error) {
      throw TranslatorException(
        TranslatorErrorKind.network,
        'Could not establish a secure connection to Gemini: ${error.message}',
      );
    } on http.ClientException catch (error) {
      throw TranslatorException(
        TranslatorErrorKind.network,
        'Could not reach Gemini: ${error.message}',
      );
    }

    final body = _decodeJsonObject(response.body);
    if (response.statusCode != 200) {
      throw _errorForStatus(response.statusCode, body);
    }
    if (body == null) {
      throw const TranslatorException(
        TranslatorErrorKind.unknown,
        'Gemini returned a response that was not a JSON object.',
      );
    }
    final candidates = body['candidates'];
    if (candidates is! List || candidates.isEmpty) {
      final reason = _promptBlockReason(body);
      throw TranslatorException(
        TranslatorErrorKind.unknown,
        reason == null
            ? 'Gemini returned no candidates.'
            : 'Gemini blocked the request: $reason',
      );
    }
    return body;
  }

  TranslatorException _errorForStatus(int status, Map<String, dynamic>? body) {
    final googleMessage = _googleErrorMessage(body);
    switch (status) {
      case 400:
      case 401:
      case 403:
        final detail =
            googleMessage ?? 'Gemini rejected the request (HTTP $status).';
        return TranslatorException(
          TranslatorErrorKind.badRequest,
          '$detail Check that GEMINI_API_KEY is valid and enabled for the '
          'Generative Language API.',
        );
      case 404:
        return TranslatorException(
          TranslatorErrorKind.badRequest,
          googleMessage ?? 'Gemini model not found (HTTP 404).',
        );
      case 429:
        return TranslatorException(
          TranslatorErrorKind.rateLimited,
          googleMessage ?? 'Gemini free-tier quota reached (HTTP 429).',
          retryAfter: _retryAfter(body),
        );
      default:
        if (status >= 500) {
          return TranslatorException(
            TranslatorErrorKind.server,
            googleMessage ?? 'Gemini is unavailable (HTTP $status).',
          );
        }
        return TranslatorException(
          TranslatorErrorKind.unknown,
          googleMessage ?? 'Unexpected Gemini response (HTTP $status).',
        );
    }
  }
}

/// Concatenates every text part of `candidates[0].content.parts`.
///
/// Throws an unknown-kind [TranslatorException] when the envelope carries no
/// candidates or no text at all (blocked / safety-filtered responses).
String extractCandidateText(Map<String, dynamic> envelope) {
  final candidates = envelope['candidates'];
  if (candidates is! List || candidates.isEmpty) {
    throw const TranslatorException(
      TranslatorErrorKind.unknown,
      'Gemini returned no candidates.',
    );
  }
  final candidate = candidates.first;
  if (candidate is! Map) {
    throw const TranslatorException(
      TranslatorErrorKind.unknown,
      'Gemini returned a malformed candidate.',
    );
  }
  final content = candidate['content'];
  if (content is Map) {
    final parts = content['parts'];
    if (parts is List) {
      final buffer = StringBuffer();
      for (final part in parts) {
        if (part is Map) {
          final text = part['text'];
          if (text is String) buffer.write(text);
        }
      }
      if (buffer.isNotEmpty) return buffer.toString();
    }
  }
  final finishReason = candidate['finishReason'];
  throw TranslatorException(
    TranslatorErrorKind.unknown,
    finishReason is String
        ? 'Gemini returned no text (finish reason: $finishReason).'
        : 'Gemini returned an empty response.',
  );
}

/// Parses the model's JSON answer into a [ScanResult].
///
/// Tolerates ```` ``` ```` / ```` ```json ```` fences even though
/// `responseMimeType: application/json` should make them unnecessary.
ScanResult parseScanResult(String rawModelText) {
  final text = _stripCodeFences(rawModelText);
  if (text.isEmpty) {
    throw const TranslatorException(
      TranslatorErrorKind.unknown,
      'Gemini returned an empty response.',
    );
  }

  final Object? decoded;
  try {
    decoded = jsonDecode(text);
  } on FormatException {
    throw const TranslatorException(
      TranslatorErrorKind.unknown,
      'Gemini returned text that is not valid JSON.',
    );
  }
  if (decoded is! Map<String, dynamic>) {
    throw const TranslatorException(
      TranslatorErrorKind.unknown,
      'Gemini returned JSON that is not an object.',
    );
  }
  return ScanResult.fromJson(decoded);
}

/// Removes a leading/trailing markdown code fence, if present.
///
/// The model normally obeys `responseMimeType`, but fenced answers have been
/// observed behind proxies and on older endpoints, so be defensive.
String _stripCodeFences(String raw) {
  var text = raw.trim();
  if (text.isEmpty) return text;

  if (!text.startsWith('```')) {
    // Commentary before the fence: keep the first fenced block.
    final start = text.indexOf('```');
    final end = text.lastIndexOf('```');
    if (start > 0 && end > start) {
      text = text.substring(start).trim();
    } else {
      return text;
    }
  }

  // Drop the opening fence and an optional language tag on the same line.
  var rest = text.substring(3);
  final newline = rest.indexOf('\n');
  if (newline >= 0) {
    final firstLine = rest.substring(0, newline).trim();
    if (RegExp(r'^[A-Za-z0-9_+-]*$').hasMatch(firstLine)) {
      rest = rest.substring(newline + 1);
    }
  }

  rest = rest.trimRight();
  if (rest.endsWith('```')) {
    rest = rest.substring(0, rest.length - 3);
  }
  return rest.trim();
}

Map<String, dynamic>? _decodeJsonObject(String body) {
  try {
    final decoded = jsonDecode(body);
    return decoded is Map<String, dynamic> ? decoded : null;
  } on FormatException {
    return null;
  }
}

String? _googleErrorMessage(Map<String, dynamic>? body) {
  final error = body?['error'];
  if (error is Map) {
    final message = error['message'];
    if (message is String && message.trim().isNotEmpty) return message.trim();
  }
  return null;
}

String? _promptBlockReason(Map<String, dynamic> body) {
  final feedback = body['promptFeedback'];
  if (feedback is Map) {
    final reason = feedback['blockReason'];
    if (reason is String && reason.isNotEmpty) return reason;
  }
  return null;
}

/// Reads `error.details[]` for a protobuf `RetryInfo` entry.
Duration? _retryAfter(Map<String, dynamic>? body) {
  final error = body?['error'];
  if (error is! Map) return null;
  final details = error['details'];
  if (details is! List) return null;
  for (final detail in details) {
    if (detail is! Map) continue;
    if (detail['@type'] != 'type.googleapis.com/google.rpc.RetryInfo') {
      continue;
    }
    final delay = detail['retryDelay'];
    if (delay is String) return _parseRetryDelay(delay);
  }
  return null;
}

/// Parses protobuf duration strings such as `"12s"`, `"1.5s"` or `"250ms"`.
Duration? _parseRetryDelay(String value) {
  final match = RegExp(r'^(\d+(?:\.\d+)?)(ms|s)$').firstMatch(value.trim());
  if (match == null) return null;
  final amount = double.parse(match.group(1)!);
  if (match.group(2) == 'ms') {
    return Duration(milliseconds: amount.round());
  }
  return Duration(milliseconds: (amount * 1000).ceil());
}
