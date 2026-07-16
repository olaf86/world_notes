import 'package:flutter/material.dart';

import '../../domain/entities/note_theme.dart';

class NoteThemePalette {
  final ColorScheme colorScheme;
  final List<Color> heroGradient;

  const NoteThemePalette({
    required this.colorScheme,
    required this.heroGradient,
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
    ),
    _definition(
      id: NoteThemeId.aurora,
      name: 'Aurora',
      description: 'Indigo with aqua and violet light.',
      lightSeed: const Color(0xFF5B5CE2),
      darkSeed: const Color(0xFF9B8CFF),
      lightGradient: const [Color(0xFFEAF3FF), Color(0xFFF2E9FF)],
      darkGradient: const [Color(0xFF101B3D), Color(0xFF261947)],
    ),
    _definition(
      id: NoteThemeId.citrus,
      name: 'Citrus Pop',
      description: 'Warm coral, orange, and a teal lift.',
      lightSeed: const Color(0xFFE75C3C),
      darkSeed: const Color(0xFFFF9A70),
      lightGradient: const [Color(0xFFFFF2DE), Color(0xFFFFE6E1)],
      darkGradient: const [Color(0xFF3A1E18), Color(0xFF3B2B10)],
    ),
    _definition(
      id: NoteThemeId.botanical,
      name: 'Botanical',
      description: 'Grounded jade and leaf green.',
      lightSeed: const Color(0xFF16836B),
      darkSeed: const Color(0xFF65D7B7),
      lightGradient: const [Color(0xFFE7F7EF), Color(0xFFF4F8DE)],
      darkGradient: const [Color(0xFF102C29), Color(0xFF22311A)],
    ),
    _definition(
      id: NoteThemeId.neon,
      name: 'Neon Grid',
      description: 'Cyber cyan and fuchsia after dark.',
      lightSeed: const Color(0xFF8A2BE2),
      darkSeed: const Color(0xFF00D9FF),
      lightGradient: const [Color(0xFFF5EEFF), Color(0xFFE8F8FF)],
      darkGradient: const [Color(0xFF07131E), Color(0xFF210A2D)],
    ),
    _definition(
      id: NoteThemeId.editorial,
      name: 'Editorial',
      description: 'Paper neutrals with a cobalt signal.',
      lightSeed: const Color(0xFF2455A6),
      darkSeed: const Color(0xFF9BB9FF),
      lightGradient: const [Color(0xFFFFFBF4), Color(0xFFF2F4F8)],
      darkGradient: const [Color(0xFF1B1C20), Color(0xFF17253B)],
    ),
  ];

  static NoteThemeDefinition of(NoteThemeId id) =>
      all.firstWhere((definition) => definition.id == id);

  static NoteThemePalette paletteOf(BuildContext context, NoteThemeId id) =>
      of(id).paletteFor(Theme.of(context).brightness);

  static ThemeData themed(BuildContext context, NoteThemeId id) {
    final base = Theme.of(context);
    final palette = paletteOf(context, id);
    return base.copyWith(colorScheme: palette.colorScheme);
  }

  static NoteThemeDefinition _definition({
    required NoteThemeId id,
    required String name,
    required String description,
    required Color lightSeed,
    required Color darkSeed,
    required List<Color> lightGradient,
    required List<Color> darkGradient,
  }) => NoteThemeDefinition(
    id: id,
    name: name,
    description: description,
    light: NoteThemePalette(
      colorScheme: ColorScheme.fromSeed(
        seedColor: lightSeed,
        brightness: Brightness.light,
      ),
      heroGradient: lightGradient,
    ),
    dark: NoteThemePalette(
      colorScheme: ColorScheme.fromSeed(
        seedColor: darkSeed,
        brightness: Brightness.dark,
      ),
      heroGradient: darkGradient,
    ),
  );
}
