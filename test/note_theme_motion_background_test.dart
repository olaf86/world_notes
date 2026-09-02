import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:world_notes/core/theme/note_themes.dart';
import 'package:world_notes/domain/entities/note_theme.dart';
import 'package:world_notes/presentation/widgets/note/note_theme_motion_background.dart';

void main() {
  testWidgets('keeps the standard theme free of decorative objects', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 320,
          height: 480,
          child: NoteThemeMotionBackground(
            themeId: NoteThemeId.standard,
            palette: NoteThemes.of(NoteThemeId.standard).light,
          ),
        ),
      ),
    );

    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is CustomPaint && widget.painter is NoteThemeMotionPainter,
      ),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('note-theme-motion-standard')),
      findsNothing,
    );
  });

  testWidgets('provides a decorative layer for every expressive theme', (
    tester,
  ) async {
    await tester.runAsync(NoteThemeShaderProgram.load);

    for (final themeId in NoteThemeId.values.where(
      (id) => id != NoteThemeId.standard,
    )) {
      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            width: 320,
            height: 480,
            child: NoteThemeMotionBackground(
              themeId: themeId,
              palette: NoteThemes.of(themeId).light,
              animate: false,
            ),
          ),
        ),
      );

      expect(
        find.byKey(ValueKey('note-theme-motion-${themeId.name}')),
        findsOneWidget,
      );
    }
  });

  testWidgets('loads the shared fragment program for expressive themes', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 320,
          height: 480,
          child: NoteThemeMotionBackground(
            themeId: NoteThemeId.citrus,
            palette: NoteThemes.of(NoteThemeId.citrus).light,
            animate: false,
          ),
        ),
      ),
    );

    await tester.runAsync(NoteThemeShaderProgram.load);
    await tester.pumpAndSettle();

    expect(_painter(tester, NoteThemeId.citrus).fragmentShader, isNotNull);
  });

  testWidgets('uses a still composition when reduced motion is requested', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: SizedBox(
            width: 320,
            height: 480,
            child: NoteThemeMotionBackground(
              themeId: NoteThemeId.aurora,
              palette: NoteThemes.of(NoteThemeId.aurora).light,
            ),
          ),
        ),
      ),
    );

    final before = _painter(tester, NoteThemeId.aurora).progress;
    await tester.pump(const Duration(seconds: 5));
    final after = _painter(tester, NoteThemeId.aurora).progress;

    expect(after, before);
  });

  testWidgets('advances the composition when motion is enabled', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 320,
          height: 480,
          child: NoteThemeMotionBackground(
            themeId: NoteThemeId.botanical,
            palette: NoteThemes.of(NoteThemeId.botanical).light,
          ),
        ),
      ),
    );

    final before = _painter(tester, NoteThemeId.botanical).progress;
    await tester.pump(const Duration(seconds: 5));
    final after = _painter(tester, NoteThemeId.botanical).progress;

    expect(after, isNot(before));
  });
}

NoteThemeMotionPainter _painter(WidgetTester tester, NoteThemeId themeId) {
  final paint = tester.widget<CustomPaint>(
    find.byKey(ValueKey('note-theme-motion-${themeId.name}')),
  );
  return paint.painter! as NoteThemeMotionPainter;
}
