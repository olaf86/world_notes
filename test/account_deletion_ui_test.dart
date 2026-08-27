import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:world_notes/config/bootstrap_world_catalog.dart';
import 'package:world_notes/domain/entities/user_entity.dart';
import 'package:world_notes/domain/repositories/auth_repository.dart';
import 'package:world_notes/l10n/app_localizations.dart';
import 'package:world_notes/presentation/providers/providers.dart';
import 'package:world_notes/presentation/screens/settings/settings_screen.dart';
import 'package:world_notes/services/account_bootstrap_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('account deletion is presented as an irreversible danger', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(const {});
    final preferences = await SharedPreferences.getInstance();
    final repository = _FakeAuthRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appLanguagePreferenceProvider.overrideWith(
            (ref) => AppLanguagePreferenceNotifier.localOnly(
              preferences: preferences,
            ),
          ),
          authRepositoryProvider.overrideWithValue(repository),
          authStateProvider.overrideWith(
            (ref) => Stream.value(repository.currentUser),
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
        child: const MaterialApp(
          locale: Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: SettingsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('delete-account-tile')),
      300,
      scrollable: find.byType(Scrollable).first,
    );

    expect(find.text('Danger zone'), findsOneWidget);
    expect(find.byKey(const ValueKey('danger-zone-card')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('delete-account-tile')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('irreversible-action-warning')),
      findsOneWidget,
    );
    expect(find.text('This action cannot be undone.'), findsOneWidget);
    expect(find.text('Delete permanently'), findsOneWidget);
  });
}

class _FakeAuthRepository implements AuthRepository {
  static const _user = UserEntity(id: 'user-1', name: 'User');

  @override
  Stream<UserEntity?> get authStateChanges => Stream.value(_user);

  @override
  UserEntity? get currentUser => _user;

  @override
  bool get requiresPasswordForAccountDeletion => false;

  @override
  Future<void> deleteAccount({String? password}) async {}

  @override
  Future<UserEntity> signInWithApple() => throw UnimplementedError();

  @override
  Future<UserEntity> signInWithEmail(String email, String password) =>
      throw UnimplementedError();

  @override
  Future<UserEntity> signInWithGoogle() => throw UnimplementedError();

  @override
  Future<void> signOut() => throw UnimplementedError();

  @override
  Future<UserEntity> signUpWithEmail(
    String email,
    String password,
    String name,
  ) => throw UnimplementedError();

  @override
  Future<UserEntity> updateDisplayName(String displayName) =>
      throw UnimplementedError();
}
