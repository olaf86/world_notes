import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:world_notes/config/app_config.dart';
import 'package:world_notes/l10n/l10n.dart';
import 'package:world_notes/presentation/screens/subscription/subscription_screen.dart';

void main() {
  testWidgets('subscription legal links open the configured HTTPS pages', (
    tester,
  ) async {
    final openedUris = <Uri>[];

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SubscriptionLegalLinks(
            urlLauncher: (uri) async {
              openedUris.add(uri);
              return true;
            },
          ),
        ),
      ),
    );

    expect(find.text('Privacy Policy'), findsOneWidget);
    expect(find.text('Terms of Use (EULA)'), findsOneWidget);

    await tester.tap(find.text('Privacy Policy'));
    await tester.pump();
    await tester.tap(find.text('Terms of Use (EULA)'));
    await tester.pump();

    expect(openedUris, [
      Uri.parse(AppConfig.privacyPolicyUrl),
      Uri.parse(AppConfig.termsOfUseUrl),
    ]);
  });

  testWidgets('shows an error when a legal link cannot be opened', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SubscriptionLegalLinks(urlLauncher: (_) async => false),
        ),
      ),
    );

    await tester.tap(find.text('Privacy Policy'));
    await tester.pump();

    expect(
      find.text('Could not open the selected legal document.'),
      findsOneWidget,
    );
  });
}
