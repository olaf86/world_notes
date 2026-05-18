import 'package:flutter/material.dart';

/// The three map styles available to the user.
enum MapStyle {
  standard,
  dark,
  pop;

  /// Human-readable label shown in the settings UI.
  String get label => switch (this) {
        MapStyle.standard => 'Standard',
        MapStyle.dark => 'Dark',
        MapStyle.pop => 'Pop',
      };

  /// Short description shown below the label.
  String get description => switch (this) {
        MapStyle.standard => 'Clean & minimal',
        MapStyle.dark => 'Easy on the eyes at night',
        MapStyle.pop => 'Bright & colourful',
      };

  /// Stadia Maps style identifier.
  String get _styleId => switch (this) {
        MapStyle.standard => 'alidade_smooth',
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
        MapStyle.standard => const Color(0xFFE8E0D8),
        MapStyle.dark => const Color(0xFF2C2C3A),
        MapStyle.pop => const Color(0xFFC8E6C9),
      };

  /// Icon shown next to the style name.
  IconData get icon => switch (this) {
        MapStyle.standard => Icons.map_outlined,
        MapStyle.dark => Icons.dark_mode_outlined,
        MapStyle.pop => Icons.palette_outlined,
      };
}
