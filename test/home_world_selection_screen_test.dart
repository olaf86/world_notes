import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:world_notes/l10n/app_locale.dart';
import 'package:world_notes/l10n/app_localizations.dart';
import 'package:world_notes/presentation/providers/providers.dart';
import 'package:world_notes/presentation/screens/auth/home_world_selection_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('explains that the home world is permanent', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          homeAssignmentProvider.overrideWith((ref) => Stream.value(null)),
          appLanguagePreferenceProvider.overrideWith(
            (ref) => AppLanguagePreferenceNotifier.localOnly(
              preferences: preferences,
            ),
          ),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: HomeWorldSelectionScreen(),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Choose your home world'), findsOneWidget);
    expect(find.text('Asia'), findsOneWidget);
    expect(find.textContaining('cannot be changed later'), findsOneWidget);
    expect(find.text('Set as my permanent home'), findsOneWidget);
  });

  testWidgets('localizes the permanent-home explanation in Japanese', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      appLanguagePreferenceKey: AppLanguagePreference.japanese.storageValue,
    });
    final preferences = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          homeAssignmentProvider.overrideWith((ref) => Stream.value(null)),
          appLanguagePreferenceProvider.overrideWith(
            (ref) => AppLanguagePreferenceNotifier.localOnly(
              preferences: preferences,
            ),
          ),
        ],
        child: const MaterialApp(
          locale: Locale('ja'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: HomeWorldSelectionScreen(),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('ホームワールドを選択'), findsOneWidget);
    expect(find.text('アジア'), findsOneWidget);
    expect(find.textContaining('一度設定すると変更できません'), findsOneWidget);
    expect(find.text('このワールドをホームに設定'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('language-picker-button')),
      findsOneWidget,
    );
  });

  testWidgets('changes language while choosing the first home world', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          homeAssignmentProvider.overrideWith((ref) => Stream.value(null)),
          appLanguagePreferenceProvider.overrideWith(
            (ref) => AppLanguagePreferenceNotifier.localOnly(
              preferences: preferences,
            ),
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
              home: const HomeWorldSelectionScreen(),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('language-picker-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('한국어'));
    await tester.pumpAndSettle();

    expect(find.text('홈 월드 선택'), findsOneWidget);
    expect(find.text('아시아'), findsOneWidget);
    expect(find.textContaining('한 번 설정하면 변경할 수 없습니다'), findsOneWidget);
    expect(find.text('이 월드를 홈으로 설정'), findsOneWidget);
    expect(
      preferences.getString(appLanguagePreferenceKey),
      AppLanguagePreference.korean.storageValue,
    );
  });
}
