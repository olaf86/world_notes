import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:world_notes/config/bootstrap_world_catalog.dart';
import 'package:world_notes/config/world_catalog.dart';
import 'package:world_notes/domain/entities/user_entity.dart';
import 'package:world_notes/l10n/app_localizations.dart';
import 'package:world_notes/presentation/providers/providers.dart';
import 'package:world_notes/presentation/screens/settings/settings_screen.dart';
import 'package:world_notes/services/account_bootstrap_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('switches only between content-enabled worlds', (tester) async {
    SharedPreferences.setMockInitialValues(const {});
    final preferences = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [
        appLanguagePreferenceProvider.overrideWith(
          (ref) =>
              AppLanguagePreferenceNotifier.localOnly(preferences: preferences),
        ),
        authStateProvider.overrideWith(
          (ref) => Stream.value(const UserEntity(id: 'user-1', name: 'User')),
        ),
        homeAssignmentProvider.overrideWith(
          (ref) => Stream.value(
            const HomeAssignment(homeWorld: asiaWorldId, epoch: 1),
          ),
        ),
        worldReadinessProvider.overrideWith((ref, worldId) async => true),
        myNotesNotificationEnabledProvider.overrideWith(
          (ref) => Stream.value(false),
        ),
        myNotesNotificationPreviewEnabledProvider.overrideWith(
          (ref) => Stream.value(true),
        ),
      ],
    );
    addTearDown(container.dispose);
    await container.read(authStateProvider.future);
    await container.read(homeAssignmentProvider.future);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: SettingsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final homeWorldTile = find.byKey(const ValueKey('home-world-setting-tile'));
    final contentWorldTile = find.byKey(
      const ValueKey('content-world-setting-tile'),
    );
    expect(find.text('Home world'), findsOneWidget);
    expect(
      find.descendant(
        of: homeWorldTile,
        matching: find.textContaining('Asia ·'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: contentWorldTile,
        matching: find.textContaining('Asia ·'),
      ),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('content-world-setting-tile')));
    await tester.pumpAndSettle();

    expect(find.text('Asia'), findsOneWidget);
    expect(find.text('North America'), findsOneWidget);
    expect(find.text('Europe'), findsOneWidget);
    expect(
      find.textContaining('Switching content worlds does not change'),
      findsOneWidget,
    );

    await tester.tap(find.text('Europe'));
    await tester.pumpAndSettle();

    expect(container.read(homeWorldProvider), asiaWorldId);
    expect(container.read(selectedWorldProvider), const WorldId('europe'));
    expect(
      find.descendant(
        of: homeWorldTile,
        matching: find.textContaining('Asia ·'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: contentWorldTile,
        matching: find.textContaining('Europe ·'),
      ),
      findsOneWidget,
    );
  });
}
