import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/languages.dart';
import '../core/settings.dart';
import '../core/theme.dart';
import '../features/capture/crop_screen.dart';
import '../features/result/result_sheet.dart';
import '../services/gemini_translator.dart';
import '../services/translator.dart';

/// Flutter half of the floating overlay.
///
/// Runs in its own engine started with the `overlayMain` entrypoint (see
/// `CaptureOverlayController`) and is driven entirely by the `oshi/overlay`
/// channel: native adds the window, sends a screenshot path, and this widget
/// renders the crop screen and the result sheet inside it.
class OshiOverlayApp extends StatefulWidget {
  const OshiOverlayApp({
    super.key,
    required this.apiKey,
    this.captureChannel,
    this.translator,
    this.settings,
  });

  final String apiKey;
  final MethodChannel? captureChannel;
  final Translator? translator;
  final Settings? settings;

  @override
  State<OshiOverlayApp> createState() => _OshiOverlayAppState();
}

class _OshiOverlayAppState extends State<OshiOverlayApp> {
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  final ValueNotifier<AppLanguage> _targetLanguage =
      ValueNotifier<AppLanguage>(kEnglish);

  late final MethodChannel _channel =
      widget.captureChannel ?? const MethodChannel('oshi/overlay');
  late final Translator? _translator;

  bool _running = false;
  bool _booted = false;

  @override
  void initState() {
    super.initState();
    _translator = widget.translator ??
        (widget.apiKey.trim().isEmpty
            ? null
            : GeminiFlashLiteTranslator(apiKey: widget.apiKey.trim()));
    _channel.setMethodCallHandler(_onMethodCall);
    _boot();
  }

  @override
  void dispose() {
    _targetLanguage.dispose();
    super.dispose();
  }

  Future<void> _boot() async {
    var languageResolved = false;
    try {
      final settings = widget.settings ?? await Settings.load();
      _targetLanguage.value = languageForCode(settings.targetLangCode);
      languageResolved = true;
    } catch (_) {
      // Preferences are a nicety; native hands us the code below instead.
    }
    if (!mounted) return;
    _booted = true;
    // Tell native we can receive "show" now, and drain a capture that arrived
    // while the engine was still starting.
    try {
      final ready = await _channel.invokeMapMethod<String, dynamic>('ready');
      if (!languageResolved) {
        final code = ready?['targetLang'] as String?;
        if (code != null && code.isNotEmpty) {
          _targetLanguage.value = languageForCode(code);
        }
      }
      final path = ready?['path'] as String?;
      if (path != null && path.isNotEmpty) await _run(path);
    } catch (_) {
      // The window was dismissed before we finished booting.
    }
  }

  Future<void> _onMethodCall(MethodCall call) async {
    if (call.method != 'show' || !_booted) return;
    final arguments = call.arguments;
    final path = arguments is Map ? arguments['path'] as String? : null;
    // The reply must not wait for the whole crop + sheet flow.
    if (path != null) unawaited(_run(path));
  }

  Future<void> _run(String path) async {
    if (_running) return;
    _running = true;
    try {
      final navigator = await _navigator();
      if (navigator == null) return;
      final bytes = await navigator.push<Uint8List>(
        MaterialPageRoute<Uint8List>(
          fullscreenDialog: true,
          builder: (_) => CropScreen(screenshotPath: path),
        ),
      );
      if (bytes == null || !mounted) return;

      final translator = _translator;
      if (translator == null) {
        await _showMissingKey(navigator);
        return;
      }
      final context = _navigatorKey.currentContext;
      if (context == null || !context.mounted) return;
      await showResultSheet(
        context,
        translator: translator,
        targetLanguage: _targetLanguage,
        imagePng: bytes,
        copy: _copyToClipboard,
      );
    } finally {
      await _dismiss();
      _running = false;
    }
  }

  Future<NavigatorState?> _navigator() async {
    final existing = _navigatorKey.currentState;
    if (existing != null) return existing;
    await WidgetsBinding.instance.endOfFrame;
    return _navigatorKey.currentState;
  }

  Future<void> _showMissingKey(NavigatorState navigator) async {
    final context = _navigatorKey.currentContext;
    if (context == null || !context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('No Gemini API key'),
        content: const Text(
          'Add GEMINI_API_KEY to .env and rebuild to enable translation.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  /// The overlay has no Activity, so the stock clipboard platform plugin has
  /// nothing to bind to; native does it for us.
  Future<void> _copyToClipboard(String text) async {
    final copied = await _channel.invokeMethod<bool>('copy', {'text': text});
    if (copied != true) throw StateError('clipboard unavailable');
  }

  Future<void> _dismiss() async {
    try {
      await _channel.invokeMethod<void>('dismiss');
    } catch (_) {
      // Window already gone.
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigatorKey,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.dark,
      home: const ColoredBox(color: Colors.black),
    );
  }
}
