import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as maplibre;

import '../../../config/app_config.dart';
import '../../../core/map_style.dart';
import '../../../domain/entities/pin_summary_entity.dart';
import '../../providers/providers.dart';
import 'note_map_adapter.dart';
import 'note_map_controller.dart';

class MapLibreNoteMapAdapter implements NoteMapAdapter {
  final NoteMapController _controller;

  MapLibreNoteMapAdapter({
    required TickerProvider vsync,
    required Future<void> Function(PinSummary pin) onPinSelected,
  }) : _controller = NoteMapController(
         vsync: vsync,
         onPinSelected: onPinSelected,
       );

  @override
  bool get supportsMapStyle => true;

  @override
  Widget buildMap({
    required Position anchor,
    required ColorScheme colorScheme,
    required MapStyle mapStyle,
    required String styleUrl,
    required ValueChanged<MapLatLng> onCameraIdle,
  }) {
    return maplibre.MapLibreMap(
      styleString: styleUrl,
      initialCameraPosition: maplibre.CameraPosition(
        target: maplibre.LatLng(anchor.latitude, anchor.longitude),
        zoom: AppConfig.defaultZoom,
      ),
      myLocationEnabled: true,
      myLocationTrackingMode: maplibre.MyLocationTrackingMode.none,
      onMapCreated: _controller.attach,
      onStyleLoadedCallback: () => _controller.onStyleLoaded(colorScheme),
      featureTapsTriggersMapClick: true,
      onMapClick: (point, _) => _controller.onMapClick(point),
      onCameraIdle: () {
        final target = _controller.cameraTarget;
        if (target != null) {
          onCameraIdle(MapLatLng(target.latitude, target.longitude));
        }
      },
    );
  }

  @override
  Future<void> updateMarkers(List<PinSummary> pins) {
    return _controller.updateMarkers(pins);
  }

  @override
  Future<void> setTrackingEnabled(bool enabled) {
    return _controller.setTrackingMode(
      enabled
          ? maplibre.MyLocationTrackingMode.tracking
          : maplibre.MyLocationTrackingMode.none,
    );
  }

  @override
  Future<void> changeStyle(MapStyle style, String apiKey) {
    return _controller.changeStyle(style.styleUrl(apiKey));
  }

  @override
  void dispose() {
    _controller.dispose();
  }
}
