import 'package:flutter/material.dart';

const defaultMapPinIcon = 'place';

/// Maps a [PlaceEntity.icon] string (as persisted in Firestore) to its
/// Material [IconData]. Unknown values fall back to a generic pin.
IconData placeIconData(String icon) {
  return switch (icon) {
    'restaurant' => Icons.restaurant,
    'park' => Icons.park,
    'home' => Icons.home,
    'star' => Icons.star,
    'photo' => Icons.photo_camera,
    'music' => Icons.music_note,
    _ => Icons.place,
  };
}

/// Parses a "#RRGGBB" hex string into a Flutter [Color]. Returns a safe
/// fallback green when parsing fails so the UI never crashes on bad data.
Color parsePlaceColor(String hex) {
  try {
    return Color(int.parse(hex.replaceFirst('#', '0xFF')));
  } catch (_) {
    return Colors.green;
  }
}
