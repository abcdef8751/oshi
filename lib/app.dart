import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/languages.dart';
import 'core/settings.dart';
import 'core/theme.dart';
import 'data/models.dart';
import 'features/capture/crop_screen.dart';
import 'features/result/result_sheet.dart';
import 'features/settings/settings_screen.dart';
import 'native/capture_channel.dart';
import 'services/gemini_translator.dart';
import 'services/translator.dart';

/// Root widget. Dependencies are injectable so the shell can be widget-tested
/// without a platform channel or a network.
class OshiApp extends StatefulWidget {
  const OshiApp({
    super.key,
    required this.apiKey,
    this.captureChannel,
    this.translator,
    this.settings,
  });

  /// Gemini key from `.env`; empty string when missing.
  final String apiKey;
  final CaptureChannel? captureChannel;
  final Translator? translator;
  final Settings? settings;

  @override
  State<OshiApp> createState() => _OshiAppState();
}

class _OshiAppState extends State<OshiApp>
    with WidgetsBindingObserver {
  late final CaptureChannel _channel;
  late final Translator? _translator;
  final ValueNotifier<AppLanguage> _targetLanguage =
      ValueNotifier<AppLanguage>(kEnglish);

  final GlobalKey<NavigatorState> _navKey = GlobalKey<NavigatorState>();
  final GlobalKey<ScaffoldMessengerState> _messengerKey =
      GlobalKey<ScaffoldMessengerState>();

  Settings? _settings;
  ScanResult? _lastResult;

  bool _accessibilityEnabled = false;
  bool _tileAdded = false;
  bool _loading = true;
  bool _draining = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _channel = widget.captureChannel ?? CaptureChannel();
    _translator = widget.translator ??
        (widget.apiKey.trim().isEmpty
            ? null
            : GeminiFlashLiteTranslator(apiKey: widget.apiKey.trim()));
    _channel.setCaptureAvailableHandler(_drainPendingCapture);
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final settings = widget.settings ?? await Settings.load();
    if (!mounted) return;
    _targetLanguage.value = languageForCode(settings.targetLangCode);
    setState(() => _settings = settings);
    await _refreshStatus();
    await _drainPendingCapture();
    if (settings.notificationEnabled) {
      // Re-post the shade shortcut on every launch; harmless when already up.
      unawaited(_channel.postNotification().catchError((Object _) {}));
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _refreshStatus() async {
    final enabled = await _channel.isAccessibilityEnabled();
    final tileAdded = await _channel.isTileAdded();
    if (!mounted) return;
    setState(() {
      _accessibilityEnabled = enabled;
      _tileAdded = tileAdded;
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshStatus();
      _drainPendingCapture();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _targetLanguage.dispose();
    super.dispose();
  }

  Future<void> _drainPendingCapture() async {
    if (_draining) return;
    _draining = true;
    try {
      final pending = await _channel.getPendingCapture();
      if (!mounted || pending.isEmpty) return;
      if (pending.error != null) {
        _showCaptureError(pending.error!);
        return;
      }
      final path = pending.path;
      if (path != null) await _openCrop(path);
    } finally {
      _draining = false;
    }
  }

  /// The navigator lives below `MaterialApp`; this state is above it, so we
  /// reach it through a key and tolerate the very first frame.
  Future<NavigatorState?> _navigator() async {
    final existing = _navKey.currentState;
    if (existing != null) return existing;
    await WidgetsBinding.instance.endOfFrame;
    return _navKey.currentState;
  }

  Future<void> _openCrop(String screenshotPath) async {
    final navigator = await _navigator();
    if (navigator == null) return;
    final bytes = await navigator.push<Uint8List>(
      MaterialPageRoute<Uint8List>(
        fullscreenDialog: true,
        builder: (_) => CropScreen(screenshotPath: screenshotPath),
      ),
    );
    if (!mounted || bytes == null) return;
    await _analyze(bytes);
  }

  Future<void> _analyze(Uint8List png) async {
    final translator = _translator;
    if (translator == null) {
      _snack('Add GEMINI_API_KEY to .env, then rebuild.');
      return;
    }
    final sheetContext = _navKey.currentContext;
    if (sheetContext == null || !mounted) return;
    await showResultSheet(
      sheetContext,
      translator: translator,
      targetLanguage: _targetLanguage,
      imagePng: png,
      onResult: (result) {
        if (mounted) setState(() => _lastResult = result);
      },
    );
  }

  Future<void> _reopenLastResult() async {
    final last = _lastResult;
    final translator = _translator;
    if (last == null || translator == null) return;
    final sheetContext = _navKey.currentContext;
    if (sheetContext == null || !mounted) return;
    await showResultSheet(
      sheetContext,
      translator: translator,
      targetLanguage: _targetLanguage,
      initialResult: last,
      onResult: (result) {
        if (mounted) setState(() => _lastResult = result);
      },
    );
  }

  /// In-app debug path: capture synchronously through the channel.
  Future<void> _captureNow() async {
    try {
      final path = await _channel.takeScreenshot();
      if (!mounted) return;
      await _openCrop(path);
    } on PlatformException catch (error) {
      _showCaptureError(error.code);
    }
  }

  void _showCaptureError(String code) {
    switch (code) {
      case CaptureErrorCodes.secureWindow:
        _snack('This screen is protected (DRM / banking app)');
      case CaptureErrorCodes.noAccessibilityAccess:
        _showAccessibilityDialog();
      case CaptureErrorCodes.intervalTimeShort:
        // Retried natively; if it still shows up, stay quiet.
        break;
      case CaptureErrorCodes.internalError:
      default:
        _snack('Capture failed');
    }
  }

  Future<void> _showAccessibilityDialog() async {
    final dialogContext = (await _navigator())?.context;
    if (dialogContext == null || !dialogContext.mounted) return;
    await showDialog<void>(
      context: dialogContext,
      builder: (context) => AlertDialog(
        title: const Text('Accessibility access needed'),
        content: const Text(
          'Oshi uses the accessibility service only to take screenshots you '
          'explicitly request. Enable it to capture text.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Not now'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(context).pop();
              _channel.openAccessibilitySettings();
            },
            child: const Text('Open settings'),
          ),
        ],
      ),
    );
  }

  void _snack(String message) {
    if (!mounted) return;
    final messenger = _messengerKey.currentState;
    if (messenger == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _messengerKey.currentState
          ?..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(message)));
      });
      return;
    }
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openSettings() async {
    final settings = _settings;
    if (settings == null) return;
    final navigator = await _navigator();
    if (navigator == null) return;
    await navigator.push<void>(
      MaterialPageRoute<void>(
        builder: (_) => SettingsScreen(
          settings: settings,
          captureChannel: _channel,
        ),
      ),
    );
    if (!mounted) return;
    // The default target may have changed while we were away.
    _targetLanguage.value = languageForCode(settings.targetLangCode);
    await _refreshStatus();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Oshi',
      navigatorKey: _navKey,
      scaffoldMessengerKey: _messengerKey,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.dark,
      home: _loading || _settings == null
          ? const Scaffold(body: Center(child: CircularProgressIndicator()))
          : _HomeScreen(
              settings: _settings!,
              accessibilityEnabled: _accessibilityEnabled,
              tileAdded: _tileAdded,
              hasApiKey: _translator != null,
              lastResult: _lastResult,
              onCaptureNow: _captureNow,
              onReopenLast: _reopenLastResult,
              onOpenSettings: _openSettings,
              onEnableAccessibility: _channel.openAccessibilitySettings,
              onRetryStatus: _refreshStatus,
            ),
    );
  }
}

