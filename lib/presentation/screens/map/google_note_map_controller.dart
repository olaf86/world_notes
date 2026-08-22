import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as google;

import '../../../config/app_config.dart';
import '../../../core/map_style.dart';
import '../../../core/utils/marker_image.dart';
import '../../../core/utils/place_icon.dart';
import '../../../domain/entities/pin_summary_entity.dart';
import '../../providers/providers.dart';
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
  static const double _normalMarkerWidth = 48;
  static const double _selectedMarkerWidth = 72;

  final Future<void> Function(PinSummary pin) onPinSelected;
  final OnResolvePinMarkerImage onResolveMarkerImage;
  final Future<google.BitmapDescriptor> Function(PinSummary pin, bool selected)?
  markerIconBuilder;

  GoogleNoteMapController({
    required this.onPinSelected,
    required this.onResolveMarkerImage,
    this.markerIconBuilder,
  });

  final markers = ValueNotifier<Set<google.Marker>>(<google.Marker>{});
  final accessAreaCircles = ValueNotifier<Set<google.Circle>>(
    <google.Circle>{},
  );

  final Map<String, google.BitmapDescriptor> _iconsByMarkerId = {};
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
    _latestPins = pins;
    if (_selectedPlaceId != null &&
        !pins.any((pin) => pin.placeId == _selectedPlaceId)) {
      _selectedPlaceId = null;
    }
    await _rebuildMarkers();
  }

  Future<void> _rebuildMarkers() async {
    final revision = ++_markerRevision;
    final next = <google.Marker>{};

    for (final pin in _latestPins) {
      final selected = pin.placeId == _selectedPlaceId;
      final icon =
          await (markerIconBuilder?.call(pin, selected) ??
              _markerIcon(pin, selected: selected));
      if (_disposed || revision != _markerRevision) return;

      next.add(
        google.Marker(
          markerId: google.MarkerId(pin.placeId),
          clusterManagerId: _noteClusterManagerId,
          position: google.LatLng(pin.latitude, pin.longitude),
          icon: icon,
          infoWindow: google.InfoWindow.noText,
          zIndexInt: selected ? 1 : 0,
          onTap: () => unawaited(_showSelectedPin(pin)),
        ),
      );
    }

    if (!_disposed && revision == _markerRevision) {
      markers.value = next;
    }
  }

  Future<void> _showSelectedPin(PinSummary pin) async {
    final revision = ++_selectionRevision;
    _selectedPlaceId = pin.placeId;
    await _rebuildMarkers();
    await onPinSelected(pin);
    if (_disposed || revision != _selectionRevision) return;
    _selectedPlaceId = null;
    await _rebuildMarkers();
  }

  String _markerImageId(PinSummary pin, {String? imageStoragePath}) =>
      MarkerImage.cacheKey(
        namespace: 'google_marker',
        iconName: pin.icon,
        colorHex: pin.colorHex,
        imageStoragePath: imageStoragePath,
        variant: pin.markerVariantKey,
      );

  Future<google.BitmapDescriptor> _markerIcon(
    PinSummary pin, {
    required bool selected,
  }) async {
    final photoStoragePath = pin.pinImageStoragePath;
    final suffix = selected ? 'selected' : 'normal';
    final fallbackCacheId = '${_markerImageId(pin)}-$suffix';
    final photoCacheId = photoStoragePath == null
        ? null
        : '${_markerImageId(pin, imageStoragePath: photoStoragePath)}-$suffix';
    if (photoCacheId != null) {
      final cachedPhoto = _iconsByMarkerId[photoCacheId];
      if (cachedPhoto != null) return cachedPhoto;
    }

    final photoBytes = photoStoragePath == null
        ? null
        : await _resolveMarkerImage(pin);
    final cacheId = photoBytes == null ? fallbackCacheId : photoCacheId!;
    final cached = _iconsByMarkerId[cacheId];
    if (cached != null) return cached;
    final bytes = await _renderMarker(pin, photoBytes: photoBytes);
    final descriptor = google.BitmapDescriptor.bytes(
      bytes,
      width: selected ? _selectedMarkerWidth : _normalMarkerWidth,
    );
    _iconsByMarkerId[cacheId] = descriptor;
    return descriptor;
  }

  Future<Uint8List> _renderMarker(
    PinSummary pin, {
    Uint8List? photoBytes,
  }) async {
    try {
      return await MarkerImage.render(
        iconData: placeIconData(pin.icon),
        color: parsePlaceColor(pin.colorHex),
        imageBytes: photoBytes,
        showFollowedAuthorRing: pin.isFromFollowedAuthor,
        showUnseenDot: pin.hasUnseenMessages,
      );
    } catch (error, stack) {
      debugPrint('Failed to render Google pin marker image: $error\n$stack');
      return MarkerImage.render(
        iconData: placeIconData(pin.icon),
        color: parsePlaceColor(pin.colorHex),
        showFollowedAuthorRing: pin.isFromFollowedAuthor,
        showUnseenDot: pin.hasUnseenMessages,
      );
    }
  }

  Future<Uint8List?> _resolveMarkerImage(PinSummary pin) async {
    try {
      return await onResolveMarkerImage(pin);
    } catch (error, stack) {
      debugPrint('Failed to load Google pin marker image: $error\n$stack');
      return null;
    }
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
