import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:world_notes/core/theme/app_theme.dart';

void main() {
  const supportedLanguages = ['ja', 'en', 'ko', 'zh-Hans', 'zh-Hant'];
  const supportEmail = 'asobo.support@gmail.com';

  group('public legal pages', () {
    late String supportPage;
    late String privacyPage;
    late String termsPage;
    late String commercialTransactionsPage;
    late String invitationPage;
    late String stylesheet;
    late String languageScript;

    setUpAll(() async {
      supportPage = await File('public/support/index.html').readAsString();
      privacyPage = await File('public/privacy/index.html').readAsString();
      termsPage = await File('public/terms/index.html').readAsString();
      commercialTransactionsPage = await File(
        'public/commercial-transactions/index.html',
      ).readAsString();
      invitationPage = await File('public/index.html').readAsString();
      stylesheet = await File('public/assets/legal.css').readAsString();
      languageScript = await File(
        'public/assets/legal-language.js',
      ).readAsString();
    });

    test('publish the real support contact on both pages', () {
      expect(supportPage, contains('mailto:$supportEmail'));
      expect(privacyPage, contains('mailto:$supportEmail'));
      expect(termsPage, contains('mailto:$supportEmail'));
      expect(commercialTransactionsPage, contains('mailto:$supportEmail'));
      expect(supportPage, isNot(contains('support@worldnotes.asobo.dev')));
      expect(privacyPage, isNot(contains('support@worldnotes.asobo.dev')));
      expect(termsPage, isNot(contains('support@worldnotes.asobo.dev')));
      expect(
        commercialTransactionsPage,
        isNot(contains('support@worldnotes.asobo.dev')),
      );
    });

    test('name the legal rights holder in the copyright notice', () {
      expect(supportPage, contains('© 2026 Yuta Ogawa'));
      expect(privacyPage, contains('© 2026 Yuta Ogawa'));
      expect(termsPage, contains('© 2026 Yuta Ogawa'));
      expect(commercialTransactionsPage, contains('© 2026 Yuta Ogawa'));
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
          termsPage,
          contains('data-language-panel="$language"'),
          reason: 'Terms page is missing $language.',
        );
        expect(
          commercialTransactionsPage,
          contains('data-language-panel="$language"'),
          reason: 'Commercial transactions page is missing $language.',
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
      expect(termsPage, contains('href="/support/?lang='));
      expect(termsPage, contains('href="/privacy/?lang='));
      expect(
        commercialTransactionsPage,
        contains('data-language-target="/support/" href="/support/"'),
      );
      expect(
        commercialTransactionsPage,
        contains('data-language-target="/privacy/" href="/privacy/"'),
      );
      for (final page in [
        invitationPage,
        supportPage,
        privacyPage,
        termsPage,
        commercialTransactionsPage,
      ]) {
        expect(page, contains('href="/commercial-transactions/'));
      }
      expect(
        supportPage,
        contains('data-language-target="/support/" href="/support/"'),
      );
      expect(
        privacyPage,
        contains('data-language-target="/privacy/" href="/privacy/"'),
      );
      expect(
        termsPage,
        contains('data-language-target="/terms/" href="/terms/"'),
      );
      expect(
        commercialTransactionsPage,
        contains(
          'data-language-target="/commercial-transactions/" '
          'href="/commercial-transactions/"',
        ),
      );
      expect(
        languageScript,
        contains('document.querySelectorAll("[data-language-target]")'),
      );
      expect(languageScript, contains('encodeURIComponent(language)'));
    });

    test('use the app icon in both page headers', () {
      expect(File('public/assets/app_icon.svg').existsSync(), isTrue);
      expect(supportPage, contains('src="/assets/app_icon.svg"'));
      expect(privacyPage, contains('src="/assets/app_icon.svg"'));
      expect(termsPage, contains('src="/assets/app_icon.svg"'));
      expect(
        commercialTransactionsPage,
        contains('src="/assets/app_icon.svg"'),
      );
    });

    test('version static assets so Hosting updates bypass browser caches', () {
      expect(supportPage, contains('/assets/legal.css?v='));
      expect(supportPage, contains('/assets/legal-language.js?v='));
      expect(privacyPage, contains('/assets/legal.css?v='));
      expect(privacyPage, contains('/assets/legal-language.js?v='));
      expect(termsPage, contains('/assets/legal.css?v='));
      expect(termsPage, contains('/assets/legal-language.js?v='));
      expect(commercialTransactionsPage, contains('/assets/legal.css?v='));
      expect(
        commercialTransactionsPage,
        contains('/assets/legal-language.js?v='),
      );
    });

    test('share the app palette and adaptive surfaces across web pages', () {
      expect(stylesheet, contains('--accent: ${_cssHex(AppTheme.accent)}'));
      expect(stylesheet, contains('--accent: ${_cssHex(AppTheme.darkAccent)}'));
      expect(supportPage, contains('content="#f6f7f5"'));
      expect(privacyPage, contains('content="#101414"'));
      expect(termsPage, contains('content="#101414"'));
      expect(commercialTransactionsPage, contains('content="#101414"'));
      expect(invitationPage, contains('/assets/legal.css?v='));
      expect(invitationPage, contains('src="/assets/app_icon.svg"'));
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

    test('cover UGC, location safety, subscriptions, and standard EULA', () {
      expect(termsPage, contains('投稿コンテンツ'));
      expect(termsPage, contains('モデレーション、通報およびブロック'));
      expect(termsPage, contains('位置情報'));
      expect(termsPage, contains('自動更新'));
      expect(termsPage, contains('Apple標準EULA'));
      expect(
        termsPage,
        contains(
          'https://www.apple.com/legal/internet-services/itunes/dev/stdeula/',
        ),
      );
    });

    test('publish a complete commercial transactions disclosure', () {
      for (final marker in [
        '特定商取引法に基づく表記',
        '<dt>販売事業者</dt><dd>小川 雄大</dd>',
        '所在地・電話番号',
        '遅滞なく開示します',
        '月額プラン300円',
        '年額プラン2,980円',
        'セカイノートのアカウント',
        '解約',
        '返金',
      ]) {
        expect(commercialTransactionsPage, contains(marker));
      }
      expect(
        commercialTransactionsPage,
        isNot(contains('<dt>販売事業者</dt><dd>小川 雄大（World Notes）</dd>')),
      );
      expect(commercialTransactionsPage, isNot(contains('運営責任者')));
      expect(commercialTransactionsPage, isNot(contains('Operations manager')));
      expect(termsPage, contains('小川 雄大（以下「運営者」）'));
    });

    test('make the Japanese legal text authoritative', () {
      for (final page in [privacyPage, termsPage, commercialTransactionsPage]) {
        expect(page, contains('日本語版を正文とします'));
        expect(page, contains('日本語版が優先します'));
        expect(page, contains('権利を妨げるものではありません'));
      }
    });

    test('publish APPI operator and data-request information', () {
      for (final marker in [
        '個人情報取扱事業者は、小川 雄大です',
        '事業者の住所は、本人からご請求いただいた場合に遅滞なく開示します',
        '安全管理措置',
        '本人確認に必要な最小限の情報',
        '第三者提供の停止',
        '手数料は原則としていただきません',
      ]) {
        expect(privacyPage, contains(marker));
      }
    });

    test('publish the same minimum-age policy in every legal language', () {
      for (final marker in [
        '13歳以上',
        'at least 13 years',
        '만 13세 이상',
        '年满13周岁',
        '年滿13歲',
      ]) {
        expect(termsPage, contains(marker));
      }
      for (final marker in [
        '13歳未満',
        'under 13',
        '만 13세 미만',
        '未满13周岁',
        '未滿13歲',
      ]) {
        expect(privacyPage, contains(marker));
      }
      for (final marker in [
        '居住国・地域',
        'country or region',
        '거주 국가 또는 지역',
        '所在国家或地区',
        '所在國家或地區',
      ]) {
        expect(termsPage, contains(marker));
        expect(privacyPage, contains(marker));
      }
      for (final page in [termsPage, privacyPage]) {
        expect(page, isNot(contains('18歳未満')));
        expect(page, isNot(contains('under 18')));
        expect(page, isNot(contains('18세 미만')));
        expect(page, isNot(contains('未满18周岁')));
        expect(page, isNot(contains('未滿18歲')));
      }
    });
  });
}

String _cssHex(Color color) {
  final argb = color.toARGB32().toRadixString(16).padLeft(8, '0');
  return '#${argb.substring(2)}';
}
