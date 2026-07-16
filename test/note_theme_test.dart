import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:world_notes/core/theme/note_themes.dart';
import 'package:world_notes/domain/entities/note_theme.dart';

void main() {
  test('parses each built-in note theme id', () {
    for (final theme in NoteThemeId.values) {
      expect(NoteThemeId.fromJson(theme.toJson()), theme);
    }
  });

  test('rejects missing and unsupported stored theme ids', () {
    expect(() => NoteThemeId.fromJson(null), throwsArgumentError);
    expect(() => NoteThemeId.fromJson('custom'), throwsArgumentError);
  });

  test('provides distinct semantic text colors for every theme', () {
    for (final brightness in Brightness.values) {
      final signatures = NoteThemes.all
          .map((theme) => theme.paletteFor(brightness).textColors)
          .map(
            (colors) => (
              colors.heading.toARGB32(),
              colors.body.toARGB32(),
              colors.muted.toARGB32(),
            ),
          )
          .toSet();

      expect(signatures, hasLength(NoteThemeId.values.length));
    }
  });

  test('keeps all semantic text colors readable on themed surfaces', () {
    for (final definition in NoteThemes.all) {
      for (final brightness in Brightness.values) {
        final palette = definition.paletteFor(brightness);
        final foregrounds = <String, Color>{
          'heading': palette.textColors.heading,
          'body': palette.textColors.body,
          'muted': palette.textColors.muted,
        };
        final backgrounds = <Color>{
          palette.colorScheme.surface,
          palette.colorScheme.surfaceContainerHighest,
          ...palette.pageGradient.colors,
          ...palette.cardGradient(isArchived: false).colors,
          ...palette.cardGradient(isArchived: true).colors,
        };

        for (final foreground in foregrounds.entries) {
          for (final background in backgrounds) {
            expect(
              _contrastRatio(foreground.value, background),
              greaterThanOrEqualTo(4.5),
              reason:
                  '${definition.id.name} ${brightness.name} '
                  '${foreground.key} on $background',
            );
          }
        }
      }
    }
  });

  testWidgets('maps semantic colors into the local note theme', (tester) async {
    late ThemeData themed;
    late NoteThemePalette palette;

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.light(),
        home: Builder(
          builder: (context) {
            palette = NoteThemes.paletteOf(context, NoteThemeId.citrus);
            themed = NoteThemes.themed(context, NoteThemeId.citrus);
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(themed.textTheme.titleMedium?.color, palette.textColors.heading);
    expect(themed.textTheme.bodyMedium?.color, palette.textColors.body);
    expect(themed.textTheme.bodySmall?.color, palette.textColors.muted);
    expect(themed.colorScheme.onSurface, palette.textColors.body);
    expect(themed.colorScheme.onSurfaceVariant, palette.textColors.muted);
  });
}

double _contrastRatio(Color foreground, Color background) {
  final light = foreground.computeLuminance() > background.computeLuminance()
      ? foreground.computeLuminance()
      : background.computeLuminance();
  final dark = foreground.computeLuminance() > background.computeLuminance()
      ? background.computeLuminance()
      : foreground.computeLuminance();
  return (light + 0.05) / (dark + 0.05);
}
