import 'dart:async';
import 'dart:typed_data';

import 'package:apple_maps_flutter/apple_maps_flutter.dart' as apple;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../../../config/app_config.dart';
import '../../../core/map_style.dart';
import '../../../core/utils/marker_image.dart';
import '../../../core/utils/place_icon.dart';
import '../../../domain/entities/pin_summary_entity.dart';
import '../../providers/providers.dart';
import 'map_diagnostics.dart';
import 'note_map_adapter.dart';

/// Adapter between the places domain and Apple's native MapKit view.
///
/// This uses MapKit's native annotation clustering through the forked
/// apple_maps_flutter API so the iOS path can remove third-party tile costs
/// without changing the repository/query layer.
class AppleNoteMapController implements NoteMapAdapter {
  static final apple.CircleId _accessAreaCircleId = apple.CircleId(
    'note_detail_access_area',
  );
  static const String _noteClusterId = 'world_notes_places';
  static const double _clusterMaxZoom = 14;
  static const double _selectedMarkerScale = 1.65;
  static const Duration _markerScaleDuration = Duration(milliseconds: 260);
  static const double _markerZIndex = 0;

  final Future<void> Function(PinSummary pin) onPinSelected;
  final OnResolvePinMarkerImage onResolveMarkerImage;

  AppleNoteMapController({
    required this.onPinSelected,
    required this.onResolveMarkerImage,
  });

  final annotations = ValueNotifier<Set<apple.Annotation>>(
    <apple.Annotation>{},
  );
  final trackingMode = ValueNotifier<apple.TrackingMode>(
    apple.TrackingMode.none,
  );
  final accessAreaCircles = ValueNotifier<Set<apple.Circle>>(<apple.Circle>{});

  final Map<String, apple.BitmapDescriptor> _iconsByMarkerId = {};
  List<PinSummary> _latestPins = const [];
  apple.AppleMapController? _map;
  apple.MapAppearanceMode _appearanceMode = apple.MapAppearanceMode.light;
  ValueChanged<MapCameraSnapshot>? _onCameraIdleChanged;
  apple.LatLng? _lastCameraTarget;
  double _lastCameraZoom = AppConfig.defaultZoom;
  bool _clusteringEnabled = AppConfig.defaultZoom < _clusterMaxZoom;
  Position? _accessAreaCenter;
  bool _accessAreaVisible = false;
  double? _accessAreaRadiusMeters;
  Color? _accessAreaColor;
  String? _selectedPlaceId;
  int _markerRevision = 0;
  int _selectionRevision = 0;
  int _cameraMoveEventsSinceIdle = 0;

