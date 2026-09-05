import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

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
    'coffee' => Icons.coffee,
    'shopping' => Icons.shopping_bag,
    'hotel' => Icons.hotel,
    'directions' => Icons.directions_car,
    'hiking' => Icons.hiking,
    'pets' => Icons.pets,
    'work' => Icons.work,
    'favorite' => Icons.favorite,
    _ => Icons.place,
  };
}

/// Parses a "#RRGGBB" hex string into a Flutter [Color]. Returns the app's
/// default note color when parsing fails so the UI never crashes on bad data.
Color parsePlaceColor(String hex) {
  try {
    return Color(int.parse(hex.replaceFirst('#', '0xFF')));
  } catch (_) {
    return AppTheme.defaultNoteColor;
  }
}
