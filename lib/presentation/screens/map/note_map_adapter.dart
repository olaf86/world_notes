import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../../../core/map_style.dart';
import '../../../domain/entities/pin_summary_entity.dart';
import '../../providers/providers.dart';

abstract class NoteMapAdapter {
  bool get supportsMapStyle;

  Widget buildMap({
    required Position anchor,
    required ColorScheme colorScheme,
    required MapStyle mapStyle,
    required String styleUrl,
    required ValueChanged<MapCameraSnapshot> onCameraIdle,
  });

  Future<void> updateMarkers(List<PinSummary> pins);

  Future<void> updateAccessArea({
    required Position center,
    required bool visible,
    required double radiusMeters,
    required ColorScheme colorScheme,
  });

  Future<void> setTrackingEnabled(bool enabled);

  Future<void> changeStyle(MapStyle style, String apiKey);

  void dispose();
}
