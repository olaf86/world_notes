import 'package:flutter/material.dart';

class AppTheme {
  static const _seed = Color(0xFF2E7D32);

  static const _nativeEmojiFontFamilyFallback = <String>[
    'Apple Color Emoji',
    'Noto Color Emoji',
    'Segoe UI Emoji',
  ];

  static ThemeData get light => _withNativeEmojiFallback(
    ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: _seed,
        brightness: Brightness.light,
      ),
      appBarTheme: const AppBarTheme(centerTitle: true, elevation: 0),
      cardTheme: CardThemeData(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        filled: true,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          minimumSize: const Size(double.infinity, 48),
        ),
      ),
    ),
  );

  static ThemeData get dark => _withNativeEmojiFallback(
    ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: _seed,
        brightness: Brightness.dark,
      ),
      appBarTheme: const AppBarTheme(centerTitle: true, elevation: 0),
      cardTheme: CardThemeData(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        filled: true,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          minimumSize: const Size(double.infinity, 48),
        ),
      ),
    ),
  );

  static ThemeData _withNativeEmojiFallback(ThemeData theme) {
    return theme.copyWith(
      textTheme: _textThemeWithNativeEmojiFallback(theme.textTheme),
      primaryTextTheme: _textThemeWithNativeEmojiFallback(
        theme.primaryTextTheme,
      ),
    );
  }

  static TextTheme _textThemeWithNativeEmojiFallback(TextTheme textTheme) {
    return textTheme.apply(fontFamilyFallback: _nativeEmojiFontFamilyFallback);
  }
}
