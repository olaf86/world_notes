import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:world_notes/l10n/app_localizations.dart';
import 'package:world_notes/presentation/providers/providers.dart';
import 'package:world_notes/presentation/screens/settings/settings_screen.dart';
import 'package:world_notes/presentation/widgets/my_notes_notification_controls.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('groups maintained-note previews under their parent setting', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(const {});
    final preferences = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appLanguagePreferenceProvider.overrideWith(
            (ref) => AppLanguagePreferenceNotifier.localOnly(
              preferences: preferences,
            ),
          ),
          myNotesNotificationEnabledProvider.overrideWith(
            (ref) => Stream.value(false),
          ),
          myNotesNotificationPreviewEnabledProvider.overrideWith(
            (ref) => Stream.value(true),
          ),
          mentionNotificationEnabledProvider.overrideWith(
            (ref) => Stream.value(true),
          ),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: SettingsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final maintainedGroup = find.byKey(
      const ValueKey('maintained-notes-notification-settings'),
    );
    await tester.scrollUntilVisible(maintainedGroup, 300);
    await tester.pumpAndSettle();

    final mentionGroup = find.byKey(
      const ValueKey('mention-notification-settings'),
    );
    final maintainedSetting = find.byType(MyNotesNotificationSwitchTile);
    final previewSetting = find.byType(MyNotesNotificationPreviewSwitchTile);
    final mentionSetting = find.byType(MentionNotificationSwitchTile);

    expect(
      find.descendant(of: maintainedGroup, matching: maintainedSetting),
      findsOneWidget,
    );
    expect(
      find.descendant(of: maintainedGroup, matching: previewSetting),
      findsOneWidget,
    );
    expect(
      find.descendant(of: maintainedGroup, matching: mentionSetting),
      findsNothing,
    );
    expect(
      find.descendant(of: mentionGroup, matching: mentionSetting),
      findsOneWidget,
    );
    expect(
      tester.getTopLeft(maintainedSetting).dy,
      lessThan(tester.getTopLeft(previewSetting).dy),
    );
    expect(
      tester.getTopLeft(previewSetting).dy,
      lessThan(tester.getTopLeft(mentionSetting).dy),
    );

    final maintainedTile = tester.widget<SwitchListTile>(
      find.descendant(
        of: maintainedSetting,
        matching: find.byType(SwitchListTile),
      ),
    );
    final previewTile = tester.widget<SwitchListTile>(
      find.descendant(
        of: previewSetting,
        matching: find.byType(SwitchListTile),
      ),
    );
    expect(
      previewTile.contentPadding!.resolve(TextDirection.ltr).left,
      greaterThan(
        maintainedTile.contentPadding!.resolve(TextDirection.ltr).left,
      ),
    );
    expect(previewTile.onChanged, isNull);
  });
}
