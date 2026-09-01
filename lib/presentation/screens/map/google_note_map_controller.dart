import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as google;

import '../../../config/app_config.dart';
import '../../../core/map_style.dart';
import '../../../domain/entities/pin_summary_entity.dart';
import '../../providers/providers.dart';
import 'google_marker_icons.dart';
import 'map_diagnostics.dart';
import 'note_map_adapter.dart';

/// Android map adapter backed by the native Google Maps SDK.
///
/// No Map ID is supplied to [google.GoogleMap]. This is intentional: native
/// map loads without a Map ID use the unlimited-free Maps SDK SKU. Marker
/// clustering, camera movement, access-area rendering, and custom pin images
/// remain encapsulated behind [NoteMapAdapter].
class GoogleNoteMapController implements NoteMapAdapter {
  static const google.CircleId _accessAreaCircleId = google.CircleId(
    'note_detail_access_area',
  );
  static const google.ClusterManagerId _noteClusterManagerId =
      google.ClusterManagerId('world_notes_places');

  final Future<void> Function(PinSummary pin) onPinSelected;
  final GoogleMarkerIcons _markerIcons;

  GoogleNoteMapController({
    required this.onPinSelected,
    required OnResolvePinMarkerImage onResolveMarkerImage,
  }) : _markerIcons = GoogleMarkerIcons(
         onResolveMarkerImage: onResolveMarkerImage,
       );

  final markers = ValueNotifier<Set<google.Marker>>(<google.Marker>{});
  final accessAreaCircles = ValueNotifier<Set<google.Circle>>(
    <google.Circle>{},
  );

  List<PinSummary> _latestPins = const [];
  google.GoogleMapController? _map;
  ValueChanged<MapCameraSnapshot>? _onCameraIdleChanged;
  google.LatLng? _lastCameraTarget;
  double _lastCameraZoom = AppConfig.defaultZoom;
  Position? _accessAreaCenter;
  bool _accessAreaVisible = false;
  double? _accessAreaRadiusMeters;
  Color? _accessAreaColor;
  String? _selectedPlaceId;
  google.BitmapDescriptor? _selectedMarkerIcon;
  bool _trackingEnabled = false;
  bool _disposed = false;
  int _markerRevision = 0;
  int _selectionRevision = 0;

  Set<google.ClusterManager> get _clusterManagers => {
    google.ClusterManager(
      clusterManagerId: _noteClusterManagerId,
      onClusterTap: (cluster) => unawaited(_zoomToCluster(cluster)),
    ),
  };

  @override
  bool get supportsMapStyle => true;

  @override
  Widget buildMap({
    required Position anchor,
    required ColorScheme colorScheme,
    required MapStyle mapStyle,
    required ValueChanged<MapCameraSnapshot> onCameraIdle,
  }) {
    _onCameraIdleChanged = onCameraIdle;
    _lastCameraTarget ??= google.LatLng(anchor.latitude, anchor.longitude);

    return AnimatedBuilder(
      animation: Listenable.merge([markers, accessAreaCircles]),
      builder: (context, _) {
        return google.GoogleMap(
          initialCameraPosition: google.CameraPosition(
            target: google.LatLng(anchor.latitude, anchor.longitude),
            zoom: AppConfig.defaultZoom,
          ),
          // Deliberately omit mapId. See the class-level billing note.
          style: mapStyle.googleMapStyleJson,
          myLocationEnabled: true,
          myLocationButtonEnabled: false,
          zoomControlsEnabled: false,
          mapToolbarEnabled: false,
          markers: markers.value,
          circles: accessAreaCircles.value,
          clusterManagers: _clusterManagers,
          onMapCreated: _attach,
          onCameraMove: _onCameraMove,
          onCameraIdle: _onCameraIdle,
        );
      },
    );
  }

  void _attach(google.GoogleMapController map) {
    if (_disposed) return;
    _map = map;
    logMapDiagnostics('GoogleMap.attach');
    if (_trackingEnabled && _accessAreaCenter != null) {
      unawaited(_moveTo(_accessAreaCenter!));
    }
  }

  void _onCameraMove(google.CameraPosition position) {
    _lastCameraTarget = position.target;
    _lastCameraZoom = position.zoom;
  }

  void _onCameraIdle() {
    final target = _lastCameraTarget;
    if (target == null) return;
    _onCameraIdleChanged?.call(
      MapCameraSnapshot(
        center: MapLatLng(target.latitude, target.longitude),
        zoom: _lastCameraZoom,
      ),
    );
  }

