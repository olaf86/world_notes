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

    test('use the intended copyright notice on each legal page', () {
      expect(supportPage, contains('© 2026 Yuta Ogawa'));
      expect(privacyPage, contains('© 2026 World Notes'));
      expect(privacyPage, isNot(contains('© 2026 Yuta Ogawa')));
      expect(termsPage, contains('© 2026 World Notes'));
      expect(termsPage, isNot(contains('© 2026 Yuta Ogawa')));
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

    test('state enforceable consent, amendment, and liability safeguards', () {
      for (final marker in [
        '同意する旨の操作を完了した時点',
        '未成年者取消権',
        '必要かつ相当な範囲',
        '登録情報に重大な虚偽',
        '権利侵害の対象となる投稿コンテンツ',
        '無料期間終了後の価格',
        '行政機関、施設管理者、交通事業者その他の公的または権限ある情報源',
        '自己の責めに帰すべき事由がある範囲',
        '運営者の責めに帰すべき事由によらない外部サービスの行為',
        '合理的な範囲で、本サービスを安全かつ安定的に提供し',
        '合理的な安全管理措置を講じても防止困難なサイバー攻撃',
        '本条は、それ自体により',
        '消費者契約法上の消費者契約',
        '故意または重大な過失',
        '特別事情によって生じた損害',
        '利用者の一般の利益に適合する場合',
        '暴力団員でなくなった日から5年を経過しない者',
        '暴力的な要求行為',
        '本サービス内への掲示、登録されたメールアドレスへの送信',
        '事業譲渡、合併、会社分割',
        '第一審の付加的合意管轄裁判所',
        '分離可能性',
        '当該使用許諾に限りApple標準EULAが優先します',
      ]) {
        expect(termsPage, contains(marker));
      }
      expect(termsPage, isNot(contains('専属的合意管轄裁判所')));
      expect(termsPage, isNot(contains('Tokyo District Court')));
      expect(termsPage, contains('2026年9月26日'));
      expect(termsPage, isNot(contains('2026年9月22日')));
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
      expect(termsPage, contains('セカイノート運営者（以下「運営者」）'));
      expect(termsPage, isNot(contains('小川 雄大')));
      expect(termsPage, isNot(contains('Yuta Ogawa')));
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
        'セカイノート運営者（以下「運営者」）',
        '個人情報の保護に関する法律その他の適用法令',
        '法令に定める要件を満たす場合',
        '法令に基づく場合その他法令上認められる場合を除き',
        '本サービスの運営主体は個人です',
        '個人情報取扱事業者の氏名および住所は、本人またはその正当な代理人から請求があった場合',
        '本人確認および代理権の確認',
        '法令に従い遅滞なく開示します',
        '必要かつ適切な組織的および技術的安全管理措置',
        '適用法令上同意が必要な場合は、別途同意を取得します',
        '手数料は原則として徴収しません',
      ]) {
        expect(privacyPage, contains(marker));
      }
      for (final localizedOperator in [
        '運営者：セカイノート運営者',
        'Operator: Operator of World Notes',
        '운영자: 세계 일기 운영자',
        '运营者：世界日记运营者',
        '營運者：世界日記營運者',
      ]) {
        expect(privacyPage, contains(localizedOperator));
        expect(termsPage, contains(localizedOperator));
      }
      expect(privacyPage, isNot(contains('小川 雄大')));
      expect(privacyPage, isNot(contains('Yuta Ogawa')));
      expect(
        commercialTransactionsPage,
        contains('<dt>販売事業者</dt><dd>小川 雄大</dd>'),
      );
    });

    test('link role-based operator labels to the statutory disclosure', () {
      for (final language in supportedLanguages) {
        final link = '/commercial-transactions/?lang=$language';
        expect(privacyPage, contains('href="$link"'));
        expect(termsPage, contains('href="$link"'));
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
