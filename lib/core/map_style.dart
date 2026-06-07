import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Map styles available to the user.
enum MapStyle {
  auto,
  standard,
  dark,
  pop;

  static bool get usesAppleMaps =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  static List<MapStyle> get availableForCurrentPlatform => usesAppleMaps
      ? const [auto, standard, dark]
      : const [standard, dark, pop];

  MapStyle get effectiveForCurrentPlatform {
    if (usesAppleMaps && this == pop) return auto;
    if (!usesAppleMaps && this == auto) return standard;
    return this;
  }

  /// Human-readable label shown in the settings UI.
  String label({bool usesAppleMaps = false}) => switch (this) {
    MapStyle.auto => 'Auto',
    MapStyle.standard => usesAppleMaps ? 'Light' : 'Standard',
    MapStyle.dark => 'Dark',
    MapStyle.pop => 'Pop',
  };

  /// Short description shown below the label.
  String description({bool usesAppleMaps = false}) => switch (this) {
    MapStyle.auto => 'Follow the system appearance',
    MapStyle.standard =>
      usesAppleMaps ? 'Use Apple Maps in light mode' : 'Clean & minimal',
    MapStyle.dark => 'Easy on the eyes at night',
    MapStyle.pop => 'Bright & colourful',
  };

  /// Stadia Maps style identifier.
  String get _styleId => switch (this) {
    MapStyle.auto || MapStyle.standard => 'alidade_smooth',
    MapStyle.dark => 'alidade_smooth_dark',
    MapStyle.pop => 'osm_bright',
  };

  /// Full style URL, optionally including the API key.
  String styleUrl([String apiKey = '']) {
    final base = 'https://tiles.stadiamaps.com/styles/$_styleId.json';
    return apiKey.isEmpty ? base : '$base?api_key=$apiKey';
  }

  /// Representative colour used for the preview swatch in the UI.
  Color get previewColor => switch (this) {
    MapStyle.auto => const Color(0xFFDCE7EF),
    MapStyle.standard => const Color(0xFFE8E0D8),
    MapStyle.dark => const Color(0xFF2C2C3A),
    MapStyle.pop => const Color(0xFFC8E6C9),
  };

  /// Icon shown next to the style name.
  IconData get icon => switch (this) {
    MapStyle.auto => Icons.brightness_auto_outlined,
    MapStyle.standard => Icons.light_mode_outlined,
    MapStyle.dark => Icons.dark_mode_outlined,
    MapStyle.pop => Icons.palette_outlined,
  };
}
