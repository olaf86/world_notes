import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:world_notes/l10n/app_localizations.dart';
import 'package:world_notes/presentation/screens/auth/sign_in_screen.dart';

void main() {
  testWidgets('exposes stable selectors for sign-in automation', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: SignInScreen(),
        ),
      ),
    );

    expect(find.bySemanticsIdentifier('screen-sign-in'), findsOneWidget);
    expect(find.bySemanticsIdentifier('field-auth-email'), findsOneWidget);
    expect(find.bySemanticsIdentifier('field-auth-password'), findsOneWidget);
    expect(find.bySemanticsIdentifier('action-auth-submit'), findsOneWidget);

    semantics.dispose();
  });
}