  @override
  Future<void> updateMarkers(List<PinSummary> pins) async {
    if (_disposed || identical(_latestPins, pins)) return;
    final stopwatch = Stopwatch()..start();
    _latestPins = pins;
    if (_selectedPlaceId != null &&
        !pins.any((pin) => pin.placeId == _selectedPlaceId)) {
      _selectedPlaceId = null;
      _selectedMarkerIcon = null;
    }
    final revision = ++_markerRevision;
    _markerIcons.retainPlaces(pins);

    // Positions are usable immediately. Native placeholders are replaced by
    // the normal custom markers as soon as their inexpensive render finishes.
    _publishMarkers();
    logMapDiagnostics(
      'GoogleMap.markers placeholders count=${pins.length} '
      'millis=${stopwatch.elapsedMilliseconds}',
    );

    await _markerIcons.prepareFallbacks(
      pins,
      isCurrent: () => _isCurrentMarkerRevision(revision),
    );
    if (!_isCurrentMarkerRevision(revision)) return;
    _publishMarkers();
    logMapDiagnostics(
      'GoogleMap.markers fallbacks count=${pins.length} '
      'millis=${stopwatch.elapsedMilliseconds}',
    );

    final photoPins = pins
        .where((pin) => pin.pinImageStoragePath != null)
        .toList(growable: false);
    await _markerIcons.preparePhotos(
      pins,
      isCurrent: () => _isCurrentMarkerRevision(revision),
      afterBatch: () {
        if (_isCurrentMarkerRevision(revision)) _publishMarkers();
      },
    );
    if (!_isCurrentMarkerRevision(revision)) return;
    logMapDiagnostics(
      'GoogleMap.markers photos count=${photoPins.length} '
      'totalMillis=${stopwatch.elapsedMilliseconds}',
    );
  }

  bool _isCurrentMarkerRevision(int revision) =>
      !_disposed && revision == _markerRevision;

  void _publishMarkers() {
    if (_disposed) return;
    markers.value = {
      for (final pin in _latestPins)
        google.Marker(
          markerId: google.MarkerId(pin.placeId),
          clusterManagerId: _noteClusterManagerId,
          position: google.LatLng(pin.latitude, pin.longitude),
          icon: pin.placeId == _selectedPlaceId
              ? _selectedMarkerIcon ??
                    _markerIcons.preparedFor(pin.placeId) ??
                    _markerIcons.placeholder(pin)
              : _markerIcons.preparedFor(pin.placeId) ??
                    _markerIcons.placeholder(pin),
          infoWindow: google.InfoWindow.noText,
          zIndexInt: pin.placeId == _selectedPlaceId ? 1 : 0,
          onTap: () => unawaited(_showSelectedPin(pin)),
        ),
    };
  }

  Future<void> _showSelectedPin(PinSummary pin) async {
    final revision = ++_selectionRevision;
    _selectedPlaceId = pin.placeId;
    _selectedMarkerIcon = null;
    _publishMarkers();
    final selectedIcon = await _markerIcons.selected(pin);
    if (_disposed || revision != _selectionRevision) return;
    _selectedMarkerIcon = selectedIcon;
    _publishMarkers();
    await onPinSelected(pin);
    if (_disposed || revision != _selectionRevision) return;
    _selectedPlaceId = null;
    _selectedMarkerIcon = null;
    _publishMarkers();
  }

  @override
  Future<void> updateAccessArea({
    required Position center,
    required bool visible,
    required double radiusMeters,
    required ColorScheme colorScheme,
  }) async {
    final previous = _accessAreaCenter;
    final centerChanged =
        previous?.latitude != center.latitude ||
        previous?.longitude != center.longitude;
    final color = colorScheme.primary;
    final changed =
        _accessAreaVisible != visible ||
        _accessAreaRadiusMeters != radiusMeters ||
        _accessAreaColor != color ||
        centerChanged;

    _accessAreaVisible = visible;
    _accessAreaCenter = center;
    _accessAreaRadiusMeters = radiusMeters;
    _accessAreaColor = color;

    if (changed && !_disposed) {
      accessAreaCircles.value = visible
          ? {
              google.Circle(
                circleId: _accessAreaCircleId,
                center: google.LatLng(center.latitude, center.longitude),
                radius: radiusMeters,
                fillColor: color.withValues(alpha: 0.14),
                strokeColor: color.withValues(alpha: 0.82),
                strokeWidth: 2,
              ),
            }
          : <google.Circle>{};
    }

    if (_trackingEnabled && centerChanged) {
      await _moveTo(center);
    }
  }

  @override
  Future<void> setTrackingEnabled(bool enabled) async {
    logMapDiagnostics('GoogleMap.setTrackingEnabled enabled=$enabled');
    _trackingEnabled = enabled;
    final center = _accessAreaCenter;
    if (enabled && center != null) await _moveTo(center);
  }

  Future<void> _moveTo(Position position) async {
    try {
      await _map?.animateCamera(
        google.CameraUpdate.newLatLng(
          google.LatLng(position.latitude, position.longitude),
        ),
      );
    } catch (error, stack) {
      debugPrint('Failed to move Google map camera: $error\n$stack');
    }
  }

  Future<void> _zoomToCluster(google.Cluster cluster) async {
    try {
      await _map?.animateCamera(
        google.CameraUpdate.newLatLngBounds(cluster.bounds, 64),
      );
    } catch (error, stack) {
      debugPrint('Failed to zoom Google map cluster: $error\n$stack');
    }
  }

  @override
  Future<void> changeStyle(MapStyle style) async {}

  @override
  void dispose() {
    _disposed = true;
    _markerRevision++;
    _selectionRevision++;
    _map = null;
    markers.dispose();
    accessAreaCircles.dispose();
  }
}
