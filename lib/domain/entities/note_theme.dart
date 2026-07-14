/// Stable identifiers for the built-in note appearance themes.
enum NoteThemeId {
  aurora,
  citrus,
  botanical,
  neon,
  editorial;

  String toJson() => name;

  static NoteThemeId fromJson(Object? value) => switch (value) {
    'aurora' => aurora,
    'citrus' => citrus,
    'botanical' => botanical,
    'neon' => neon,
    'editorial' => editorial,
    _ => throw ArgumentError.value(value, 'themeId', 'Unsupported note theme'),
  };
}
