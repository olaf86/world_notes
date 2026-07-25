import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:world_notes/domain/entities/note_theme.dart';
import 'package:world_notes/l10n/app_localizations.dart';
import 'package:world_notes/presentation/widgets/note/note_theme_picker.dart';

void main() {
  testWidgets('keeps theme choices in a bottom sheet', (tester) async {
    var selected = NoteThemeId.standard;

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => NoteThemePicker(
              selected: selected,
              onChanged: (value) => setState(() => selected = value),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('note-theme-picker-tile')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('note-theme-option-aurora')),
      findsNothing,
    );

    await tester.tap(find.byKey(const ValueKey('note-theme-picker-tile')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('note-theme-option-aurora')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('note-theme-option-aurora')));
    await tester.pumpAndSettle();

    expect(selected, NoteThemeId.aurora);
    expect(find.text('Aurora'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('note-theme-option-aurora')),
      findsNothing,
    );
  });
}
