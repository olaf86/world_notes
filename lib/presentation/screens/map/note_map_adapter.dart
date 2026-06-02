import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../../../core/map_style.dart';
import '../../../domain/entities/place_entity.dart';

abstract class NoteMapAdapter {
  bool get supportsMapStyle;

  Widget buildMap({
    required Position anchor,
    required ColorScheme colorScheme,
    required String styleUrl,
  });

  Future<void> updateMarkers(List<PlaceEntity> places);

  Future<void> setTrackingEnabled(bool enabled);

  Future<void> changeStyle(MapStyle style, String apiKey);

  void dispose();
}
