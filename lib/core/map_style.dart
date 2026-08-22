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

  /// Client-side Google Maps style JSON. These styles do not require a Map ID,
  /// so Android map loads remain on the unlimited-free Maps SDK SKU.
  String? get googleMapStyleJson => switch (this) {
    MapStyle.auto || MapStyle.standard => null,
    MapStyle.dark => _googleDarkStyle,
    MapStyle.pop => _googlePopStyle,
  };

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

const _googleDarkStyle = '''
[
  {"elementType":"geometry","stylers":[{"color":"#242f3e"}]},
  {"elementType":"labels.text.fill","stylers":[{"color":"#d4dbe3"}]},
  {"elementType":"labels.text.stroke","stylers":[{"color":"#242f3e"}]},
  {"featureType":"administrative.locality","elementType":"labels.text.fill","stylers":[{"color":"#f5c77a"}]},
  {"featureType":"poi","elementType":"labels.text.fill","stylers":[{"color":"#d4dbe3"}]},
  {"featureType":"poi.park","elementType":"geometry","stylers":[{"color":"#263c3f"}]},
  {"featureType":"road","elementType":"geometry","stylers":[{"color":"#38414e"}]},
  {"featureType":"road","elementType":"geometry.stroke","stylers":[{"color":"#1f2835"}]},
  {"featureType":"road.highway","elementType":"geometry","stylers":[{"color":"#6b5b45"}]},
  {"featureType":"transit","elementType":"geometry","stylers":[{"color":"#2f3948"}]},
  {"featureType":"water","elementType":"geometry","stylers":[{"color":"#17263c"}]},
  {"featureType":"water","elementType":"labels.text.fill","stylers":[{"color":"#8ea6bd"}]}
]
''';

const _googlePopStyle = '''
[
  {"elementType":"geometry","stylers":[{"color":"#f6f3e8"}]},
  {"elementType":"labels.text.fill","stylers":[{"color":"#37474f"}]},
  {"featureType":"poi.park","elementType":"geometry","stylers":[{"color":"#bfe8bf"}]},
  {"featureType":"road","elementType":"geometry","stylers":[{"color":"#ffffff"}]},
  {"featureType":"road.highway","elementType":"geometry","stylers":[{"color":"#ffd180"}]},
  {"featureType":"transit.line","elementType":"geometry","stylers":[{"color":"#90caf9"}]},
  {"featureType":"water","elementType":"geometry","stylers":[{"color":"#90caf9"}]}
]
''';