  void attach(apple.AppleMapController map) {
    _map = map;
    logMapDiagnostics('AppleMap.attach');
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
    required ValueChanged<MapCameraSnapshot> onCameraIdle,
  }) {
    _appearanceMode = _appearanceModeFor(mapStyle);
    _onCameraIdleChanged = onCameraIdle;
    return ValueListenableBuilder<Set<apple.Annotation>>(
      valueListenable: annotations,
      builder: (context, currentAnnotations, _) {
        return ValueListenableBuilder<apple.TrackingMode>(
          valueListenable: trackingMode,
          builder: (context, currentTrackingMode, _) {
            return ValueListenableBuilder<Set<apple.Circle>>(
              valueListenable: accessAreaCircles,
              builder: (context, currentCircles, _) {
                logMapDiagnostics(
                  'AppleMap.build tracking=$currentTrackingMode '
                  'annotations=${currentAnnotations.length} '
                  'circles=${currentCircles.length} '
                  'appearance=$_appearanceMode',
                );
                return apple.AppleMap(
                  initialCameraPosition: apple.CameraPosition(
                    target: apple.LatLng(anchor.latitude, anchor.longitude),
                    zoom: AppConfig.defaultZoom,
                  ),
                  myLocationEnabled: true,
                  myLocationButtonEnabled: false,
                  trackingMode: currentTrackingMode,
                  annotations: currentAnnotations,
                  circles: currentCircles,
                  appearanceMode: _appearanceMode,
                  onMapCreated: attach,
                  onCameraMove: _onCameraMove,
                  onCameraIdle: _onCameraIdle,
                );
              },
            );
          },
        );
      },
    );
  }

  @override
  void dispose() {
    logMapDiagnostics('AppleMap.dispose');
    annotations.dispose();
    trackingMode.dispose();
    accessAreaCircles.dispose();
  }

  @override
  Future<void> updateAccessArea({
    required Position center,
    required bool visible,
    required double radiusMeters,
    required ColorScheme colorScheme,
  }) async {
    final color = colorScheme.primary;
    final previous = _accessAreaCenter;
    if (_accessAreaVisible == visible &&
        _accessAreaRadiusMeters == radiusMeters &&
        _accessAreaColor == color &&
        previous?.latitude == center.latitude &&
        previous?.longitude == center.longitude) {
      return;
    }
    _accessAreaVisible = visible;
    _accessAreaCenter = center;
    _accessAreaRadiusMeters = radiusMeters;
    _accessAreaColor = color;
    accessAreaCircles.value = visible
        ? {
            apple.Circle(
              circleId: _accessAreaCircleId,
              center: apple.LatLng(center.latitude, center.longitude),
              radius: radiusMeters,
              fillColor: color.withValues(alpha: 0.14),
              strokeColor: color.withValues(alpha: 0.82),
              strokeWidth: 2,
            ),
          }
        : <apple.Circle>{};
  }

  @override
  Future<void> setTrackingEnabled(bool enabled) async {
    logMapDiagnostics('AppleMap.setTrackingEnabled enabled=$enabled');
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
      logMapDiagnostics(
        'AppleMap.applyAppearance mode=$mode hasMap=${_map != null}',
      );
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
  Future<void> updateMarkers(List<PinSummary> pins) async {
    logMapDiagnostics('AppleMap.updateMarkers count=${pins.length}');
    _latestPins = pins;
    if (_selectedPlaceId != null &&
        !pins.any((pin) => pin.placeId == _selectedPlaceId)) {
      _selectedPlaceId = null;
    }
    await _rebuildAnnotations();
  }

  void _onCameraMove(apple.CameraPosition position) {
    _cameraMoveEventsSinceIdle += 1;
    if (_cameraMoveEventsSinceIdle <= 3 ||
        _cameraMoveEventsSinceIdle % 10 == 0) {
      logMapDiagnostics(
        'AppleMap.cameraMove #$_cameraMoveEventsSinceIdle '
        'target=${position.target.latitude.toStringAsFixed(6)},'
        '${position.target.longitude.toStringAsFixed(6)} '
        'zoom=${position.zoom.toStringAsFixed(2)}',
      );
    }
    _lastCameraTarget = position.target;
    _lastCameraZoom = position.zoom;
    _setClusteringEnabled(position.zoom < _clusterMaxZoom);
  }

  void _onCameraIdle() {
    logMapDiagnostics(
      'AppleMap.cameraIdle moves=$_cameraMoveEventsSinceIdle '
      'hasTarget=${_lastCameraTarget != null}',
    );
    _cameraMoveEventsSinceIdle = 0;
    final target = _lastCameraTarget;
    if (target != null) {
      _onCameraIdleChanged?.call(
        MapCameraSnapshot(
          center: MapLatLng(target.latitude, target.longitude),
          zoom: _lastCameraZoom,
        ),
      );
    }
    unawaited(_syncClusteringWithMapZoom());
  }

  Future<void> _syncClusteringWithMapZoom() async {
    final zoom = await _map?.getZoomLevel();
    if (zoom == null) return;
    _setClusteringEnabled(zoom < _clusterMaxZoom);
  }

  void _setClusteringEnabled(bool enabled) {
    if (_clusteringEnabled == enabled) return;
    logMapDiagnostics('AppleMap.clustering enabled=$enabled');
    _clusteringEnabled = enabled;
    unawaited(_rebuildAnnotations());
  }

  Future<void> _showSelectedPin(PinSummary pin) async {
    logMapDiagnostics('AppleMap.pinTap placeId=${pin.placeId}');
    final revision = ++_selectionRevision;
    _selectedPlaceId = pin.placeId;
    final annotationId = _annotationIdFor(pin.placeId);
    await _animateAnnotationScale(annotationId, _selectedMarkerScale);

    await onPinSelected(pin);
    logMapDiagnostics('AppleMap.pinSheetClosed placeId=${pin.placeId}');
    if (revision != _selectionRevision) return;

    await _deselectAnnotation(annotationId);
    await _animateAnnotationScale(annotationId, 1);
    if (revision == _selectionRevision) {
      _selectedPlaceId = null;
    }
  }

  Future<void> _rebuildAnnotations() async {
    final revision = ++_markerRevision;
    final next = <apple.Annotation>{};

    for (final pin in _latestPins) {
      final icon = await _markerIcon(pin);
      if (revision != _markerRevision) return;

      next.add(
        apple.Annotation(
          annotationId: apple.AnnotationId(_annotationIdFor(pin.placeId)),
          position: apple.LatLng(pin.latitude, pin.longitude),
          icon: icon,
          infoWindow: apple.InfoWindow.noText,
          clusteringIdentifier: !_clusteringEnabled ? null : _noteClusterId,
          // Keep every marker at the same zIndex. The iOS plugin tracks the
          // maximum zIndex monotonically, so briefly raising a selected pin can
          // make later normal taps remove/re-add annotations while MapKit is
          // handling touch state. That is the path that can leave the map
          // unable to pan after repeated bottom-sheet interactions.
          zIndex: _markerZIndex,
          onTap: () => unawaited(_showSelectedPin(pin)),
        ),
      );
    }

    if (revision == _markerRevision) {
      annotations.value = next;
    }
  }

  String _annotationIdFor(String placeId) {
    // MapKit does not reliably re-cluster an existing annotation when only
    // its clusteringIdentifier changes. Make the clustered/unclustered state
    // part of the id so zoom-threshold changes become remove/add updates.
    return '${_clusteringEnabled ? 'clustered' : 'single'}-$placeId';
  }

  Future<void> _deselectAnnotation(String annotationId) async {
    try {
      await _map?.hideMarkerInfoWindow(apple.AnnotationId(annotationId));
    } catch (error, stack) {
      debugPrint('Failed to deselect Apple map annotation: $error\n$stack');
    }
  }

  Future<void> _animateAnnotationScale(
    String annotationId,
    double scale,
  ) async {
    try {
      await _map?.animateMarkerScale(
        apple.AnnotationId(annotationId),
        scale: scale,
        duration: _markerScaleDuration,
      );
    } catch (error, stack) {
      debugPrint('Failed to animate Apple map annotation: $error\n$stack');
    }
  }

  String _markerImageId(PinSummary pin, {String? imageStoragePath}) =>
      MarkerImage.cacheKey(
        namespace: 'marker',
        iconName: pin.icon,
        colorHex: pin.colorHex,
        imageStoragePath: imageStoragePath,
        variant: pin.markerVariantKey,
      );

  Future<apple.BitmapDescriptor> _markerIcon(PinSummary pin) async {
    final fallbackId = _markerImageId(pin);
    final photoStoragePath = pin.pinImageStoragePath;
    final photoId = photoStoragePath == null
        ? null
        : _markerImageId(pin, imageStoragePath: photoStoragePath);
    if (photoId != null && _iconsByMarkerId.containsKey(photoId)) {
      return _iconsByMarkerId[photoId]!;
    }

    final photoBytes = photoStoragePath == null
        ? null
        : await _resolveMarkerImage(pin);
    if (photoBytes != null) {
      try {
        final bytes = await MarkerImage.render(
          iconData: placeIconData(pin.icon),
          color: parsePlaceColor(pin.colorHex),
          imageBytes: photoBytes,
          showFollowedAuthorRing: pin.isFromFollowedAuthor,
          showUnseenDot: pin.hasUnseenMessages,
        );
        final descriptor = apple.BitmapDescriptor.fromBytes(bytes);
        _iconsByMarkerId[photoId!] = descriptor;
        return descriptor;
      } catch (error, stack) {
        debugPrint('Failed to render Apple pin marker image: $error\n$stack');
      }
    }

    final cached = _iconsByMarkerId[fallbackId];
    if (cached != null) return cached;

    final bytes = await MarkerImage.render(
      iconData: placeIconData(pin.icon),
      color: parsePlaceColor(pin.colorHex),
      showFollowedAuthorRing: pin.isFromFollowedAuthor,
      showUnseenDot: pin.hasUnseenMessages,
    );
    final descriptor = apple.BitmapDescriptor.fromBytes(bytes);
    _iconsByMarkerId[fallbackId] = descriptor;
    return descriptor;
  }

  Future<Uint8List?> _resolveMarkerImage(PinSummary pin) async {
    try {
      return await onResolveMarkerImage(pin);
    } catch (error, stack) {
      debugPrint('Failed to load Apple pin marker image: $error\n$stack');
      return null;
    }
  }
}
