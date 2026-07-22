import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:world_notes/l10n/app_locale.dart';
import 'package:world_notes/l10n/app_localizations.dart';
import 'package:world_notes/presentation/providers/providers.dart';
import 'package:world_notes/presentation/screens/settings/settings_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('preloaded account cache controls the first rendered locale', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      appLanguagePreferenceKey: AppLanguagePreference.japanese.storageValue,
    });
    final preferences = await SharedPreferences.getInstance();

    await tester.pumpWidget(_testApp(preferences));
    await tester.pump();

    expect(find.text('設定'), findsOneWidget);
    expect(find.text('アプリの言語'), findsOneWidget);
    expect(find.text('自動（システム）'), findsOneWidget);
  });

  testWidgets('selecting a language updates the UI and local mirror', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      appLanguagePreferenceKey: AppLanguagePreference.english.storageValue,
    });
    final preferences = await SharedPreferences.getInstance();

    await tester.pumpWidget(_testApp(preferences));
    await tester.pump();
    await tester.tap(find.text('한국어'));
    await tester.pumpAndSettle();

    expect(find.text('설정'), findsOneWidget);
    expect(find.text('앱 언어'), findsOneWidget);
    expect(
      preferences.getString(appLanguagePreferenceKey),
      AppLanguagePreference.korean.storageValue,
    );
  });
}

Widget _testApp(SharedPreferences preferences) {
  return ProviderScope(
    overrides: [
      appLanguagePreferenceProvider.overrideWith(
        (ref) =>
            AppLanguagePreferenceNotifier.localOnly(preferences: preferences),
      ),
      myNotesNotificationEnabledProvider.overrideWith(
        (ref) => Stream.value(false),
      ),
      myNotesNotificationPreviewEnabledProvider.overrideWith(
        (ref) => Stream.value(true),
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
          home: const SettingsScreen(),
        );
      },
    ),
  );
}
