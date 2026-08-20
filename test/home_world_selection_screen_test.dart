import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:world_notes/l10n/app_localizations.dart';
import 'package:world_notes/presentation/providers/providers.dart';
import 'package:world_notes/presentation/screens/auth/home_world_selection_screen.dart';

void main() {
  testWidgets('explains that the home world is permanent', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          homeAssignmentProvider.overrideWith((ref) => Stream.value(null)),
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
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          homeAssignmentProvider.overrideWith((ref) => Stream.value(null)),
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
    expect(find.textContaining('後から変更できません'), findsOneWidget);
    expect(find.text('このワールドを変更できないホームに設定'), findsOneWidget);
  });
}
