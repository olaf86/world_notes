import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:world_notes/l10n/app_locale.dart';
import 'package:world_notes/l10n/app_localizations.dart';
import 'package:world_notes/l10n/localized_formatters.dart';

void main() {
  group('supported localizations', () {
    test('every declared locale loads a translated bundle', () {
      for (final locale in AppLocalizations.supportedLocales) {
        final l10n = lookupAppLocalizations(locale);
        expect(l10n.navMap, isNotEmpty, reason: locale.toLanguageTag());
        expect(
          l10n.messageCount(2),
          isNotEmpty,
          reason: locale.toLanguageTag(),
        );
      }
    });

    test('Chinese script variants resolve independently', () {
      final simplified = lookupAppLocalizations(
        const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'),
      );
      final traditional = lookupAppLocalizations(
        const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
      );

      expect(simplified.commonSave, '保存');
      expect(traditional.commonSave, '儲存');
    });

    test('screenshot locale parser accepts script tags', () {
      expect(appLocaleFromTag('zh_Hant').toLanguageTag(), 'zh-Hant');
      expect(appLocaleFromTag('zh-Hans').toLanguageTag(), 'zh-Hans');
      expect(appLocaleFromTag('ko').toLanguageTag(), 'ko');
      expect(appLocaleFromTag('unsupported').toLanguageTag(), 'ja');
    });
  });

  group('localized formatters', () {
    final l10n = lookupAppLocalizations(const Locale('en'));
    final now = DateTime.utc(2026, 7, 19, 12);

    test('formats relative time through ARB messages', () {
      expect(
        formatRelativeTime(
          l10n,
          now.subtract(const Duration(hours: 3)),
          now: now,
        ),
        '3 hours ago',
      );
    });

    test('formats remaining lifetime through ARB messages', () {
      expect(
        formatRemainingLifetime(
          l10n,
          now.add(const Duration(days: 4)),
          now: now,
        ),
        'Expires in 4 days',
      );
      expect(
        formatRemainingLifetime(
          l10n,
          now.subtract(const Duration(minutes: 1)),
          now: now,
        ),
        'Expired',
      );
    });
  });
}
