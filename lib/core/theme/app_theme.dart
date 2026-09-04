import 'package:flutter/material.dart';

/// The shared World Notes visual language.
///
/// Surfaces stay deliberately neutral so note colors and map content remain
/// useful signals. Mineral teal is reserved for selection, focus, and primary
/// actions instead of tinting every surface in the app.
class AppTheme {
  static const accent = Color(0xFF0F6B6C);
  static const darkAccent = Color(0xFF84D9CC);

  static const _lightScheme = ColorScheme(
    brightness: Brightness.light,
    primary: accent,
    onPrimary: Color(0xFFFFFFFF),
    primaryContainer: Color(0xFFD2EFEB),
    onPrimaryContainer: Color(0xFF0A3737),
    secondary: Color(0xFF586565),
    onSecondary: Color(0xFFFFFFFF),
    secondaryContainer: Color(0xFFDFE8E7),
    onSecondaryContainer: Color(0xFF182222),
    tertiary: Color(0xFF5D6576),
    onTertiary: Color(0xFFFFFFFF),
    tertiaryContainer: Color(0xFFE2E6F2),
    onTertiaryContainer: Color(0xFF1B2231),
    error: Color(0xFFBA1A1A),
    onError: Color(0xFFFFFFFF),
    errorContainer: Color(0xFFFFDAD6),
    onErrorContainer: Color(0xFF410002),
    surface: Color(0xFFFFFEFC),
    onSurface: Color(0xFF191C1C),
    onSurfaceVariant: Color(0xFF56605E),
    outline: Color(0xFF737C79),
    outlineVariant: Color(0xFFD0D7D4),
    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),
    inverseSurface: Color(0xFF2D3130),
    onInverseSurface: Color(0xFFF0F2F0),
    inversePrimary: darkAccent,
    surfaceTint: accent,
    surfaceDim: Color(0xFFDBDEDC),
    surfaceBright: Color(0xFFFFFEFC),
    surfaceContainerLowest: Color(0xFFFFFFFF),
    surfaceContainerLow: Color(0xFFF6F7F5),
    surfaceContainer: Color(0xFFF0F2F0),
    surfaceContainerHigh: Color(0xFFEAEDEA),
    surfaceContainerHighest: Color(0xFFE3E7E4),
  );

  static const _darkScheme = ColorScheme(
    brightness: Brightness.dark,
    primary: darkAccent,
    onPrimary: Color(0xFF003736),
    primaryContainer: Color(0xFF0F4F50),
    onPrimaryContainer: Color(0xFFB5F1E9),
    secondary: Color(0xFFB9C9C7),
    onSecondary: Color(0xFF243332),
    secondaryContainer: Color(0xFF354745),
    onSecondaryContainer: Color(0xFFD5E5E2),
    tertiary: Color(0xFFC4C8D6),
    onTertiary: Color(0xFF2E3443),
    tertiaryContainer: Color(0xFF454B5C),
    onTertiaryContainer: Color(0xFFE1E4F2),
    error: Color(0xFFFFB4AB),
    onError: Color(0xFF690005),
    errorContainer: Color(0xFF93000A),
    onErrorContainer: Color(0xFFFFDAD6),
    surface: Color(0xFF101414),
    onSurface: Color(0xFFE7EBE9),
    onSurfaceVariant: Color(0xFFBEC7C4),
    outline: Color(0xFF89938F),
    outlineVariant: Color(0xFF3F4846),
    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),
    inverseSurface: Color(0xFFE1E3E1),
    onInverseSurface: Color(0xFF2E3130),
    inversePrimary: accent,
    surfaceTint: darkAccent,
    surfaceDim: Color(0xFF101414),
    surfaceBright: Color(0xFF363B3A),
    surfaceContainerLowest: Color(0xFF0B0E0E),
    surfaceContainerLow: Color(0xFF171B1B),
    surfaceContainer: Color(0xFF1B2020),
    surfaceContainerHigh: Color(0xFF222827),
    surfaceContainerHighest: Color(0xFF2A3130),
  );

  static ThemeData get light => _build(_lightScheme);

  static ThemeData get dark => _build(_darkScheme);

  static ThemeData _build(ColorScheme colors) {
    final base = ThemeData(
      useMaterial3: true,
      brightness: colors.brightness,
      colorScheme: colors,
      scaffoldBackgroundColor: colors.surface,
    );
    final textTheme = base.textTheme.copyWith(
      headlineLarge: base.textTheme.headlineLarge?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -0.8,
      ),
      headlineMedium: base.textTheme.headlineMedium?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
      ),
      headlineSmall: base.textTheme.headlineSmall?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
      ),
      titleLarge: base.textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
      ),
      titleMedium: base.textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.w600,
      ),
      labelLarge: base.textTheme.labelLarge?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: 0.1,
      ),
    );
    final controlShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
    );

    return base.copyWith(
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: colors.surface,
        foregroundColor: colors.onSurface,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: textTheme.titleLarge?.copyWith(color: colors.onSurface),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: colors.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        margin: const EdgeInsets.all(4),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: colors.outlineVariant),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colors.surfaceContainerLow,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: colors.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: colors.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: colors.primary, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: colors.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: colors.error, width: 1.6),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(double.infinity, 52),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          elevation: 0,
          shape: controlShape,
          textStyle: textTheme.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, 52),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          side: BorderSide(color: colors.outlineVariant),
          shape: controlShape,
          textStyle: textTheme.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(48, 44),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: textTheme.labelLarge,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 68,
        elevation: 0,
        backgroundColor: colors.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        indicatorColor: colors.primaryContainer,
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          return textTheme.labelMedium?.copyWith(
            color: states.contains(WidgetState.selected)
                ? colors.onSurface
                : colors.onSurfaceVariant,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w500,
          );
        }),
      ),
      tabBarTheme: TabBarThemeData(
        dividerColor: colors.outlineVariant,
        indicatorColor: colors.primary,
        labelColor: colors.onSurface,
        unselectedLabelColor: colors.onSurfaceVariant,
        labelStyle: textTheme.labelLarge,
        unselectedLabelStyle: textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w500,
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        elevation: 1,
        focusElevation: 1,
        hoverElevation: 2,
        highlightElevation: 1,
        backgroundColor: colors.primary,
        foregroundColor: colors.onPrimary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colors.surfaceContainerLowest,
        modalBackgroundColor: colors.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
        ),
      ),
      dialogTheme: DialogThemeData(
        elevation: 8,
        backgroundColor: colors.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: colors.inverseSurface,
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: colors.onInverseSurface,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      dividerTheme: DividerThemeData(
        color: colors.outlineVariant,
        thickness: 1,
        space: 1,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: colors.primary,
        linearTrackColor: colors.primaryContainer,
        circularTrackColor: colors.surfaceContainerHighest,
      ),
    );
  }
}
