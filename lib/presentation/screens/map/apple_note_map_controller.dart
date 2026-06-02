import 'package:apple_maps_flutter/apple_maps_flutter.dart' as apple;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../../../config/app_config.dart';
import '../../../core/map_style.dart';
import '../../../core/utils/marker_image.dart';
import '../../../core/utils/place_icon.dart';
import '../../../domain/entities/place_entity.dart';
import 'note_map_adapter.dart';

/// Adapter between the places domain and Apple's native MapKit view.
///
/// This is intentionally simpler than the MapLibre controller: the public
/// apple_maps_flutter API supports annotations, camera updates, and location
/// tracking, but not MapKit's native annotation clustering. We keep the iOS
/// path lightweight so it can remove third-party tile costs without changing
/// the repository/query layer.
class AppleNoteMapController implements NoteMapAdapter {
  final Future<void> Function(PlaceEntity place) onPinSelected;

  AppleNoteMapController({required this.onPinSelected});

  final annotations = ValueNotifier<Set<apple.Annotation>>(
    <apple.Annotation>{},
  );
  final trackingMode = ValueNotifier<apple.TrackingMode>(
    apple.TrackingMode.none,
  );

  final Map<String, apple.BitmapDescriptor> _iconsByMarkerId = {};
  int _markerRevision = 0;

  void attach(apple.AppleMapController _) {}

  @override
  bool get supportsMapStyle => false;

  @override
  Widget buildMap({
    required Position anchor,
    required ColorScheme colorScheme,
    required String styleUrl,
  }) {
    return ValueListenableBuilder<Set<apple.Annotation>>(
      valueListenable: annotations,
      builder: (context, currentAnnotations, _) {
        return ValueListenableBuilder<apple.TrackingMode>(
          valueListenable: trackingMode,
          builder: (context, currentTrackingMode, _) {
            return apple.AppleMap(
              initialCameraPosition: apple.CameraPosition(
                target: apple.LatLng(anchor.latitude, anchor.longitude),
                zoom: AppConfig.defaultZoom,
              ),
              myLocationEnabled: true,
              myLocationButtonEnabled: false,
              trackingMode: currentTrackingMode,
              annotations: currentAnnotations,
              onMapCreated: attach,
            );
          },
        );
      },
    );
  }

  @override
  void dispose() {
    annotations.dispose();
    trackingMode.dispose();
  }

  @override
  Future<void> setTrackingEnabled(bool enabled) async {
    trackingMode.value = enabled
        ? apple.TrackingMode.follow
        : apple.TrackingMode.none;
  }

  @override
  Future<void> changeStyle(MapStyle style, String apiKey) async {
    // MapKit's public Flutter wrapper only exposes Apple's map types, not the
    // custom Stadia styles used by the MapLibre adapter.
  }

  @override
  Future<void> updateMarkers(List<PlaceEntity> places) async {
    final revision = ++_markerRevision;
    final next = <apple.Annotation>{};

    for (final place in places) {
      final icon = await _markerIcon(place.icon, place.colorHex);
      if (revision != _markerRevision) return;

      next.add(
        apple.Annotation(
          annotationId: apple.AnnotationId(place.id),
          position: apple.LatLng(place.latitude, place.longitude),
          icon: icon,
          infoWindow: apple.InfoWindow.noText,
          onTap: () => onPinSelected(place),
        ),
      );
    }

    if (revision == _markerRevision) {
      annotations.value = next;
    }
  }

  Future<apple.BitmapDescriptor> _markerIcon(
    String iconName,
    String colorHex,
  ) async {
    final id = 'marker_${iconName}_${colorHex.replaceAll('#', '')}';
    final cached = _iconsByMarkerId[id];
    if (cached != null) return cached;

    final bytes = await MarkerImage.render(
      iconData: placeIconData(iconName),
      color: parsePlaceColor(colorHex),
    );
    final descriptor = apple.BitmapDescriptor.fromBytes(bytes);
    _iconsByMarkerId[id] = descriptor;
    return descriptor;
  }
}
