import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:world_notes/l10n/app_locale.dart';
import 'package:world_notes/l10n/app_localizations.dart';
import 'package:world_notes/presentation/providers/providers.dart';
import 'package:world_notes/presentation/screens/auth/sign_in_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('exposes stable selectors for sign-in automation', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();

    await tester.pumpWidget(_testApp(preferences));

    expect(find.bySemanticsIdentifier('screen-sign-in'), findsOneWidget);
    expect(find.bySemanticsIdentifier('field-auth-email'), findsOneWidget);
    expect(find.bySemanticsIdentifier('field-auth-password'), findsOneWidget);
    expect(find.bySemanticsIdentifier('action-auth-submit'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('language-picker-button')),
      findsOneWidget,
    );

    semantics.dispose();
  });

  testWidgets('changes language before sign-in and keeps it for sign-up', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();

    await tester.pumpWidget(_testApp(preferences));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('language-picker-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('日本語'));
    await tester.pumpAndSettle();

    expect(find.text('サインイン'), findsOneWidget);
    expect(find.text('メールアドレス'), findsOneWidget);
    expect(
      preferences.getString(appLanguagePreferenceKey),
      AppLanguagePreference.japanese.storageValue,
    );

    await tester.tap(find.text('アカウントをお持ちでない方は新規登録'));
    await tester.pumpAndSettle();

    expect(find.text('ニックネーム'), findsOneWidget);
    expect(find.text('確認用パスワード'), findsOneWidget);
    expect(find.text('新規登録'), findsOneWidget);
  });
}

Widget _testApp(SharedPreferences preferences) {
  return ProviderScope(
    overrides: [
      appLanguagePreferenceProvider.overrideWith(
        (ref) =>
            AppLanguagePreferenceNotifier.localOnly(preferences: preferences),
      ),
    ],
    child: Consumer(
      builder: (context, ref, _) {
        final preference = ref.watch(appLanguagePreferenceProvider);
        return MaterialApp(
          locale: preference.locale,
          localeListResolutionCallback: resolveAppLocale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const SignInScreen(),
        );
      },
    ),
  );
}
