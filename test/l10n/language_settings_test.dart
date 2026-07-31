import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:world_notes/domain/entities/place_entity.dart';
import 'package:world_notes/domain/entities/user_entity.dart';
import 'package:world_notes/l10n/app_locale.dart';
import 'package:world_notes/l10n/app_localizations.dart';
import 'package:world_notes/presentation/providers/providers.dart';
import 'package:world_notes/presentation/screens/note/note_box_screen.dart';
import 'package:world_notes/presentation/screens/note/note_creation_screen.dart';
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
    expect(find.text('日本語'), findsOneWidget);
    expect(find.byType(RadioListTile<AppLanguagePreference>), findsNothing);
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
    await tester.tap(find.byKey(const ValueKey('language-setting-tile')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('한국어'));
    await tester.pumpAndSettle();

    expect(find.text('설정'), findsOneWidget);
    expect(find.text('앱 언어'), findsOneWidget);
    expect(find.byType(RadioListTile<AppLanguagePreference>), findsNothing);
    expect(
      preferences.getString(appLanguagePreferenceKey),
      AppLanguagePreference.korean.storageValue,
    );
  });

  testWidgets('does not expose the removed function-region picker', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      appLanguagePreferenceKey: AppLanguagePreference.english.storageValue,
    });
    final preferences = await SharedPreferences.getInstance();

    await tester.pumpWidget(_testApp(preferences));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('data-region-setting-tile')),
      findsNothing,
    );
  });

  testWidgets(
    'new note routes use the language selected immediately beforehand',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        appLanguagePreferenceKey: AppLanguagePreference.english.storageValue,
      });
      final preferences = await SharedPreferences.getInstance();

      await tester.pumpWidget(_testApp(preferences));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('language-setting-tile')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('日本語'));
      await tester.pumpAndSettle();

      final settingsContext = tester.element(find.byType(SettingsScreen));
      Navigator.of(settingsContext).pushNamed('/note-create');
      await tester.pumpAndSettle();

      expect(find.text('新しいノート'), findsOneWidget);
      expect(find.text('タイトル'), findsOneWidget);
      expect(find.text('New Note'), findsNothing);

      Navigator.of(
        tester.element(find.byType(NoteCreationScreen)),
      ).pushNamed('/note-detail');
      await tester.pump();
      await tester.pump();

      expect(find.text('ノートを開けませんでした。'), findsOneWidget);
      expect(find.text('もう一度試す'), findsOneWidget);
      expect(find.text('Could not open this note.'), findsNothing);
    },
  );
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
      authStateProvider.overrideWith((ref) => Stream<UserEntity?>.value(null)),
      isPremiumProvider.overrideWith((ref) => Stream.value(true)),
      activeMyPlacesCountProvider.overrideWith((ref) async => 0),
      placeProvider.overrideWith(
        (ref, String placeId) => const Stream<PlaceEntity?>.empty(),
      ),
      noteAccessValidationProvider.overrideWith(
        (ref, NoteAccessValidationRequest request) =>
            Future<void>.error(StateError('offline')),
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
          routes: {
            '/note-create': (_) => const NoteCreationScreen(),
            '/note-detail': (_) => const NoteBoxScreen(
              placeId: 'note-1',
              placeTitle: '',
              accessValidation: NoteAccessValidationRequest(
                placeId: 'note-1',
                latitude: 35,
                longitude: 139,
              ),
            ),
          },
        );
      },
    ),
  );
}
