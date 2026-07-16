import 'package:flutter/material.dart';

import '../../domain/entities/note_theme.dart';

class NoteThemeTextColors {
  final Color heading;
  final Color body;
  final Color muted;

  const NoteThemeTextColors({
    required this.heading,
    required this.body,
    required this.muted,
  });
}

class NoteThemePalette {
  final ColorScheme colorScheme;
  final List<Color> heroGradient;
  final NoteThemeTextColors textColors;

  const NoteThemePalette({
    required this.colorScheme,
    required this.heroGradient,
    required this.textColors,
  });

  /// A spacious, low-frequency gradient for a whole note surface.
  LinearGradient get pageGradient => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      heroGradient.first,
      Color.alphaBlend(
        colorScheme.primary.withValues(alpha: 0.035),
        colorScheme.surface,
      ),
      heroGradient.last,
    ],
    stops: const [0, 0.52, 1],
  );

  /// A quieter version for mixed-theme lists, with archived notes softened.
  LinearGradient cardGradient({required bool isArchived}) {
    final strength = isArchived ? 0.20 : 0.52;
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: heroGradient
          .map((color) => Color.lerp(colorScheme.surface, color, strength)!)
          .toList(),
    );
  }

  LinearGradient get previewGradient => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: heroGradient,
  );
}

class NoteThemeDefinition {
  final NoteThemeId id;
  final String name;
  final String description;
  final NoteThemePalette light;
  final NoteThemePalette dark;

  const NoteThemeDefinition({
    required this.id,
    required this.name,
    required this.description,
    required this.light,
    required this.dark,
  });

  NoteThemePalette paletteFor(Brightness brightness) =>
      brightness == Brightness.dark ? dark : light;
}

class NoteThemes {
  static final all = <NoteThemeDefinition>[
    _definition(
      id: NoteThemeId.standard,
      name: 'Standard',
      description: 'The calm, familiar World Notes appearance.',
      lightSeed: const Color(0xFF2E7D32),
      darkSeed: const Color(0xFF8BC58F),
      lightGradient: const [Color(0xFFF7FAF6), Color(0xFFF3F8F5)],
      darkGradient: const [Color(0xFF142018), Color(0xFF18241B)],
      lightTextColors: const NoteThemeTextColors(
        heading: Color(0xFF18251C),
        body: Color(0xFF25352A),
        muted: Color(0xFF536258),
      ),
      darkTextColors: const NoteThemeTextColors(
        heading: Color(0xFFEAF4EC),
        body: Color(0xFFDDE9DF),
        muted: Color(0xFFABB9AE),
      ),
    ),
    _definition(
      id: NoteThemeId.aurora,
      name: 'Aurora',
      description: 'Indigo with aqua and violet light.',
      lightSeed: const Color(0xFF5B5CE2),
      darkSeed: const Color(0xFF9B8CFF),
      lightGradient: const [Color(0xFFEAF3FF), Color(0xFFF2E9FF)],
      darkGradient: const [Color(0xFF101B3D), Color(0xFF261947)],
      lightTextColors: const NoteThemeTextColors(
        heading: Color(0xFF25235C),
        body: Color(0xFF302E4A),
        muted: Color(0xFF5F5B79),
      ),
      darkTextColors: const NoteThemeTextColors(
        heading: Color(0xFFF0EDFF),
        body: Color(0xFFE0DDF4),
        muted: Color(0xFFB2AACB),
      ),
    ),
    _definition(
      id: NoteThemeId.citrus,
      name: 'Citrus Pop',
      description: 'Warm coral, orange, and a teal lift.',
      lightSeed: const Color(0xFFE75C3C),
      darkSeed: const Color(0xFFFF9A70),
      lightGradient: const [Color(0xFFFFF2DE), Color(0xFFFFE6E1)],
      darkGradient: const [Color(0xFF3A1E18), Color(0xFF3B2B10)],
      lightTextColors: const NoteThemeTextColors(
        heading: Color(0xFF5B2B1F),
        body: Color(0xFF49332C),
        muted: Color(0xFF775B50),
      ),
      darkTextColors: const NoteThemeTextColors(
        heading: Color(0xFFFFE8DE),
        body: Color(0xFFF1D9CF),
        muted: Color(0xFFC8A99D),
      ),
    ),
    _definition(
      id: NoteThemeId.botanical,
      name: 'Botanical',
      description: 'Grounded jade and leaf green.',
      lightSeed: const Color(0xFF16836B),
      darkSeed: const Color(0xFF65D7B7),
      lightGradient: const [Color(0xFFE7F7EF), Color(0xFFF4F8DE)],
      darkGradient: const [Color(0xFF102C29), Color(0xFF22311A)],
      lightTextColors: const NoteThemeTextColors(
        heading: Color(0xFF153F35),
        body: Color(0xFF29463E),
        muted: Color(0xFF50665E),
      ),
      darkTextColors: const NoteThemeTextColors(
        heading: Color(0xFFE4F5EB),
        body: Color(0xFFD4E8DD),
        muted: Color(0xFFA7BCAF),
      ),
    ),
    _definition(
      id: NoteThemeId.neon,
      name: 'Neon Grid',
      description: 'Cyber cyan and fuchsia after dark.',
      lightSeed: const Color(0xFF8A2BE2),
      darkSeed: const Color(0xFF00D9FF),
      lightGradient: const [Color(0xFFF5EEFF), Color(0xFFE8F8FF)],
      darkGradient: const [Color(0xFF07131E), Color(0xFF210A2D)],
      lightTextColors: const NoteThemeTextColors(
        heading: Color(0xFF3D1C63),
        body: Color(0xFF26213A),
        muted: Color(0xFF5F5971),
      ),
      darkTextColors: const NoteThemeTextColors(
        heading: Color(0xFFE7FBFF),
        body: Color(0xFFD5EDF1),
        muted: Color(0xFF91B4BB),
      ),
    ),
    _definition(
      id: NoteThemeId.editorial,
      name: 'Editorial',
      description: 'Paper neutrals with a cobalt signal.',
      lightSeed: const Color(0xFF2455A6),
      darkSeed: const Color(0xFF9BB9FF),
      lightGradient: const [Color(0xFFFFFBF4), Color(0xFFF2F4F8)],
      darkGradient: const [Color(0xFF1B1C20), Color(0xFF17253B)],
      lightTextColors: const NoteThemeTextColors(
        heading: Color(0xFF17233A),
        body: Color(0xFF2F3540),
        muted: Color(0xFF58616F),
      ),
      darkTextColors: const NoteThemeTextColors(
        heading: Color(0xFFF4F2ED),
        body: Color(0xFFE2E1DE),
        muted: Color(0xFFB5B6BA),
      ),
    ),
  ];

