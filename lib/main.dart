import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  var apiKey = '';
  try {
    await dotenv.load(fileName: '.env');
    apiKey = dotenv.env['GEMINI_API_KEY'] ?? '';
  } catch (_) {
    // The asset is gitignored; a missing .env just disables capture until the
    // developer copies .env.example.
  }

  runApp(OshiApp(apiKey: apiKey));
}

/// Kept so widget tests can boot the app without reading `.env`.
@visibleForTesting
Widget buildAppForTests({String apiKey = ''}) => OshiApp(apiKey: apiKey);
