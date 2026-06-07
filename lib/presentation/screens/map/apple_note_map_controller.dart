import 'dart:async';

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
/// This uses MapKit's native annotation clustering through the forked
/// apple_maps_flutter API so the iOS path can remove third-party tile costs
/// without changing the repository/query layer.
class AppleNoteMapController implements NoteMapAdapter {
  static const String _noteClusterId = 'world_notes_places';
  static const double _clusterMaxZoom = 14;
  static const double _selectedMarkerScale = 1.35;

  final Future<void> Function(PlaceEntity place) onPinSelected;

  AppleNoteMapController({
    required TickerProvider vsync,
    required this.onPinSelected,
  }) {
    _pinScaleController = AnimationController(
      vsync: vsync,
      duration: const Duration(milliseconds: 220),
    );
    _pinScaleAnimation = CurvedAnimation(
      parent: _pinScaleController,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    )..addListener(_onPinScaleTick);
  }

  final annotations = ValueNotifier<Set<apple.Annotation>>(
    <apple.Annotation>{},
  );
  final trackingMode = ValueNotifier<apple.TrackingMode>(
    apple.TrackingMode.none,
  );

  final Map<String, apple.BitmapDescriptor> _iconsByMarkerId = {};
  List<PlaceEntity> _latestPlaces = const [];
  apple.AppleMapController? _map;
  apple.MapAppearanceMode _appearanceMode = apple.MapAppearanceMode.light;
  bool _clusteringEnabled = AppConfig.defaultZoom < _clusterMaxZoom;
  String? _selectedPlaceId;
  int _markerRevision = 0;
  int _selectionRevision = 0;
  late final AnimationController _pinScaleController;
  late final Animation<double> _pinScaleAnimation;

  void attach(apple.AppleMapController map) {
    _map = map;
    _applyAppearanceMode(_appearanceMode);
  }

  @override
  bool get supportsMapStyle => true;

  @override
  Widget buildMap({
    required Position anchor,
    required ColorScheme colorScheme,
    required MapStyle mapStyle,
    required String styleUrl,
  }) {
    _appearanceMode = _appearanceModeFor(mapStyle);
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
              appearanceMode: _appearanceMode,
              onMapCreated: attach,
              onCameraMove: _onCameraMove,
              onCameraIdle: _onCameraIdle,
            );
          },
        );
      },
    );
  }

  @override
  void dispose() {
    _pinScaleController.dispose();
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
    final mode = _appearanceModeFor(style);
    _appearanceMode = mode;
    await _applyAppearanceMode(mode);
  }

  Future<void> _applyAppearanceMode(apple.MapAppearanceMode mode) async {
    try {
      await _map?.setAppearanceMode(mode);
    } catch (error, stack) {
      debugPrint('Failed to apply Apple map appearance: $error\n$stack');
    }
  }

  apple.MapAppearanceMode _appearanceModeFor(MapStyle style) {
    return switch (style) {
      MapStyle.auto => apple.MapAppearanceMode.unspecified,
      MapStyle.dark => apple.MapAppearanceMode.dark,
      MapStyle.standard || MapStyle.pop => apple.MapAppearanceMode.light,
    };
  }

  @override
  Future<void> updateMarkers(List<PlaceEntity> places) async {
    _latestPlaces = places;
    if (_selectedPlaceId != null &&
        !places.any((place) => place.id == _selectedPlaceId)) {
      _selectedPlaceId = null;
      _pinScaleController.value = 0;
    }
    await _rebuildAnnotations();
  }

  void _onCameraMove(apple.CameraPosition position) {
    _setClusteringEnabled(position.zoom < _clusterMaxZoom);
  }

  void _onCameraIdle() {
    unawaited(_syncClusteringWithMapZoom());
  }

  Future<void> _syncClusteringWithMapZoom() async {
    final zoom = await _map?.getZoomLevel();
    if (zoom == null) return;
    _setClusteringEnabled(zoom < _clusterMaxZoom);
  }

  void _setClusteringEnabled(bool enabled) {
    if (_clusteringEnabled == enabled) return;
    _clusteringEnabled = enabled;
    unawaited(_rebuildAnnotations());
  }

  Future<void> _showSelectedPin(PlaceEntity place) async {
    final revision = ++_selectionRevision;
    _selectedPlaceId = place.id;
    await _pinScaleController.forward(from: 0);
    if (revision != _selectionRevision) return;

    await onPinSelected(place);
    if (revision != _selectionRevision) return;

    await _pinScaleController.reverse();
    if (revision == _selectionRevision) {
      _selectedPlaceId = null;
      await _rebuildAnnotations();
    }
  }

  void _onPinScaleTick() {
    unawaited(_rebuildAnnotations());
  }

  Future<void> _rebuildAnnotations() async {
    final revision = ++_markerRevision;
    final next = <apple.Annotation>{};
    final selectedPlaceId = _selectedPlaceId;
    final selectedScale =
        1 + ((_selectedMarkerScale - 1) * _pinScaleAnimation.value);

    for (final place in _latestPlaces) {
      final isSelected = selectedPlaceId == place.id;
      final icon = await _markerIcon(
        place.icon,
        place.colorHex,
        scale: isSelected ? selectedScale : 1,
      );
      if (revision != _markerRevision) return;

      next.add(
        apple.Annotation(
          annotationId: apple.AnnotationId(
            _annotationIdFor(place.id, isSelected: isSelected),
          ),
          position: apple.LatLng(place.latitude, place.longitude),
          icon: icon,
          infoWindow: apple.InfoWindow.noText,
          clusteringIdentifier: isSelected || !_clusteringEnabled
              ? null
              : _noteClusterId,
          zIndex: isSelected ? 1 : 0,
          onTap: () => unawaited(_showSelectedPin(place)),
        ),
      );
    }

    if (revision == _markerRevision) {
      annotations.value = next;
    }
  }

  String _annotationIdFor(String placeId, {required bool isSelected}) {
    // MapKit does not reliably re-cluster an existing annotation when only
    // its clusteringIdentifier changes. Make the clustered/unclustered state
    // part of the id so zoom-threshold changes become remove/add updates.
    if (isSelected) return 'selected-$placeId';
    return '${_clusteringEnabled ? 'clustered' : 'single'}-$placeId';
  }

  Future<apple.BitmapDescriptor> _markerIcon(
    String iconName,
    String colorHex, {
    double scale = 1,
  }) async {
    final scaleKey = (scale * 100).round();
    final id = 'marker_${iconName}_${colorHex.replaceAll('#', '')}_$scaleKey';
    final cached = _iconsByMarkerId[id];
    if (cached != null) return cached;

    final bytes = await MarkerImage.render(
      iconData: placeIconData(iconName),
      color: parsePlaceColor(colorHex),
      scale: scale,
    );
    final descriptor = apple.BitmapDescriptor.fromBytes(bytes);
    _iconsByMarkerId[id] = descriptor;
    return descriptor;
  }
}
