// Live smoke check for the Gemini data layer (one-off, never run in tests).
//
// It exercises the same request shapes as `GeminiFlashLiteTranslator` but
// without `dart:ui`, so it can run under plain `dart run`:
//   - a text-only retranslate call
//   - optionally, a multimodal analyze call against a PNG you provide
//     (the real translator downscales; this script assumes a small image).
//
// Usage:
//   cp /home/rp/oshi/.env .env           # never commit
//   dart run tool/gemini_smoke.dart [--image /tmp/oshi-smoke.png]
//                                   [--target ja] [--name Japanese]
//
// The key is read from GEMINI_API_KEY (environment wins) or `.env`, and is
// never echoed. Exit code 0 = both calls returned parseable answers.

import 'dart:convert';
import 'dart:io';

import 'package:oshi/data/gemini_client.dart';
import 'package:oshi/data/prompts.dart';
import 'package:oshi/services/translator.dart';

Future<void> main(List<String> args) async {
  if (args.contains('-h') || args.contains('--help')) {
    _usage();
    return;
  }

  final options = _Options.parse(args);
  final apiKey = _loadApiKey();
  if (apiKey == null) {
    stderr.writeln(
      'GEMINI_API_KEY not found. Put it in the environment or in .env '
      '(see .env.example).',
    );
    exitCode = 2;
    return;
  }

  final client = GeminiClient(apiKey: apiKey);
  final targetName = options.targetName;
  final targetCode = options.targetCode;

  stdout.writeln(
    'Model: $kGeminiModel | target: $targetName ($targetCode) | '
    'timeout: ${client.timeout.inSeconds}s',
  );

  var failures = 0;
  try {
    stdout.writeln('\n[1/2] text-only retranslate');
    final prompt = buildTranslatePrompt(
      targetName: targetName,
      targetCode: targetCode,
    );
    const sample = 'こんにちは世界。これはライブのスモークテストです。';
    final envelope = await client.generateContent(
      parts: <Map<String, dynamic>>[
        <String, dynamic>{'text': '$prompt\n\n$sample'},
      ],
      generationConfig: <String, dynamic>{'temperature': 0.1},
    );
    final translation = extractCandidateText(envelope).trim();
    stdout.writeln('  sample:      $sample');
    stdout.writeln('  translation: $translation');
    if (translation.isEmpty) {
      failures++;
      stderr.writeln('  FAIL: empty translation');
    }
  } on TranslatorException catch (error) {
    failures++;
    stderr.writeln('  FAIL: ${_describe(error)}');
  }

  final imagePath = options.imagePath;
  if (imagePath == null) {
    stdout.writeln(
      '\n[2/2] analyze skipped (pass --image /path/to.png to enable)',
    );
  } else {
    try {
      stdout.writeln('\n[2/2] multimodal analyze: $imagePath');
      final bytes = File(imagePath).readAsBytesSync();
      final envelope = await client.generateContent(
        parts: <Map<String, dynamic>>[
          <String, dynamic>{
            'inlineData': <String, dynamic>{
              'mimeType': 'image/png',
              'data': base64Encode(bytes),
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
      final result = parseScanResult(extractCandidateText(envelope));
      stdout.writeln('  detected:    ${result.detectedLanguage}');
      stdout.writeln(
        '  original:    ${result.originalText.replaceAll('\n', r'\n')}',
      );
      stdout.writeln(
        '  translation: ${result.translation.replaceAll('\n', r'\n')}',
      );
      if (result.originalText.trim().isEmpty) {
        failures++;
        stderr.writeln('  FAIL: empty transcription');
      }
    } on FileSystemException catch (error) {
      failures++;
      stderr.writeln('  FAIL: cannot read image: ${error.message}');
    } on TranslatorException catch (error) {
      failures++;
      stderr.writeln('  FAIL: ${_describe(error)}');
    }
  }

  client.close();
  stdout.writeln(failures == 0 ? '\nOK' : '\n$failures failure(s)');
  if (failures != 0) exitCode = 1;
}

String _describe(TranslatorException error) {
  final delay = error.retryAfter;
  final suffix = delay == null ? '' : ' (retry after ${delay.inSeconds}s)';
  return '${error.kind.name}: ${error.message}$suffix';
}

String? _loadApiKey() {
  final fromEnvironment = Platform.environment['GEMINI_API_KEY'];
  if (fromEnvironment != null && fromEnvironment.trim().isNotEmpty) {
    return fromEnvironment.trim();
  }
  final file = File('.env');
  if (!file.existsSync()) return null;
  for (final line in file.readAsLinesSync()) {
    final trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
    final equals = trimmed.indexOf('=');
    if (equals <= 0) continue;
    if (trimmed.substring(0, equals).trim() != 'GEMINI_API_KEY') continue;
    var value = trimmed.substring(equals + 1).trim();
    final quoted =
        value.length >= 2 &&
        ((value.startsWith('"') && value.endsWith('"')) ||
            (value.startsWith("'") && value.endsWith("'")));
    if (quoted) value = value.substring(1, value.length - 1);
    return value.isEmpty ? null : value;
  }
  return null;
}

void _usage() {
  stdout.writeln(
    'Usage: dart run tool/gemini_smoke.dart '
    '[--image /path/to.png] [--target ja] [--name Japanese]\n'
    'Reads GEMINI_API_KEY from the environment or from .env in the repo root.',
  );
}

class _Options {
  const _Options({
    required this.targetCode,
    required this.targetName,
    this.imagePath,
  });

  final String targetCode;
  final String targetName;
  final String? imagePath;

  static _Options parse(List<String> args) {
    var targetCode = 'ja';
    var targetName = 'Japanese';
    String? imagePath;

    for (var index = 0; index < args.length; index++) {
      final argument = args[index];
      final isValueFlag =
          argument == '--target' ||
          argument == '--name' ||
          argument == '--image';
      if (!isValueFlag) continue;
      if (index + 1 >= args.length) {
        throw ArgumentError('Missing value for $argument');
      }
      final value = args[++index];
      switch (argument) {
        case '--target':
          targetCode = value;
          break;
        case '--name':
          targetName = value;
          break;
        case '--image':
          imagePath = value;
          break;
      }
    }

    return _Options(
      targetCode: targetCode,
      targetName: targetName,
      imagePath: imagePath,
    );
  }
}
