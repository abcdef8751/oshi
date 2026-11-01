import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persisted user preferences. Backed by [SharedPreferences]; notifies
/// listeners so the settings screen and app shell stay in sync.
class Settings extends ChangeNotifier {
  Settings._(this._prefs, this._targetLangCode, this._notificationEnabled,
      this._tilePromptShown);

  static const String keyTargetLang = 'target_lang';
  static const String keyNotificationEnabled = 'notification_enabled';
  static const String keyTilePromptShown = 'tile_prompt_shown';

  final SharedPreferences _prefs;
  String _targetLangCode;
  bool _notificationEnabled;
  bool _tilePromptShown;

  static Future<Settings> load() async {
    final prefs = await SharedPreferences.getInstance();
    return Settings._(
      prefs,
      prefs.getString(keyTargetLang) ?? 'en',
      prefs.getBool(keyNotificationEnabled) ?? true,
      prefs.getBool(keyTilePromptShown) ?? false,
    );
  }

  /// In-memory instance for tests and previews.
  @visibleForTesting
  factory Settings.memory({
    String targetLangCode = 'en',
    bool notificationEnabled = true,
    bool tilePromptShown = false,
    SharedPreferences? prefs,
  }) {
    return Settings._(
      prefs ?? _MemoryPrefs(),
      targetLangCode,
      notificationEnabled,
      tilePromptShown,
    );
  }

  String get targetLangCode => _targetLangCode;

  Future<void> setTargetLangCode(String code) async {
    if (code == _targetLangCode) return;
    _targetLangCode = code;
    notifyListeners();
    await _prefs.setString(keyTargetLang, code);
  }

  bool get notificationEnabled => _notificationEnabled;

  Future<void> setNotificationEnabled(bool enabled) async {
    if (enabled == _notificationEnabled) return;
    _notificationEnabled = enabled;
    notifyListeners();
    await _prefs.setBool(keyNotificationEnabled, enabled);
  }

  bool get tilePromptShown => _tilePromptShown;

  Future<void> setTilePromptShown(bool shown) async {
    if (shown == _tilePromptShown) return;
    _tilePromptShown = shown;
    notifyListeners();
    await _prefs.setBool(keyTilePromptShown, shown);
  }
}

/// Minimal in-memory stand-in used by [Settings.memory] so tests don't need a
/// platform plugin. Only the write path is ever exercised through it.
class _MemoryPrefs implements SharedPreferences {
  final Map<String, Object?> _values = {};

  @override
  Future<bool> setString(String key, String value) async {
    _values[key] = value;
    return true;
  }

  @override
  Future<bool> setBool(String key, bool value) async {
    _values[key] = value;
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
