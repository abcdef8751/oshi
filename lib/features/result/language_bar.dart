import 'package:flutter/material.dart';

import '../../core/languages.dart';
import '../../core/theme.dart';

/// Bottom bar of the result sheet: locked `Auto` source, the current target
/// language (tap to change), and a reload button.
///
/// The bar owns the target-language picker but not the retranslation itself:
/// [onRetranslate] is invoked for an explicit reload, while picking a language
/// only writes [targetLanguage] so the owning sheet can listen and retranslate.
class LanguageBar extends StatelessWidget {
  const LanguageBar({
    super.key,
    required this.targetLanguage,
    required this.onRetranslate,
    this.busy = false,
  });

  final ValueNotifier<AppLanguage> targetLanguage;
  final VoidCallback onRetranslate;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: scheme.outline.withValues(alpha: 0.35)),
        ),
      ),
      child: ValueListenableBuilder<AppLanguage>(
        valueListenable: targetLanguage,
        builder: (context, language, _) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (busy)
                const LinearProgressIndicator(
                  minHeight: 2,
                  color: AppTheme.accent,
                  backgroundColor: Colors.transparent,
                ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                child: Row(
                  children: <Widget>[
                    _buildAutoSegment(context),
                    Expanded(child: _buildTargetSegment(context, language)),
                    IconButton(
                      key: const ValueKey<String>('language-bar-reload'),
                      tooltip: 'Retranslate',
                      onPressed: busy ? null : onRetranslate,
                      icon: const Icon(Icons.refresh_rounded),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Source language is always auto; the segment is intentionally muted but
  /// still tappable so it can explain itself.
  Widget _buildAutoSegment(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final muted = scheme.onSurfaceVariant.withValues(alpha: 0.55);

    return Tooltip(
      message: 'Source is always auto-detected',
      child: TextButton.icon(
        key: const ValueKey<String>('language-bar-auto'),
        onPressed: () {
          final messenger = ScaffoldMessenger.maybeOf(context);
          messenger
            ?..hideCurrentSnackBar()
            ..showSnackBar(
              const SnackBar(
                content: Text('Source is always auto-detected'),
                duration: Duration(seconds: 2),
              ),
            );
        },
        icon: Icon(Icons.language_rounded, size: 18, color: muted),
        label: Text('Auto', style: TextStyle(color: muted)),
        style: TextButton.styleFrom(
          foregroundColor: muted,
          padding: const EdgeInsets.symmetric(horizontal: 10),
        ),
      ),
    );
  }

  Widget _buildTargetSegment(BuildContext context, AppLanguage language) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return TextButton(
      key: const ValueKey<String>('language-bar-target'),
      onPressed: () => _openPicker(context),
      style: TextButton.styleFrom(alignment: Alignment.centerLeft),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Flexible(
            child: Text(
              language.name,
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
          if (language.nativeName != language.name) ...<Widget>[
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                language.nativeName,
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
          Icon(Icons.arrow_drop_down_rounded, color: scheme.onSurfaceVariant),
        ],
      ),
    );
  }

  Future<void> _openPicker(BuildContext context) async {
    final selected = await showModalBottomSheet<AppLanguage>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => _LanguagePicker(current: targetLanguage.value),
    );
    if (selected != null) {
      targetLanguage.value = selected;
    }
  }
}

class _LanguagePicker extends StatelessWidget {
  const _LanguagePicker({required this.current});

  final AppLanguage current;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.65,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: Text('Translate to', style: theme.textTheme.titleMedium),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.builder(
              itemCount: kLanguages.length,
              itemBuilder: (context, index) {
                final language = kLanguages[index];
                final selected = language == current;
                return ListTile(
                  key: ValueKey<String>('language-${language.code}'),
                  title: Text(language.name),
                  subtitle: language.nativeName == language.name
                      ? null
                      : Text(language.nativeName),
                  trailing: selected
                      ? const Icon(Icons.check_rounded, color: AppTheme.accent)
                      : null,
                  onTap: () => Navigator.of(context).pop(language),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
