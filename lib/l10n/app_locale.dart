import 'package:flutter/widgets.dart';

const supportedAppLocaleTags = <String>{'en', 'ja', 'zh_Hant', 'zh_Hans', 'ko'};

const appLanguagePreferenceKey = 'app_language_preference';

/// Region-to-script policy for Chinese locales that do not include an
/// explicit script code. Keeping it as data makes the supported regional
/// assumptions visible and independently maintainable.
const _chineseScriptByRegion = <String, String>{
  'CN': 'Hans',
  'SG': 'Hans',
  'TW': 'Hant',
  'HK': 'Hant',
  'MO': 'Hant',
};

/// The language choice saved for an account and mirrored on the current
/// device. [system] deliberately has no locale so Flutter keeps following the
/// platform's preferred languages.
enum AppLanguagePreference {
  system('system', null),
  english('en', Locale('en')),
  japanese('ja', Locale('ja')),
  korean('ko', Locale('ko')),
  simplifiedChinese(
    'zh-Hans',
    Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'),
  ),
  traditionalChinese(
    'zh-Hant',
    Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
  );

  const AppLanguagePreference(this.storageValue, this.locale);

  final String storageValue;
  final Locale? locale;

  static AppLanguagePreference? tryParse(String? value) {
    final normalized = value?.trim().replaceAll('_', '-');
    for (final preference in values) {
      if (preference.storageValue == normalized) return preference;
    }
    return null;
  }

  static AppLanguagePreference fromLocalStorage(String? value) =>
      tryParse(value) ?? system;
}

/// Parses the locale tags accepted by dart-defines and screenshot scripts.
Locale appLocaleFromTag(String tag) {
  final normalized = tag.replaceAll('-', '_');
  if (!supportedAppLocaleTags.contains(normalized)) return const Locale('ja');
  final parts = normalized.split('_');
  if (parts.length == 2) {
    return Locale.fromSubtags(languageCode: parts[0], scriptCode: parts[1]);
  }
  return Locale(parts[0]);
}

/// Resolves Chinese locales that arrive with a region but no script code.
/// Flutter's default resolver can otherwise fall back to generic Chinese,
/// which is simplified in this app even for Taiwan, Hong Kong, or Macao.
Locale resolveAppLocale(
  List<Locale>? preferredLocales,
  Iterable<Locale> supportedLocales,
) {
  final normalizedLocales = preferredLocales
      ?.map(_normalizeChineseLocale)
      .toList(growable: false);

  return basicLocaleListResolution(normalizedLocales, supportedLocales);
}

Locale _normalizeChineseLocale(Locale locale) {
  if (locale.languageCode != 'zh') return locale;

  final explicitScript = locale.scriptCode;
  if (explicitScript == 'Hans' || explicitScript == 'Hant') {
    return Locale.fromSubtags(languageCode: 'zh', scriptCode: explicitScript);
  }

  final scriptFromRegion = _chineseScriptByRegion[locale.countryCode];
  if (scriptFromRegion == null) return locale;
  return Locale.fromSubtags(languageCode: 'zh', scriptCode: scriptFromRegion);
}
