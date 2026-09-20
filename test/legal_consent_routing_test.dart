import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:world_notes/config/bootstrap_world_catalog.dart';
import 'package:world_notes/config/router.dart';
import 'package:world_notes/domain/entities/legal_acceptance.dart';
import 'package:world_notes/domain/entities/user_entity.dart';
import 'package:world_notes/l10n/app_locale.dart';
import 'package:world_notes/l10n/app_localizations.dart';
import 'package:world_notes/presentation/providers/providers.dart';
import 'package:world_notes/services/account_bootstrap_service.dart';

void main() {
  testWidgets('routes an existing account to one-time legal consent', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [
        authStateProvider.overrideWith(
          (ref) => Stream.value(
            const UserEntity(id: 'existing-user', name: 'Existing user'),
          ),
        ),
        homeAssignmentProvider.overrideWith(
          (ref) => Stream.value(
            const HomeAssignment(homeWorld: asiaWorldId, epoch: 1),
          ),
        ),
        legalAcceptanceProvider.overrideWith(
          (ref) => Stream.value(
            const LegalAcceptance(
              serviceTermsVersion: null,
              privacyPolicyVersion: null,
            ),
          ),
        ),
        appLanguagePreferenceProvider.overrideWith(
          (ref) =>
              AppLanguagePreferenceNotifier.localOnly(preferences: preferences),
        ),
      ],
    );
    addTearDown(container.dispose);
    await container.read(authStateProvider.future);
    await container.read(homeAssignmentProvider.future);
    await container.read(legalAcceptanceProvider.future);
    final router = container.read(routerProvider);
    addTearDown(router.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          routerConfig: router,
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.bySemanticsIdentifier('screen-legal-consent'), findsOneWidget);
    expect(find.text('Before you continue'), findsOneWidget);
  });
}
