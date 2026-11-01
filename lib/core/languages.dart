/// The small, fixed list of target languages Oshi offers.
///
/// Source language is always `auto`; only the target is user-selectable.
class AppLanguage {
  const AppLanguage(this.code, this.name, this.nativeName);

  /// BCP-47 code passed to Gemini, e.g. `ja`, `zh-Hans`.
  final String code;

  /// English display name, e.g. `Japanese`.
  final String name;

  /// Endonym, e.g. `日本語`.
  final String nativeName;

  @override
  String toString() => '$name ($code)';

  @override
  bool operator ==(Object other) => other is AppLanguage && other.code == code;

  @override
  int get hashCode => code.hashCode;
}

/// Ordered by rough personal usefulness, English first.
const List<AppLanguage> kLanguages = <AppLanguage>[
  AppLanguage('en', 'English', 'English'),
  AppLanguage('ja', 'Japanese', '日本語'),
  AppLanguage('zh-Hans', 'Chinese (Simplified)', '简体中文'),
  AppLanguage('zh-Hant', 'Chinese (Traditional)', '繁體中文'),
  AppLanguage('ko', 'Korean', '한국어'),
  AppLanguage('es', 'Spanish', 'Español'),
  AppLanguage('fr', 'French', 'Français'),
  AppLanguage('de', 'German', 'Deutsch'),
  AppLanguage('pt', 'Portuguese', 'Português'),
  AppLanguage('it', 'Italian', 'Italiano'),
  AppLanguage('ru', 'Russian', 'Русский'),
  AppLanguage('uk', 'Ukrainian', 'Українська'),
  AppLanguage('ar', 'Arabic', 'العربية'),
  AppLanguage('he', 'Hebrew', 'עברית'),
  AppLanguage('hi', 'Hindi', 'हिन्दी'),
  AppLanguage('th', 'Thai', 'ไทย'),
  AppLanguage('vi', 'Vietnamese', 'Tiếng Việt'),
  AppLanguage('id', 'Indonesian', 'Bahasa Indonesia'),
  AppLanguage('tr', 'Turkish', 'Türkçe'),
  AppLanguage('pl', 'Polish', 'Polski'),
  AppLanguage('nl', 'Dutch', 'Nederlands'),
  AppLanguage('sv', 'Swedish', 'Svenska'),
  AppLanguage('da', 'Danish', 'Dansk'),
  AppLanguage('no', 'Norwegian', 'Norsk'),
  AppLanguage('fi', 'Finnish', 'Suomi'),
  AppLanguage('cs', 'Czech', 'Čeština'),
  AppLanguage('el', 'Greek', 'Ελληνικά'),
  AppLanguage('hu', 'Hungarian', 'Magyar'),
  AppLanguage('ro', 'Romanian', 'Română'),
  AppLanguage('fa', 'Persian', 'فارسی'),
  AppLanguage('ms', 'Malay', 'Bahasa Melayu'),
];

const AppLanguage kEnglish = AppLanguage('en', 'English', 'English');

/// Looks up a language by BCP-47 code, tolerating case and `-`/`_` differences.
///
/// Falls back to [kEnglish] for unknown codes.
AppLanguage languageForCode(String? code) {
  if (code == null || code.isEmpty) return kEnglish;
  final normalized = code.replaceAll('_', '-').toLowerCase();
  for (final lang in kLanguages) {
    if (lang.code.toLowerCase() == normalized) return lang;
  }
  // `ja-JP` -> `ja`, `zh-CN` -> `zh-Hans`.
  final base = normalized.split('-').first;
  for (final lang in kLanguages) {
    if (lang.code.toLowerCase() == base) return lang;
  }
  return kEnglish;
}

/// Endonym for a detected language code, for the `detected: …` chip.
///
/// Unknown codes (e.g. `und` or something new) are rendered upper-cased so the
/// chip still says something truthful.
String detectedLanguageLabel(String code) {
  if (code.isEmpty) return '?';
  final normalized = code.replaceAll('_', '-').toLowerCase();
  for (final lang in kLanguages) {
    if (lang.code.toLowerCase() == normalized) return lang.nativeName;
  }
  final base = normalized.split('-').first;
  for (final lang in kLanguages) {
    if (lang.code.toLowerCase() == base) return lang.nativeName;
  }
  return base.toUpperCase();
}