class _HomeScreen extends StatelessWidget {
  const _HomeScreen({
    required this.settings,
    required this.accessibilityEnabled,
    required this.tileAdded,
    required this.hasApiKey,
    required this.lastResult,
    required this.onCaptureNow,
    required this.onReopenLast,
    required this.onOpenSettings,
    required this.onEnableAccessibility,
    required this.onRetryStatus,
  });

  final Settings settings;
  final bool accessibilityEnabled;
  final bool tileAdded;
  final bool hasApiKey;
  final ScanResult? lastResult;
  final Future<void> Function() onCaptureNow;
  final Future<void> Function() onReopenLast;
  final Future<void> Function() onOpenSettings;
  final Future<void> Function() onEnableAccessibility;
  final Future<void> Function() onRetryStatus;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Oshi', style: TextStyle(letterSpacing: 1.5)),
        actions: [
          if (lastResult != null)
            IconButton(
              tooltip: 'Last result',
              onPressed: onReopenLast,
              icon: const Icon(Icons.history),
            ),
          IconButton(
            tooltip: 'Settings',
            onPressed: onOpenSettings,
            icon: const Icon(Icons.tune),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: onRetryStatus,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            Text(
              'Grab text from anywhere.',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Tap the notification shade shortcut or the Quick Settings tile, '
              'drag over the text you want, and read it in your language.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 20),
            _StatusCard(
              accessibilityEnabled: accessibilityEnabled,
              tileAdded: tileAdded,
              hasApiKey: hasApiKey,
              onEnableAccessibility: onEnableAccessibility,
              onOpenSettings: onOpenSettings,
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: hasApiKey ? onCaptureNow : null,
              icon: const Icon(Icons.crop_free),
              label: const Text('Capture now (debug)'),
            ),
            const SizedBox(height: 10),
            Text(
              hasApiKey
                  ? 'TIP — the debug button captures immediately; the shade '
                      'shortcut waits for the notification panel to collapse.'
                  : 'No Gemini API key found. Put GEMINI_API_KEY in .env and '
                      'rebuild to enable capture.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: hasApiKey
                    ? theme.colorScheme.onSurfaceVariant
                    : theme.colorScheme.error,
                height: 1.4,
              ),
            ),
            if (lastResult != null) ...[
              const SizedBox(height: 20),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.notes),
                title: Text(
                  lastResult!.originalText.trim().isEmpty
                      ? '(empty capture)'
                      : lastResult!.originalText.trim().replaceAll('\n', ' '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  'detected: ${detectedLanguageLabel(lastResult!.detectedLanguage)}',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: onReopenLast,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.accessibilityEnabled,
    required this.tileAdded,
    required this.hasApiKey,
    required this.onEnableAccessibility,
    required this.onOpenSettings,
  });

  final bool accessibilityEnabled;
  final bool tileAdded;
  final bool hasApiKey;
  final Future<void> Function() onEnableAccessibility;
  final Future<void> Function() onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _StatusRow(
              icon: Icons.accessibility_new,
              title: 'Accessibility service',
              ok: accessibilityEnabled,
              okText: 'Enabled',
              badText: 'Required for capture',
            ),
            const SizedBox(height: 10),
            _StatusRow(
              icon: Icons.grid_view,
              title: 'Quick Settings tile',
              ok: tileAdded,
              okText: 'Added',
              badText: 'Not added',
            ),
            const SizedBox(height: 10),
            _StatusRow(
              icon: Icons.key,
              title: 'Gemini key',
              ok: hasApiKey,
              okText: 'Loaded from .env',
              badText: 'Missing',
            ),
            if (!accessibilityEnabled || !tileAdded) ...[
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton.tonal(
                  onPressed: !accessibilityEnabled
                      ? onEnableAccessibility
                      : onOpenSettings,
                  child: Text(
                    !accessibilityEnabled
                        ? 'Enable capture'
                        : 'Add the Quick Settings tile',
                  ),
                ),
              ),
            ],
            const SizedBox(height: 6),
            Text(
              'Everything is processed on demand. Only the cropped image leaves '
              'the device, straight to Gemini.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({
    required this.icon,
    required this.title,
    required this.ok,
    required this.okText,
    required this.badText,
  });

  final IconData icon;
  final String title;
  final bool ok;
  final String okText;
  final String badText;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 20, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 12),
        Expanded(child: Text(title, style: theme.textTheme.bodyMedium)),
        Icon(
          ok ? Icons.check_circle : Icons.error_outline,
          size: 18,
          color: ok ? theme.colorScheme.primary : theme.colorScheme.error,
        ),
        const SizedBox(width: 6),
        Text(
          ok ? okText : badText,
          style: theme.textTheme.bodySmall?.copyWith(
            color: ok ? theme.colorScheme.primary : theme.colorScheme.error,
          ),
        ),
      ],
    );
  }
}
