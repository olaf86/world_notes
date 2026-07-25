import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:world_notes/domain/entities/place_entity.dart';
import 'package:world_notes/domain/entities/user_entity.dart';
import 'package:world_notes/l10n/app_localizations.dart';
import 'package:world_notes/presentation/providers/providers.dart';
import 'package:world_notes/presentation/screens/my_notes/my_notes_screen.dart';

void main() {
  testWidgets('aligns both My Notes sort controls to the same right edge', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authStateProvider.overrideWith(
            (ref) => Stream<UserEntity?>.value(null),
          ),
          myPlacesProvider.overrideWith(
            (ref) => Stream<List<PlaceEntity>>.value(const []),
          ),
          archivedMyPlacesCountProvider.overrideWith((ref) async => 0),
          noteLimitProvider.overrideWithValue(10),
          myNotesNotificationEnabledProvider.overrideWith(
            (ref) => Stream.value(false),
          ),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: MyNotesScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final myNotesSort = find.bySemanticsIdentifier('action-sort-my-notes');
    expect(myNotesSort, findsOneWidget);
    final myNotesRight = tester.getTopRight(myNotesSort).dx;

    await tester.tap(find.byType(Tab).last);
    await tester.pumpAndSettle();

    final archivedSort = find.bySemanticsIdentifier(
      'action-sort-archived-notes',
    );
    expect(archivedSort, findsOneWidget);
    final archivedRight = tester.getTopRight(archivedSort).dx;

    expect(myNotesRight, archivedRight);
    expect(myNotesRight, 384);
  });
}
