import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'app.dart';
import 'overlay/overlay_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final apiKey = await loadGeminiApiKey();
  runApp(OshiApp(apiKey: apiKey));
}

/// Entrypoint for the floating overlay engine (see `CaptureOverlayController`).
///
/// Must stay in this library: the engine looks the function up in the app's
/// main library.
@pragma('vm:entry-point')
Future<void> overlayMain() async {
  WidgetsFlutterBinding.ensureInitialized();
  final apiKey = await loadGeminiApiKey();
  runApp(OshiOverlayApp(apiKey: apiKey));
}

/// Reads the bundled, gitignored `.env`; empty string when it is missing.
Future<String> loadGeminiApiKey() async {
  try {
    await dotenv.load(fileName: '.env');
    return dotenv.env['GEMINI_API_KEY'] ?? '';
  } catch (_) {
    return '';
  }
}

/// Kept so widget tests can boot the app without reading `.env`.
@visibleForTesting
Widget buildAppForTests({String apiKey = ''}) => OshiApp(apiKey: apiKey);
