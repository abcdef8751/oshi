import 'package:flutter/material.dart';

import '../../core/languages.dart';
import '../../core/settings.dart';
import '../../native/capture_channel.dart';
import '../../services/translator.dart';

/// How a platform-backed row is currently doing. Platform calls are allowed to
/// fail — a failed query degrades to "Unknown" rather than throwing.
enum _LoadState { loading, ready, failed }

/// Settings for capture, translation, notifications and the about blurb.
///
/// Reads and writes go through the injected [Settings]; all native calls go
/// through [CaptureChannel] so the screen is fully testable.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.settings,
    required this.captureChannel,
  });

  final Settings settings;
  final CaptureChannel captureChannel;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  _LoadState _accessibilityState = _LoadState.loading;
  bool _accessibilityEnabled = false;

  _LoadState _tileState = _LoadState.loading;
  bool _tileAdded = false;

  bool _notificationBusy = false;

  @override
  void initState() {
    super.initState();
    widget.settings.addListener(_onSettingsChanged);
    _refreshAccessibility();
    _refreshTile();
  }

  @override
  void didUpdateWidget(covariant SettingsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.settings != widget.settings) {
      oldWidget.settings.removeListener(_onSettingsChanged);
      widget.settings.addListener(_onSettingsChanged);
    }
    if (oldWidget.captureChannel != widget.captureChannel) {
      _refreshAccessibility();
      _refreshTile();
    }
  }

  @override
  void dispose() {
    widget.settings.removeListener(_onSettingsChanged);
    super.dispose();
  }

  void _onSettingsChanged() {
    if (!mounted) return;
    setState(() {});
  }

  /// Runs [call], turning any failure into `null` so rows can say "Unknown".
  Future<T?> _guard<T>(Future<T> Function() call) async {
    try {
      return await call();
    } catch (_) {
      return null;
    }
  }

  Future<void> _refreshAccessibility() async {
    final enabled = await _guard(widget.captureChannel.isAccessibilityEnabled);
    if (!mounted) return;
    setState(() {
      if (enabled == null) {
        _accessibilityState = _LoadState.failed;
        _accessibilityEnabled = false;
      } else {
        _accessibilityState = _LoadState.ready;
        _accessibilityEnabled = enabled;
      }
    });
  }

  Future<void> _refreshTile() async {
    final added = await _guard(widget.captureChannel.isTileAdded);
    if (!mounted) return;
    setState(() {
      if (added == null) {
        _tileState = _LoadState.failed;
        _tileAdded = false;
      } else {
        _tileState = _LoadState.ready;
        _tileAdded = added;
      }
    });
  }

  Future<void> _openAccessibilitySettings() async {
    try {
      await widget.captureChannel.openAccessibilitySettings();
    } catch (error) {
      debugPrint('Could not open accessibility settings: $error');
    }
    if (!mounted) return;
    await _refreshAccessibility();
  }

  Future<void> _addTile() async {
    try {
      await widget.captureChannel.openTileSettings();
    } catch (error) {
      debugPrint('Could not open Quick Settings: $error');
    }
    await widget.settings.setTilePromptShown(true);
    if (!mounted) return;
    await _refreshTile();
  }

  Future<void> _setNotificationEnabled(bool value) async {
    if (value == widget.settings.notificationEnabled) return;
    setState(() => _notificationBusy = true);
    try {
      if (value) {
        await widget.captureChannel.postNotification();
      } else {
        await widget.captureChannel.cancelNotification();
      }
      await widget.settings.setNotificationEnabled(value);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not update the notification')),
      );
    } finally {
      if (mounted) setState(() => _notificationBusy = false);
    }
  }

  Future<void> _pickTargetLanguage() async {
    final current = languageForCode(widget.settings.targetLangCode);
    final selected = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) {
        final theme = Theme.of(context);
        return ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.7,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                child: Text(
                  'Default target language',
                  style: theme.textTheme.titleMedium,
                ),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final language in kLanguages)
                      RadioListTile<String>(
                        key: ValueKey('language-option-${language.code}'),
                        value: language.code,
                        groupValue: current.code,
                        onChanged: (value) => Navigator.of(context).pop(value),
                        title: Text(language.name),
                        subtitle: language.nativeName == language.name
                            ? null
                            : Text(language.nativeName),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
    if (!mounted || selected == null) return;
    await widget.settings.setTargetLangCode(selected);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = widget.settings;
    final language = languageForCode(settings.targetLangCode);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          const _SectionHeader('Capture'),
          _buildAccessibilityTile(theme),
          _buildTileRow(theme),
          const _SectionHeader('Translation'),
          ListTile(
            title: const Text('Default target language'),
            subtitle: Text(
              language.nativeName == language.name
                  ? language.name
                  : '${language.name} · ${language.nativeName}',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: _pickTargetLanguage,
          ),
          const _SectionHeader('Notification'),
          SwitchListTile(
            title: const Text('Ongoing capture shortcut'),
            subtitle: const Text(
              'Persistent entry in the notification shade.',
            ),
            value: settings.notificationEnabled,
            onChanged:
                _notificationBusy ? null : _setNotificationEnabled,
          ),
          const _SectionHeader('About'),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
            child: Text(
              'Screenshots are cropped on-device. Only the crop is sent to '
              'Gemini with your API key.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
            child: Text(
              'Oshi v1.0.0 — personal sideload build',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Text(
              'Provider · $kProviderLabel',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAccessibilityTile(ThemeData theme) {
    final scheme = theme.colorScheme;
    final String subtitle;
    final Widget trailing;

    switch (_accessibilityState) {
      case _LoadState.loading:
        subtitle = 'Checking…';
        trailing = const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        );
      case _LoadState.failed:
        subtitle = 'Unknown';
        trailing = _enableCaptureButton();
      case _LoadState.ready:
        if (_accessibilityEnabled) {
          subtitle = 'Enabled';
          trailing = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check_circle, color: scheme.primary),
              IconButton(
                tooltip: 'Refresh accessibility status',
                onPressed: _refreshAccessibility,
                icon: const Icon(Icons.refresh),
              ),
            ],
          );
        } else {
          subtitle = 'Required to take screenshots';
          trailing = _enableCaptureButton();
        }
    }

    return ListTile(
      title: const Text('Accessibility service'),
      subtitle: Text(subtitle),
      trailing: trailing,
    );
  }

  Widget _enableCaptureButton() {
    return FilledButton(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 40),
        padding: const EdgeInsets.symmetric(horizontal: 16),
      ),
      onPressed: _openAccessibilitySettings,
      child: const Text('Enable capture'),
    );
  }

  Widget _buildTileRow(ThemeData theme) {
    final scheme = theme.colorScheme;

    if (_tileState == _LoadState.loading) {
      return const ListTile(
        title: Text('Quick Settings tile'),
        subtitle: Text('Checking…'),
        trailing: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    if (_tileState == _LoadState.failed) {
      return ListTile(
        title: const Text('Quick Settings tile'),
        subtitle: const Text('Unknown'),
        trailing: TextButton(
          onPressed: _addTile,
          child: const Text('Add'),
        ),
      );
    }

    if (_tileAdded) {
      return ListTile(
        title: const Text('Quick Settings tile'),
        subtitle: const Text('Added'),
        trailing: Icon(Icons.check_circle, color: scheme.primary),
      );
    }

    if (widget.settings.tilePromptShown) {
      return ListTile(
        title: const Text('Quick Settings tile — Not added'),
        trailing: TextButton(
          onPressed: _addTile,
          child: const Text('Add'),
        ),
      );
    }

    return Card(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      color: scheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Add the Quick Settings tile',
              style: theme.textTheme.titleMedium?.copyWith(
                color: scheme.onPrimaryContainer,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Pin Oshi to Quick Settings to capture from anywhere without '
              'opening the app.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onPrimaryContainer.withValues(alpha: 0.85),
              ),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: _addTile,
                child: const Text('Add tile'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
      child: Text(
        title,
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}
