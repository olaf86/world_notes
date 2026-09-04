import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:world_notes/core/theme/app_theme.dart';

void main() {
  group('AppTheme', () {
    test('uses neutral light surfaces with a restrained brand accent', () {
      final theme = AppTheme.light;
      final colors = theme.colorScheme;

      expect(colors.brightness, Brightness.light);
      expect(colors.primary, AppTheme.accent);
      expect(theme.scaffoldBackgroundColor, const Color(0xFFFFFEFC));
      expect(colors.surfaceContainerLow, const Color(0xFFF6F7F5));
      expect(theme.cardTheme.elevation, 0);
      expect(theme.cardTheme.surfaceTintColor, Colors.transparent);
    });

    test('uses charcoal dark surfaces and the brighter accent', () {
      final theme = AppTheme.dark;
      final colors = theme.colorScheme;

      expect(colors.brightness, Brightness.dark);
      expect(colors.primary, AppTheme.darkAccent);
      expect(theme.scaffoldBackgroundColor, const Color(0xFF101414));
      expect(colors.surfaceContainerLowest, const Color(0xFF0B0E0E));
      expect(theme.appBarTheme.surfaceTintColor, Colors.transparent);
    });

    test('keeps primary controls comfortably tappable', () {
      final style = AppTheme.light.filledButtonTheme.style;

      expect(style?.minimumSize?.resolve({}), const Size(double.infinity, 52));
      expect(style?.elevation?.resolve({}), 0);
      expect(style?.shape?.resolve({}), isA<RoundedRectangleBorder>());
    });
  });
}
