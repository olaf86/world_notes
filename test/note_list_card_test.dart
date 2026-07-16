import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:world_notes/domain/entities/note_theme.dart';
import 'package:world_notes/presentation/widgets/note/note_list_card.dart';

void main() {
  testWidgets('uses the note theme as a gradient card surface', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: NoteListCard(
            avatarColor: Colors.green,
            avatarIcon: Icons.place,
            title: 'Aurora note',
            themeId: NoteThemeId.aurora,
          ),
        ),
      ),
    );

    final themedSurface = tester.widget<Ink>(
      find.byKey(const ValueKey('note-theme-card-aurora')),
    );
    expect(
      (themedSurface.decoration as BoxDecoration).gradient,
      isA<LinearGradient>(),
    );
  });

  testWidgets('does not render a leading theme stripe', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: NoteListCard(
            avatarColor: Colors.orange,
            avatarIcon: Icons.place,
            title: 'Citrus note',
            themeId: NoteThemeId.citrus,
          ),
        ),
      ),
    );

    final legacyStripe = find.byWidgetPredicate((widget) {
      if (widget is! Container) return false;
      final constraints = widget.constraints;
      return constraints != null &&
          constraints.minWidth == 4 &&
          constraints.maxWidth == 4 &&
          constraints.minHeight == 52 &&
          constraints.maxHeight == 52;
    });
    expect(legacyStripe, findsNothing);
  });

  testWidgets('resolves a distinct card gradient in dark mode', (tester) async {
    Widget app(ThemeMode mode) => MaterialApp(
      theme: ThemeData.light(),
      darkTheme: ThemeData.dark(),
      themeMode: mode,
      home: const Scaffold(
        body: NoteListCard(
          avatarColor: Colors.purple,
          avatarIcon: Icons.place,
          title: 'Neon note',
          themeId: NoteThemeId.neon,
        ),
      ),
    );

    await tester.pumpWidget(app(ThemeMode.light));
    await tester.pumpAndSettle();
    final lightGradient = _cardGradient(tester, NoteThemeId.neon);

    await tester.pumpWidget(app(ThemeMode.dark));
    await tester.pumpAndSettle();
    final darkGradient = _cardGradient(tester, NoteThemeId.neon);

    expect(darkGradient.colors, isNot(lightGradient.colors));
  });
}

LinearGradient _cardGradient(WidgetTester tester, NoteThemeId id) {
  final surface = tester.widget<Ink>(
    find.byKey(ValueKey('note-theme-card-${id.name}')),
  );
  return (surface.decoration as BoxDecoration).gradient! as LinearGradient;
}
