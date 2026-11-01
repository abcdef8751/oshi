import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/languages.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../services/translator.dart';
import 'language_bar.dart';

/// Opens the result bottom sheet.
///
/// [initialResult] is the session cache: when present it is rendered
/// immediately and no network call is made. Otherwise [imagePng] is required
/// and a single analyze call is issued on first build.
Future<void> showResultSheet(
  BuildContext context, {
  required Translator translator,
  required ValueNotifier<AppLanguage> targetLanguage,
  Uint8List? imagePng,
  ScanResult? initialResult,
  String? initialTargetCode,
  ValueChanged<ScanResult>? onResult,
  Future<void> Function(String text)? copy,
}) async {
  assert(
    initialResult != null || imagePng != null,
    'imagePng is required when initialResult is null',
  );

  final maxHeight = MediaQuery.sizeOf(context).height * 0.85;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    constraints: BoxConstraints(maxHeight: maxHeight),
    builder: (context) => ResultSheet(
      translator: translator,
      targetLanguage: targetLanguage,
      imagePng: imagePng,
      initialResult: initialResult,
      initialTargetCode: initialTargetCode,
      onResult: onResult,
      copy: copy,
    ),
  );
}

/// Result sheet body. Public so widget tests can pump it directly; also usable
/// inside a modal bottom sheet.
class ResultSheet extends StatefulWidget {
  const ResultSheet({
    super.key,
    required this.translator,
    required this.targetLanguage,
    this.imagePng,
    this.initialResult,
    this.initialTargetCode,
    this.onResult,
    this.copy,
  }) : assert(
         initialResult != null || imagePng != null,
         'imagePng is required when initialResult is null',
       );

  final Translator translator;
  final ValueNotifier<AppLanguage> targetLanguage;
  final Uint8List? imagePng;
  final ScanResult? initialResult;

  /// Language the cached [initialResult] was translated into. Without it the
  /// sheet would assume the current target and show a stale translation.
  final String? initialTargetCode;
  final ValueChanged<ScanResult>? onResult;

  /// Overrides the clipboard write. The overlay has no Activity, so it routes
  /// the copy through a native channel instead of the platform plugin.
  final Future<void> Function(String text)? copy;

  @override
  State<ResultSheet> createState() => _ResultSheetState();
}

class _ResultSheetState extends State<ResultSheet> {
  /// One entry per `(originalText, targetCode)`, scoped to this sheet.
  final Map<String, String> _translationCache = <String, String>{};

  /// Increments per retranslate request so stale responses can be dropped.
  int _requestId = 0;

  ScanResult? _result;
  bool _analyzing = false;
  bool _copied = false;
  bool _copyFailed = false;
  Timer? _copiedTimer;
  TranslatorException? _analyzeError;

  bool _busy = false;
  TranslatorException? _retranslateError;

  /// Which variant the body, copy and toggle act on. The transcription is
  /// shown first — you should see what was on screen, with the translation one
  /// tap away.
  bool _showingTranslation = false;

  late AppLanguage _activeLanguage;

