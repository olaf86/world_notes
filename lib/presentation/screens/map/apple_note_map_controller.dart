import 'dart:async';

import 'package:apple_maps_flutter/apple_maps_flutter.dart' as apple;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../../../config/app_config.dart';
import '../../../core/map_style.dart';
import '../../../domain/entities/pin_summary_entity.dart';
import '../../providers/providers.dart';
import 'apple_marker_icons.dart';
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
  final AppleMarkerIcons _markerIcons;

  AppleNoteMapController({
    required this.onPinSelected,
    required OnResolvePinMarkerImage onResolveMarkerImage,
  }) : _markerIcons = AppleMarkerIcons(
         onResolveMarkerImage: onResolveMarkerImage,
       );

  final annotations = ValueNotifier<Set<apple.Annotation>>(
    <apple.Annotation>{},
  );
  final trackingMode = ValueNotifier<apple.TrackingMode>(
    apple.TrackingMode.none,
  );
  final accessAreaCircles = ValueNotifier<Set<apple.Circle>>(<apple.Circle>{});

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
  bool _disposed = false;
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
    _disposed = true;
    _markerRevision++;
    _selectionRevision++;
    _map = null;
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
  Future<void> changeStyle(MapStyle style) async {
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
    if (_disposed || identical(_latestPins, pins)) return;
    final stopwatch = Stopwatch()..start();
    _latestPins = pins;
    if (_selectedPlaceId != null &&
        !pins.any((pin) => pin.placeId == _selectedPlaceId)) {
      _selectedPlaceId = null;
    }
    final revision = ++_markerRevision;
    _markerIcons.retainPlaces(pins);

    // Publish coordinates synchronously with native placeholders. Custom
    // marker rendering and optional photo I/O happen after the pins exist.
    _publishAnnotations();
    logMapDiagnostics(
      'AppleMap.annotations placeholders count=${pins.length} '
      'millis=${stopwatch.elapsedMilliseconds}',
    );

    await _markerIcons.prepareFallbacks(
      pins,
      isCurrent: () => _isCurrentMarkerRevision(revision),
    );
    if (!_isCurrentMarkerRevision(revision)) return;
    _publishAnnotations();
    logMapDiagnostics(
      'AppleMap.annotations fallbacks count=${pins.length} '
      'millis=${stopwatch.elapsedMilliseconds}',
    );

    final photoPins = pins
        .where((pin) => pin.pinImageStoragePath != null)
        .toList(growable: false);
    await _markerIcons.preparePhotos(
      pins,
      isCurrent: () => _isCurrentMarkerRevision(revision),
      afterBatch: () {
        if (_isCurrentMarkerRevision(revision)) _publishAnnotations();
      },
    );
    if (!_isCurrentMarkerRevision(revision)) return;
    logMapDiagnostics(
      'AppleMap.annotations photos count=${photoPins.length} '
      'totalMillis=${stopwatch.elapsedMilliseconds}',
    );
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
    _publishAnnotations();
  }

  Future<void> _showSelectedPin(PinSummary pin) async {
    logMapDiagnostics('AppleMap.pinTap placeId=${pin.placeId}');
    final revision = ++_selectionRevision;
    _selectedPlaceId = pin.placeId;
    final annotationId = _annotationIdFor(pin.placeId);

    // Start presenting the sheet immediately. The native marker animation is
    // decorative and should not add its full duration to tap responsiveness.
    final sheetClosed = onPinSelected(pin);
    final selectionAnimation = _animateAnnotationScale(
      annotationId,
      _selectedMarkerScale,
    );

    await sheetClosed;
    logMapDiagnostics('AppleMap.pinSheetClosed placeId=${pin.placeId}');
    if (revision != _selectionRevision) return;

    await selectionAnimation;
    await _deselectAnnotation(annotationId);
    await _animateAnnotationScale(annotationId, 1);
    if (revision == _selectionRevision) {
      _selectedPlaceId = null;
    }
  }

  bool _isCurrentMarkerRevision(int revision) =>
      !_disposed && revision == _markerRevision;

  void _publishAnnotations() {
    if (_disposed) return;
    annotations.value = {
      for (final pin in _latestPins)
        apple.Annotation(
          annotationId: apple.AnnotationId(_annotationIdFor(pin.placeId)),
          position: apple.LatLng(pin.latitude, pin.longitude),
          icon:
              _markerIcons.preparedFor(pin.placeId) ??
              _markerIcons.placeholder(pin),
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
    };
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
}