  static NoteThemeDefinition of(NoteThemeId id) =>
      all.firstWhere((definition) => definition.id == id);

  static NoteThemePalette paletteOf(BuildContext context, NoteThemeId id) =>
      of(id).paletteFor(Theme.of(context).brightness);

  static ThemeData themed(BuildContext context, NoteThemeId id) {
    final base = Theme.of(context);
    final palette = paletteOf(context, id);
    final textColors = palette.textColors;
    final textTheme = base.textTheme.copyWith(
      displayLarge: _withColor(base.textTheme.displayLarge, textColors.heading),
      displayMedium: _withColor(
        base.textTheme.displayMedium,
        textColors.heading,
      ),
      displaySmall: _withColor(base.textTheme.displaySmall, textColors.heading),
      headlineLarge: _withColor(
        base.textTheme.headlineLarge,
        textColors.heading,
      ),
      headlineMedium: _withColor(
        base.textTheme.headlineMedium,
        textColors.heading,
      ),
      headlineSmall: _withColor(
        base.textTheme.headlineSmall,
        textColors.heading,
      ),
      titleLarge: _withColor(base.textTheme.titleLarge, textColors.heading),
      titleMedium: _withColor(base.textTheme.titleMedium, textColors.heading),
      titleSmall: _withColor(base.textTheme.titleSmall, textColors.heading),
      bodyLarge: _withColor(base.textTheme.bodyLarge, textColors.body),
      bodyMedium: _withColor(base.textTheme.bodyMedium, textColors.body),
      bodySmall: _withColor(base.textTheme.bodySmall, textColors.muted),
      labelLarge: _withColor(base.textTheme.labelLarge, textColors.body),
      labelMedium: _withColor(base.textTheme.labelMedium, textColors.muted),
      labelSmall: _withColor(base.textTheme.labelSmall, textColors.muted),
    );
    return base.copyWith(
      colorScheme: palette.colorScheme,
      textTheme: textTheme,
    );
  }

  static TextStyle? _withColor(TextStyle? style, Color color) =>
      style?.copyWith(color: color);

  static NoteThemeDefinition _definition({
    required NoteThemeId id,
    required String name,
    required String description,
    required Color lightSeed,
    required Color darkSeed,
    required List<Color> lightGradient,
    required List<Color> darkGradient,
    required NoteThemeTextColors lightTextColors,
    required NoteThemeTextColors darkTextColors,
  }) => NoteThemeDefinition(
    id: id,
    name: name,
    description: description,
    light: NoteThemePalette(
      colorScheme:
          ColorScheme.fromSeed(
            seedColor: lightSeed,
            brightness: Brightness.light,
          ).copyWith(
            onSurface: lightTextColors.body,
            onSurfaceVariant: lightTextColors.muted,
          ),
      heroGradient: lightGradient,
      textColors: lightTextColors,
    ),
    dark: NoteThemePalette(
      colorScheme:
          ColorScheme.fromSeed(
            seedColor: darkSeed,
            brightness: Brightness.dark,
          ).copyWith(
            onSurface: darkTextColors.body,
            onSurfaceVariant: darkTextColors.muted,
          ),
      heroGradient: darkGradient,
      textColors: darkTextColors,
    ),
  );
}
