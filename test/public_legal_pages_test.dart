import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  const supportedLanguages = ['ja', 'en', 'ko', 'zh-Hans', 'zh-Hant'];
  const supportEmail = 'asobo.support@gmail.com';

  group('public legal pages', () {
    late String supportPage;
    late String privacyPage;
    late String languageScript;

    setUpAll(() async {
      supportPage = await File('public/support/index.html').readAsString();
      privacyPage = await File('public/privacy/index.html').readAsString();
      languageScript = await File(
        'public/assets/legal-language.js',
      ).readAsString();
    });

    test('publish the real support contact on both pages', () {
      expect(supportPage, contains('mailto:$supportEmail'));
      expect(privacyPage, contains('mailto:$supportEmail'));
      expect(supportPage, isNot(contains('support@worldnotes.asobo.dev')));
      expect(privacyPage, isNot(contains('support@worldnotes.asobo.dev')));
    });

    test('include every supported app language', () {
      for (final language in supportedLanguages) {
        expect(
          supportPage,
          contains('data-language-panel="$language"'),
          reason: 'Support page is missing $language.',
        );
        expect(
          privacyPage,
          contains('data-language-panel="$language"'),
          reason: 'Privacy page is missing $language.',
        );
        expect(
          languageScript,
          contains('"$language"'),
          reason: 'Language selector is missing $language.',
        );
      }
    });

    test('link support and privacy pages to each other', () {
      expect(supportPage, contains('href="/privacy/?lang='));
      expect(privacyPage, contains('href="/support/?lang='));
    });

    test('provide account deletion and subscription guidance', () {
      expect(supportPage, contains('アカウントを削除する'));
      expect(supportPage, contains('Delete your account'));
      expect(
        supportPage,
        contains('https://apps.apple.com/account/subscriptions'),
      );
      expect(
        supportPage,
        contains('https://play.google.com/store/account/subscriptions'),
      );
    });

    test('disclose advertising and tracking', () {
      expect(privacyPage, contains('広告とトラッキング'));
      expect(privacyPage, contains('Advertising and tracking'));
      expect(privacyPage, contains('IDFA'));
      expect(privacyPage, contains('Google Mobile Ads'));
    });
  });
}
