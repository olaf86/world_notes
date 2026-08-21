import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:world_notes/l10n/app_locale.dart';
import 'package:world_notes/l10n/l10n.dart';
import 'package:world_notes/l10n/localized_formatters.dart';
import 'package:world_notes/l10n/presentation_labels.dart';

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
        expect(
          l10n.noteThemeChangeTitle,
          isNotEmpty,
          reason: locale.toLanguageTag(),
        );
        expect(
          l10n.noteThemeChangeDescription,
          isNotEmpty,
          reason: locale.toLanguageTag(),
        );
        expect(
          l10n.reportNoteTitle,
          isNotEmpty,
          reason: locale.toLanguageTag(),
        );
        expect(
          l10n.reportReasonSpam,
          isNotEmpty,
          reason: locale.toLanguageTag(),
        );
        expect(
          l10n.proPlanName,
          '${l10n.appName} PRO',
          reason: locale.toLanguageTag(),
        );
        for (final emptyStateLabel in [
          l10n.noNotifications,
          l10n.noFollowers,
          l10n.noFollowing,
          l10n.noFootprints,
          l10n.noFootprintsDescription,
          l10n.noAccessMembers,
          l10n.noModerationReviews,
          l10n.noteCreatedPinImageUploadFailed,
          l10n.noteCreateNetworkError,
          l10n.noteCreateAuthenticationRequired,
          l10n.noteCreateFailed,
          l10n.noteCreateUnexpectedError,
        ]) {
          expect(emptyStateLabel, isNotEmpty, reason: locale.toLanguageTag());
        }
        for (final newlyLocalizedLabel in [
          l10n.confirmPasswordLabel,
          l10n.patternSetupInstruction,
          l10n.messageContentHint,
          l10n.mapPinCropInstruction,
          l10n.footprintsTitle,
          l10n.sensitiveContent,
          l10n.adminAccessRequired,
        ]) {
          expect(
            newlyLocalizedLabel,
            isNotEmpty,
            reason: locale.toLanguageTag(),
          );
        }
        for (final preference in AppLanguagePreference.values) {
          expect(
            preference.localizedLabel(l10n),
            isNotEmpty,
            reason: '${locale.toLanguageTag()}: ${preference.name}',
          );
        }
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
      expect(simplified.appName, '世界日记');
      expect(traditional.appName, '世界日記');
      expect(simplified.proPlanName, '世界日记 PRO');
      expect(traditional.proPlanName, '世界日記 PRO');
    });

    test('PRO plan name uses each localized app name', () {
      expect(
        lookupAppLocalizations(const Locale('en')).proPlanName,
        'World Notes PRO',
      );
      expect(
        lookupAppLocalizations(const Locale('ja')).proPlanName,
        'セカイノート PRO',
      );
      expect(
        lookupAppLocalizations(const Locale('ko')).proPlanName,
        '세계 일기 PRO',
      );
    });

    test('screenshot locale parser accepts script tags', () {
      expect(appLocaleFromTag('zh_Hant').toLanguageTag(), 'zh-Hant');
      expect(appLocaleFromTag('zh-Hans').toLanguageTag(), 'zh-Hans');
      expect(appLocaleFromTag('ko').toLanguageTag(), 'ko');
      expect(appLocaleFromTag('unsupported').toLanguageTag(), 'ja');
    });

    test('language preferences parse account and local storage values', () {
      expect(
        AppLanguagePreference.tryParse('zh_Hant'),
        AppLanguagePreference.traditionalChinese,
      );
      expect(
        AppLanguagePreference.tryParse('ko'),
        AppLanguagePreference.korean,
      );
      expect(AppLanguagePreference.tryParse('unsupported'), isNull);
      expect(
        AppLanguagePreference.fromLocalStorage('unsupported'),
        AppLanguagePreference.system,
      );
    });

    test(
      'system Chinese locales resolve country codes to the right script',
      () {
        const simplifiedRegions = ['CN', 'SG'];
        const traditionalRegions = ['TW', 'HK', 'MO'];

        for (final region in simplifiedRegions) {
          final locale = resolveAppLocale([
            Locale('zh', region),
          ], AppLocalizations.supportedLocales);
          expect(locale.toLanguageTag(), 'zh-Hans', reason: region);
        }
        for (final region in traditionalRegions) {
          final locale = resolveAppLocale([
            Locale('zh', region),
          ], AppLocalizations.supportedLocales);
          expect(locale.toLanguageTag(), 'zh-Hant', reason: region);
        }
      },
    );

    test('system locale resolution keeps Flutter fallback behavior', () {
      final japanese = resolveAppLocale(const [
        Locale('ja', 'JP'),
      ], AppLocalizations.supportedLocales);
      final unsupported = resolveAppLocale(const [
        Locale('fr', 'FR'),
      ], AppLocalizations.supportedLocales);

      expect(japanese.languageCode, 'ja');
      expect(unsupported.languageCode, 'en');
    });

    test('Chinese normalization preserves preferred-locale order', () {
      final locale = resolveAppLocale(const [
        Locale('ja', 'JP'),
        Locale('zh', 'TW'),
      ], AppLocalizations.supportedLocales);

      expect(locale.languageCode, 'ja');
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
