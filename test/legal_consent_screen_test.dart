import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:world_notes/config/app_config.dart';
import 'package:world_notes/config/bootstrap_world_catalog.dart';
import 'package:world_notes/domain/entities/legal_acceptance.dart';
import 'package:world_notes/domain/entities/user_entity.dart';
import 'package:world_notes/domain/repositories/legal_acceptance_repository.dart';
import 'package:world_notes/l10n/app_localizations.dart';
import 'package:world_notes/presentation/providers/providers.dart';
import 'package:world_notes/presentation/screens/auth/legal_consent_screen.dart';
import 'package:world_notes/services/account_bootstrap_service.dart';

void main() {
  testWidgets('requires explicit agreement once before continuing', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final repository = _FakeLegalAcceptanceRepository();
    final router = GoRouter(
      initialLocation: '/legal',
      routes: [
        GoRoute(
          path: '/legal',
          builder: (_, _) => const LegalConsentScreen(continuation: '/map'),
        ),
        GoRoute(
          path: '/map',
          builder: (_, _) => const Scaffold(body: Text('Map destination')),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authStateProvider.overrideWith(
            (ref) =>
                Stream.value(const UserEntity(id: 'user-1', name: 'Test user')),
          ),
          homeAssignmentProvider.overrideWith(
            (ref) => Stream.value(
              const HomeAssignment(homeWorld: asiaWorldId, epoch: 1),
            ),
          ),
          legalAcceptanceRepositoryProvider.overrideWithValue(repository),
          appLanguagePreferenceProvider.overrideWith(
            (ref) => AppLanguagePreferenceNotifier.localOnly(
              preferences: preferences,
            ),
          ),
        ],
        child: MaterialApp.router(
          routerConfig: router,
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Before you continue'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Terms of Service'), 300);
    expect(find.text('Terms of Service'), findsOneWidget);
    expect(find.text('Apple Standard EULA'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Agree and continue'), 300);
    final continueButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Agree and continue'),
    );
    expect(continueButton.onPressed, isNull);

    await tester.tap(find.byKey(const ValueKey('legal-consent-checkbox')));
    await tester.pump();
    await tester.tap(find.text('Agree and continue'));
    await tester.pumpAndSettle();

    expect(repository.acceptedLocale, 'en');
    expect(find.text('Map destination'), findsOneWidget);
  });
}

class _FakeLegalAcceptanceRepository implements LegalAcceptanceRepository {
  LegalAcceptance? _acceptance = const LegalAcceptance(
    serviceTermsVersion: null,
    privacyPolicyVersion: null,
  );
  String? acceptedLocale;

  @override
  Future<void> acceptCurrent({
    required String userId,
    required String locale,
  }) async {
    expect(userId, 'user-1');
    acceptedLocale = locale;
    _acceptance = const LegalAcceptance(
      serviceTermsVersion: AppConfig.currentServiceTermsVersion,
      privacyPolicyVersion: AppConfig.currentPrivacyPolicyVersion,
    );
  }

  @override
  Stream<LegalAcceptance?> watch(String userId) => Stream.value(_acceptance);
}
