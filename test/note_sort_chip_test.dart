import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:world_notes/domain/entities/note_list_sort.dart';
import 'package:world_notes/presentation/widgets/note/note_sort_button.dart';

final _sortProvider = StateProvider<NoteListSort>(
  (ref) => NoteListSort.lastActivity,
);

void main() {
  testWidgets('sort chip shows and changes the selected sort', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 140,
                child: Consumer(
                  builder: (context, ref, child) {
                    return NoteSortChip(
                      selected: ref.watch(_sortProvider),
                      provider: _sortProvider,
                      options: const [
                        NoteListSort.lastActivity,
                        NoteListSort.newest,
                        NoteListSort.expiresSoonest,
                      ],
                      semanticIdentifier: 'test-sort-chip',
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Last activity'), findsOneWidget);
    expect(find.textContaining('Sorted by'), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.tap(find.bySemanticsIdentifier('test-sort-chip'));
    await tester.pumpAndSettle();

    expect(find.text('Newest'), findsOneWidget);
    await tester.tap(find.text('Newest'));
    await tester.pumpAndSettle();

    expect(find.text('Newest'), findsOneWidget);
    expect(find.text('Last activity'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
