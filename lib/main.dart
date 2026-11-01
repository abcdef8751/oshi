import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'app.dart';
import 'overlay/overlay_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final apiKey = await loadGeminiApiKey();
  // CaptureActivity starts us with the overlay route; everything else is the
  // normal app shell.
  final route = WidgetsBinding.instance.platformDispatcher.defaultRouteName;
  if (route == kCaptureRoute) {
    runApp(OshiOverlayApp(apiKey: apiKey));
  } else {
    runApp(OshiApp(apiKey: apiKey));
  }
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