  @override
  void initState() {
    super.initState();
    _activeLanguage = widget.targetLanguage.value;

    final initial = widget.initialResult;
    if (initial != null) {
      _result = initial;
      final cachedCode = widget.initialTargetCode ?? _activeLanguage.code;
      _translationCache[_cacheKey(initial.originalText, cachedCode)] =
          initial.translation;
      if (cachedCode != _activeLanguage.code) {
        // The session cache is in another language than the one selected now.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) unawaited(_retranslate());
        });
      }
    } else {
      _analyzing = true;
      // Defer so a first frame with the progress state is guaranteed and we
      // never call setState during initState.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          unawaited(_analyze());
        }
      });
    }

    widget.targetLanguage.addListener(_handleTargetLanguageChanged);
  }

  @override
  void didUpdateWidget(covariant ResultSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.targetLanguage != widget.targetLanguage) {
      oldWidget.targetLanguage.removeListener(_handleTargetLanguageChanged);
      _activeLanguage = widget.targetLanguage.value;
      widget.targetLanguage.addListener(_handleTargetLanguageChanged);
    }
  }

  @override
  void dispose() {
    _copiedTimer?.cancel();
    widget.targetLanguage.removeListener(_handleTargetLanguageChanged);
    super.dispose();
  }

  static String _cacheKey(String originalText, String targetCode) =>
      '$targetCode\u0000$originalText';

  Future<void> _analyze() async {
    final png = widget.imagePng;
    if (png == null) {
      if (!mounted) return;
      setState(() {
        _analyzing = false;
        _analyzeError = const TranslatorException(
          TranslatorErrorKind.unknown,
          'No image to analyze',
        );
      });
      return;
    }

    final target = widget.targetLanguage.value;
    _activeLanguage = target;

    try {
      final result = await widget.translator.analyzeImage(
        png,
        targetCode: target.code,
        targetName: target.name,
      );
      if (!mounted) return;
      setState(() {
        _analyzing = false;
        _analyzeError = null;
        _result = result;
        _showingTranslation = false;
      });
      _translationCache[_cacheKey(result.originalText, target.code)] =
          result.translation;
      widget.onResult?.call(result);

      // The user may have changed the target while the analyze call was in
      // flight; honor the newest selection.
      if (widget.targetLanguage.value.code != target.code) {
        unawaited(_retranslate());
      }
    } on TranslatorException catch (error) {
      if (!mounted) return;
      setState(() {
        _analyzing = false;
        _analyzeError = error;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _analyzing = false;
        _analyzeError = TranslatorException(
          TranslatorErrorKind.unknown,
          error.toString(),
        );
      });
    }
  }

  void _retryAnalyze() {
    if (_analyzing) return;
    setState(() {
      _analyzing = true;
      _analyzeError = null;
    });
    unawaited(_analyze());
  }

  void _handleTargetLanguageChanged() {
    final language = widget.targetLanguage.value;
    if (language.code == _activeLanguage.code) return;
    _activeLanguage = language;
    if (_result == null) return;
    unawaited(_retranslate());
  }

  Future<void> _retranslate({bool force = false}) async {
    final result = _result;
    if (result == null) return;

    final language = widget.targetLanguage.value;
    final key = _cacheKey(result.originalText, language.code);

    if (!force) {
      final cached = _translationCache[key];
      if (cached != null) {
        _requestId++;
        setState(() {
          _busy = false;
          _retranslateError = null;
          _result = result.withTranslation(cached);
        });
        return;
      }
    }

    final requestId = ++_requestId;
    setState(() {
      _busy = true;
      _retranslateError = null;
    });

    try {
      final translation = await widget.translator.translateText(
        result.originalText,
        targetCode: language.code,
        targetName: language.name,
      );
      if (!mounted || requestId != _requestId) return;
      _translationCache[key] = translation;
      final updated = result.withTranslation(translation);
      setState(() {
        _busy = false;
        _result = updated;
      });
      widget.onResult?.call(updated);
    } on TranslatorException catch (error) {
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _busy = false;
        _retranslateError = error;
      });
    } catch (error) {
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _busy = false;
        _retranslateError = TranslatorException(
          TranslatorErrorKind.unknown,
          error.toString(),
        );
      });
    }
  }

  String _messageFor(TranslatorException error) {
    switch (error.kind) {
      case TranslatorErrorKind.rateLimited:
        final seconds = error.retryAfter?.inSeconds;
        if (seconds != null && seconds > 0) {
          return 'Rate limit reached — retry in ${seconds}s';
        }
        return 'Rate limit reached — try again shortly';
      case TranslatorErrorKind.network:
        return 'No connection';
      case TranslatorErrorKind.badRequest:
        return 'Check the API key';
      case TranslatorErrorKind.server:
        return 'Gemini is having trouble';
      case TranslatorErrorKind.unknown:
        final message = error.message.trim();
        return message.isEmpty ? 'Something went wrong' : message;
    }
  }

  Future<void> _copyCurrentVariant() async {
    final result = _result;
    if (result == null) return;

    final text = _showingTranslation ? result.translation : result.originalText;
    try {
      final writer = widget.copy;
      if (writer != null) {
        await writer(text);
      } else {
        await Clipboard.setData(ClipboardData(text: text));
      }
    } catch (_) {
      if (!mounted) return;
      _copiedTimer?.cancel();
      setState(() => _copyFailed = true);
      _copiedTimer = Timer(const Duration(milliseconds: 1600), () {
        if (mounted) setState(() => _copyFailed = false);
      });
      return;
    }
    if (!mounted) return;

    // The app-level SnackBar would render underneath the modal sheet, so the
    // confirmation lives on the button itself.
    _copiedTimer?.cancel();
    setState(() {
      _copied = true;
      _copyFailed = false;
    });
    _copiedTimer = Timer(const Duration(milliseconds: 1600), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  void _closeSheet() {
    final navigator = Navigator.maybeOf(context);
    if (navigator != null && navigator.canPop()) {
      navigator.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _buildHeader(context),
        if (_retranslateError != null)
          _buildRetranslateError(context, _retranslateError!),
        Flexible(child: _buildBody(context)),
        if (result != null) _buildActions(context, result),
        LanguageBar(
          targetLanguage: widget.targetLanguage,
          busy: _busy,
          onRetranslate: () => unawaited(_retranslate(force: true)),
        ),
      ],
    );
  }

  Widget _buildHeader(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final result = _result;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 8),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: result == null
                  ? Text(
                      'Reading…',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    )
                  : Container(
                      key: const ValueKey<String>('result-detected-chip'),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.accent.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        'detected: '
                        '${detectedLanguageLabel(result.detectedLanguage)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: AppTheme.accent,
                        ),
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            kProviderLabel,
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    if (_analyzing && _result == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const CircularProgressIndicator(color: AppTheme.accent),
            const SizedBox(height: 16),
            Text(
              'Reading text…',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    final analyzeError = _analyzeError;
    if (_result == null && analyzeError != null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.error_outline_rounded, color: scheme.error, size: 32),
            const SizedBox(height: 12),
            Text(
              _messageFor(analyzeError),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: <Widget>[
                FilledButton.icon(
                  key: const ValueKey<String>('result-analyze-retry'),
                  onPressed: _retryAnalyze,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('Retry'),
                ),
                TextButton(
                  key: const ValueKey<String>('result-analyze-close'),
                  onPressed: _closeSheet,
                  child: const Text('Close'),
                ),
              ],
            ),
          ],
        ),
      );
    }

    final result = _result;
    if (result == null) {
      return const SizedBox.shrink();
    }

    final text = _showingTranslation ? result.translation : result.originalText;

    if (result.originalText.trim().isEmpty && text.trim().isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.search_off_rounded,
                color: scheme.onSurfaceVariant, size: 32),
            const SizedBox(height: 12),
            Text(
              'No text found in that selection',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: 6),
            Text(
              'Try a tighter box around the text, or a larger one.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
      child: Container(
        key: const ValueKey<String>('result-text-container'),
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: scheme.outline.withValues(alpha: 0.35)),
        ),
        child: SelectableText(
          text,
          style: theme.textTheme.bodyLarge?.copyWith(
            fontSize: 17,
            height: 1.45,
          ),
        ),
      ),
    );
  }

  Widget _buildRetranslateError(
    BuildContext context,
    TranslatorException error,
  ) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      key: const ValueKey<String>('result-retranslate-error'),
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: scheme.errorContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: <Widget>[
          Icon(
            Icons.error_outline_rounded,
            size: 18,
            color: scheme.onErrorContainer,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _messageFor(error),
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onErrorContainer,
              ),
            ),
          ),
          TextButton(
            key: const ValueKey<String>('result-retranslate-retry'),
            onPressed: () => unawaited(_retranslate(force: true)),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _buildActions(BuildContext context, ScanResult result) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 2),
      child: Row(
        children: <Widget>[
          TextButton.icon(
            key: const ValueKey<String>('result-copy'),
            onPressed: _copyCurrentVariant,
            icon: Icon(
              _copied
                  ? Icons.check_rounded
                  : (_copyFailed ? Icons.error_outline : Icons.copy_rounded),
              size: 18,
            ),
            label: Text(
              _copied ? 'Copied' : (_copyFailed ? 'Copy failed' : 'Copy'),
            ),
          ),
          const Spacer(),
          if (!result.isTranslationIdentical)
            TextButton.icon(
              key: const ValueKey<String>('result-toggle'),
              onPressed: () => setState(() {
                _showingTranslation = !_showingTranslation;
              }),
              icon: const Icon(Icons.swap_horiz_rounded, size: 18),
              label: Text(_showingTranslation ? 'Original' : 'Translation'),
            ),
        ],
      ),
    );
  }
}
