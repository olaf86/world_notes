import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../../../config/app_config.dart';
import '../../../core/utils/marker_image.dart';
import '../../../core/utils/place_icon.dart';
import '../../../domain/entities/pin_summary_entity.dart';
import 'note_map_adapter.dart';

/// Adapter between the places domain and a [MapLibreMapController].
///
/// Encapsulates everything that's specific to rendering [PinSummary]s on
/// a MapLibre map:
///   * the clustered GeoJSON source and its three style layers
///   * the per-(icon, color) marker image cache registered via `addImage`
///   * the selection-highlight overlay [Symbol] and its scale animation
///   * cluster-vs-pin tap dispatch via `queryRenderedFeatures`
///
/// The widget side stays declarative: it pipes provider data into
/// [updateMarkers], tap events into [onMapClick], and lifecycle callbacks
/// into [attach] / [onStyleLoaded] / [dispose]. The controller calls back
/// through [onPinSelected] when an individual pin is tapped, and awaits the
/// returned future before unwinding the highlight so the overlay lifetime
/// stays in sync with whatever UI (typically a bottom sheet) the widget
/// chooses to show.
class NoteMapController {
  // ── Layer / source ids ────────────────────────────────────────────────────
  static const _sourceId = 'note_places';
  static const _clusterLayerId = 'clusters';
  static const _clusterCountLayerId = 'cluster-count';
  static const _unclusteredLayerId = 'unclustered-point';
  static const _accessAreaSourceId = 'note_access_area';
  static const _accessAreaFillLayerId = 'note_access_area_fill';
  static const _accessAreaLineLayerId = 'note_access_area_line';

  // ── Cluster tuning ────────────────────────────────────────────────────────
  /// Pixel radius within which features are grouped into a cluster.
  static const double _clusterRadius = 50;

  /// Above this zoom, clustering is disabled and every pin is shown
  /// individually.
  static const int _clusterMaxZoom = 14;

  /// How much to zoom in by when a cluster is tapped. The maplibre_gl
  /// Flutter plugin doesn't expose `getClusterExpansionZoom`, so this is a
  /// pragmatic approximation that feels right in practice.
  static const double _clusterTapZoomStep = 2;

  // ── Pin sizing ────────────────────────────────────────────────────────────
  /// Multipliers applied to the (2x) bitmap rendered by [MarkerImage].
  static const double _iconSizeNormal = 0.5;
  static const double _iconSizeSelected = 0.75;

  // ── External hooks ────────────────────────────────────────────────────────
  final TickerProvider vsync;
  final OnResolvePinMarkerImage onResolveMarkerImage;

  /// Invoked when the user taps an unclustered pin. The returned future
  /// should complete when whatever UI was opened (e.g. a bottom sheet) is
  /// dismissed — the highlight overlay reverse-animates and is removed once
  /// it resolves.
  final Future<void> Function(PinSummary pin) onPinSelected;

  NoteMapController({
    required this.vsync,
    required this.onPinSelected,
    required this.onResolveMarkerImage,
  }) {
    _pinScaleController = AnimationController(
      vsync: vsync,
      duration: const Duration(milliseconds: 220),
    );
    _pinScaleAnimation = CurvedAnimation(
      parent: _pinScaleController,
      curve: Curves.easeInOut,
    )..addListener(_onPinScaleTick);
  }

  // ── Internal state ────────────────────────────────────────────────────────
  MapLibreMapController? _map;
  bool _sourceReady = false;
  final Map<String, PinSummary> _pinById = {};
  final Set<String> _registeredMarkerIds = {};
  Symbol? _selectedSymbol;
  Symbol? _animatingSymbol;
  late final AnimationController _pinScaleController;
  late final Animation<double> _pinScaleAnimation;

  /// Last places snapshot we were asked to render. Data often arrives
  /// from the provider before the GeoJSON source/layers have finished being
  /// created, so we cache it here and replay it once [_sourceReady] flips.
  List<PinSummary> _latestPins = const [];
  Position? _accessAreaCenter;
  bool _accessAreaVisible = false;
  double? _accessAreaRadiusMeters;
  Color? _accessAreaColor;

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  void attach(MapLibreMapController map) {
    _map = map;
  }

  void dispose() {
    _pinScaleController.dispose();
  }

  // ── Map operations exposed to the widget ──────────────────────────────────

  Future<void> setTrackingMode(MyLocationTrackingMode mode) async {
    await _map?.updateMyLocationTrackingMode(mode);
  }

  Future<void> changeStyle(String styleUrl) async {
    _sourceReady = false;
    await _map?.setStyle(styleUrl);
  }

  CameraPosition? get cameraPosition => _map?.cameraPosition;

  // ── Style / source / layer setup ──────────────────────────────────────────

  /// Called whenever the MapLibre style finishes loading. Re-registers the
  /// per-style state (images, source, layers) that a style swap drops, and
  /// clears any in-flight selection that referenced the previous style.
  /// Replays the most recent places snapshot so that data which arrived
  /// before the source was ready (very common on cold start) doesn't get
  /// silently dropped.
  Future<void> onStyleLoaded(ColorScheme colorScheme) async {
    _registeredMarkerIds.clear();
    _sourceReady = false;
    await _clearSelection();
    await _setupSourcesAndLayers(colorScheme);
    _sourceReady = true;
    await _pushMarkersToSource(_latestPins);
    await _pushAccessAreaToSource();
  }

  Future<void> _setupSourcesAndLayers(ColorScheme colorScheme) async {
    final map = _map;
    if (map == null) return;

    final clusterColor = _toHex(colorScheme.primary);
    final clusterTextColor = _toHex(colorScheme.onPrimary);

    await map.addSource(
      _accessAreaSourceId,
      GeojsonSourceProperties(data: _emptyFeatureCollection),
    );
    await map.addFillLayer(
      _accessAreaSourceId,
      _accessAreaFillLayerId,
      FillLayerProperties(fillColor: clusterColor, fillOpacity: 0.14),
      enableInteraction: false,
    );
    await map.addLineLayer(
      _accessAreaSourceId,
      _accessAreaLineLayerId,
      LineLayerProperties(
        lineColor: clusterColor,
        lineOpacity: 0.82,
        lineWidth: 2,
      ),
      enableInteraction: false,
    );

    await map.addSource(
      _sourceId,
      GeojsonSourceProperties(
        data: const {'type': 'FeatureCollection', 'features': []},
        cluster: true,
        clusterRadius: _clusterRadius,
        clusterMaxZoom: _clusterMaxZoom.toDouble(),
      ),
    );

    // Cluster bubble — radius grows with the count.
    await map.addCircleLayer(
      _sourceId,
      _clusterLayerId,
      CircleLayerProperties(
        circleColor: clusterColor,
        circleRadius: [
          'step',
          ['get', 'point_count'],
          18,
          10,
          22,
          30,
          28,
        ],
        circleStrokeWidth: 2,
        circleStrokeColor: '#ffffff',
        circleOpacity: 0.92,
      ),
      filter: ['has', 'point_count'],
    );

    // Cluster count label.
    await map.addSymbolLayer(
      _sourceId,
      _clusterCountLayerId,
      SymbolLayerProperties(
        textField: ['get', 'point_count_abbreviated'],
        textSize: 14,
        textColor: clusterTextColor,
        textAllowOverlap: true,
        textIgnorePlacement: true,
      ),
      filter: ['has', 'point_count'],
    );

    // Individual pins — uses each feature's iconImageId.
    await map.addSymbolLayer(
      _sourceId,
      _unclusteredLayerId,
      SymbolLayerProperties(
        iconImage: ['get', 'iconImageId'],
        iconSize: _iconSizeNormal,
        iconAnchor: 'bottom',
        iconAllowOverlap: true,
        iconIgnorePlacement: true,
        textField: ['get', 'title'],
        textSize: 12,
        textOffset: [0, 0.4],
        textAnchor: 'top',
        textOptional: true,
      ),
      filter: [
        '!',
        ['has', 'point_count'],
      ],
    );
  }

  static String _toHex(Color color) {
    final rgb = color.toARGB32() & 0x00FFFFFF;
    return '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';
  }

  // ── Marker rendering ──────────────────────────────────────────────────────

  Future<void> updateMarkers(List<PinSummary> pins) async {
    _latestPins = pins;
    if (_map == null || !_sourceReady) return;
    await _pushMarkersToSource(pins);
  }

  Future<void> updateAccessArea({
    required Position center,
    required bool visible,
    required double radiusMeters,
    required ColorScheme colorScheme,
  }) async {
    final previous = _accessAreaCenter;
    final colorChanged = _accessAreaColor != colorScheme.primary;
    final radiusChanged = _accessAreaRadiusMeters != radiusMeters;
    if (_accessAreaVisible == visible &&
        !radiusChanged &&
        !colorChanged &&
        previous?.latitude == center.latitude &&
        previous?.longitude == center.longitude) {
      return;
    }
    _accessAreaCenter = center;
    _accessAreaVisible = visible;
    _accessAreaRadiusMeters = radiusMeters;
    _accessAreaColor = colorScheme.primary;
    if (_map == null || !_sourceReady) return;

    if (colorChanged) {
      await _map?.setLayerProperties(
        _accessAreaFillLayerId,
        FillLayerProperties(
          fillColor: _toHex(colorScheme.primary),
          fillOpacity: 0.14,
        ),
      );
      await _map?.setLayerProperties(
        _accessAreaLineLayerId,
        LineLayerProperties(
          lineColor: _toHex(colorScheme.primary),
          lineOpacity: 0.82,
          lineWidth: 2,
        ),
      );
    }
    await _pushAccessAreaToSource();
  }

  Future<void> _pushAccessAreaToSource() async {
    final map = _map;
    final center = _accessAreaCenter;
    final radiusMeters = _accessAreaRadiusMeters;
    if (map == null) return;
    if (!_accessAreaVisible || center == null || radiusMeters == null) {
      await map.setGeoJsonSource(_accessAreaSourceId, _emptyFeatureCollection);
      return;
    }

    await map.setGeoJsonSource(_accessAreaSourceId, {
      'type': 'FeatureCollection',
      'features': [
        {
          'type': 'Feature',
          'geometry': {
            'type': 'Polygon',
            'coordinates': [
              _geodesicCircle(
                latitude: center.latitude,
                longitude: center.longitude,
                radiusMeters: radiusMeters,
              ),
            ],
          },
          'properties': const <String, dynamic>{},
        },
      ],
    });
  }

  static const Map<String, dynamic> _emptyFeatureCollection = {
    'type': 'FeatureCollection',
    'features': <dynamic>[],
  };

  static List<List<double>> _geodesicCircle({
    required double latitude,
    required double longitude,
    required double radiusMeters,
    int points = 72,
  }) {
    const earthRadiusMeters = 6371008.8;
    final angularDistance = radiusMeters / earthRadiusMeters;
    final latitudeRadians = latitude * math.pi / 180;
    final longitudeRadians = longitude * math.pi / 180;
    final coordinates = <List<double>>[];

    for (var index = 0; index <= points; index++) {
      final bearing = 2 * math.pi * index / points;
      final destinationLatitude = math.asin(
        math.sin(latitudeRadians) * math.cos(angularDistance) +
            math.cos(latitudeRadians) *
                math.sin(angularDistance) *
                math.cos(bearing),
      );
      final destinationLongitude =
          longitudeRadians +
          math.atan2(
            math.sin(bearing) *
                math.sin(angularDistance) *
                math.cos(latitudeRadians),
            math.cos(angularDistance) -
                math.sin(latitudeRadians) * math.sin(destinationLatitude),
          );
      coordinates.add([
        destinationLongitude * 180 / math.pi,
        destinationLatitude * 180 / math.pi,
      ]);
    }
    return coordinates;
  }

  Future<void> _pushMarkersToSource(List<PinSummary> pins) async {
    final map = _map;
    if (map == null) return;

    _pinById
      ..clear()
      ..addEntries(pins.map((p) => MapEntry(p.placeId, p)));

    // Register any (icon, color) combinations we haven't seen yet — must
    // happen before pushing features that reference them.
    final imageIdsByPlaceId = <String, String>{};
    for (final pin in pins) {
      imageIdsByPlaceId[pin.placeId] = await _ensureMarkerImage(pin);
    }

    // Underlying features changed; any selection overlay is stale.
    await _clearSelection();

    final features = pins
        .map(
          (pin) => {
            'type': 'Feature',
            'id': pin.placeId,
            'geometry': {
              'type': 'Point',
              'coordinates': [pin.longitude, pin.latitude],
            },
            'properties': {
              'iconImageId': imageIdsByPlaceId[pin.placeId],
              'title': pin.title,
            },
          },
        )
        .toList();

    await map.setGeoJsonSource(_sourceId, {
      'type': 'FeatureCollection',
      'features': features,
    });
  }

  String _markerImageId(PinSummary pin, {String? imageStoragePath}) =>
      MarkerImage.cacheKey(
        namespace: 'marker',
        iconName: pin.icon,
        colorHex: pin.colorHex,
        imageStoragePath: imageStoragePath,
        variant: pin.markerVariantKey,
      );

  Future<String> _ensureMarkerImage(PinSummary pin) async {
    final fallbackId = _markerImageId(pin);
    final photoStoragePath = pin.pinImageStoragePath;
    final photoId = photoStoragePath == null
        ? null
        : _markerImageId(pin, imageStoragePath: photoStoragePath);
    if (photoId != null && _registeredMarkerIds.contains(photoId)) {
      return photoId;
    }

    final photoBytes = photoStoragePath == null
        ? null
        : await _resolveMarkerImage(pin);
    final map = _map;
    if (map == null) return photoBytes == null ? fallbackId : photoId!;

    if (photoBytes != null) {
      try {
        final bytes = await MarkerImage.render(
          iconData: placeIconData(pin.icon),
          color: parsePlaceColor(pin.colorHex),
          imageBytes: photoBytes,
          showFollowedAuthorRing: pin.isFromFollowedAuthor,
          showUnseenDot: pin.hasUnseenMessages,
        );
        await map.addImage(photoId!, bytes);
        _registeredMarkerIds.add(photoId);
        return photoId;
      } catch (error, stack) {
        debugPrint('Failed to render pin marker image: $error\n$stack');
      }
    }

    if (_registeredMarkerIds.contains(fallbackId)) return fallbackId;

    final bytes = await MarkerImage.render(
      iconData: placeIconData(pin.icon),
      color: parsePlaceColor(pin.colorHex),
      showFollowedAuthorRing: pin.isFromFollowedAuthor,
      showUnseenDot: pin.hasUnseenMessages,
    );
    await map.addImage(fallbackId, bytes);
    _registeredMarkerIds.add(fallbackId);
    return fallbackId;
  }

  Future<Uint8List?> _resolveMarkerImage(PinSummary pin) async {
    try {
      return await onResolveMarkerImage(pin);
    } catch (error, stack) {
      debugPrint('Failed to load pin marker image: $error\n$stack');
      return null;
    }
  }

  // ── Tap handling ──────────────────────────────────────────────────────────

  Future<void> onMapClick(math.Point<double> point) async {
    final map = _map;
    if (map == null || !_sourceReady) return;

    final features = await map.queryRenderedFeatures(point, [
      _clusterLayerId,
      _unclusteredLayerId,
    ], null);
    if (features.isEmpty) return;

    final feature = features.first;
    if (feature is! Map) return;
    final props = feature['properties'];
    if (props is! Map) return;

    if (props['cluster'] == true) {
      await _handleClusterTap(feature);
    } else {
      await _handlePinTap(feature);
    }
  }

  Future<void> _handleClusterTap(Map feature) async {
    final map = _map;
    if (map == null) return;
    final coords = _coordsOf(feature);
    if (coords == null) return;

    final currentZoom = map.cameraPosition?.zoom ?? AppConfig.defaultZoom;
    final targetZoom = (currentZoom + _clusterTapZoomStep).clamp(0.0, 22.0);

    await map.animateCamera(CameraUpdate.newLatLngZoom(coords, targetZoom));
  }

  Future<void> _handlePinTap(Map feature) async {
    final map = _map;
    if (map == null) return;
    final placeId = feature['id']?.toString();
    if (placeId == null) return;
    final pin = _pinById[placeId];
    if (pin == null) return;
    final coords = _coordsOf(feature);
    if (coords == null) return;

    final imageId = await _ensureMarkerImage(pin);

    // Overlay a managed Symbol on top of the layer-rendered pin so its size
    // can be tweened. Pixel-identical to the layer pin at iconSize 0.5, so
    // adding/removing the overlay is visually invisible.
    final overlay = await map.addSymbol(
      SymbolOptions(
        geometry: coords,
        iconImage: imageId,
        iconSize: _iconSizeNormal,
        iconAnchor: 'bottom',
      ),
    );

    _selectedSymbol = overlay;
    _animatePin(overlay, toSelected: true);

    try {
      await onPinSelected(pin);
    } finally {
      // Only unwind if this selection is still current — a marker refresh
      // or another tap may have replaced it.
      if (_selectedSymbol?.id == overlay.id) {
        _animatePin(overlay, toSelected: false);
        await Future.delayed(_pinScaleController.duration!);
        await _removeOverlay(overlay);
        _selectedSymbol = null;
        _animatingSymbol = null;
      }
    }
  }

  // ── Selection animation ───────────────────────────────────────────────────

  void _onPinScaleTick() {
    final symbol = _animatingSymbol;
    final map = _map;
    if (symbol == null || map == null) return;

    if (_selectedSymbol?.id != symbol.id) return;

    final t = _pinScaleAnimation.value;
    final size = _iconSizeNormal + (_iconSizeSelected - _iconSizeNormal) * t;
    map.updateSymbol(symbol, SymbolOptions(iconSize: size)).catchError((
      Object error,
      StackTrace stack,
    ) {
      debugPrint('Pin scale updateSymbol failed: $error\n$stack');
    });
  }

  void _animatePin(Symbol symbol, {required bool toSelected}) {
    _animatingSymbol = symbol;
    if (toSelected) {
      _pinScaleController.forward();
    } else {
      _pinScaleController.reverse();
    }
  }

  Future<void> _clearSelection() async {
    final overlay = _selectedSymbol;
    _selectedSymbol = null;
    _animatingSymbol = null;
    _pinScaleController.reset();
    if (overlay != null) await _removeOverlay(overlay);
  }

  Future<void> _removeOverlay(Symbol overlay) async {
    final map = _map;
    if (map == null) return;
    try {
      await map.removeSymbol(overlay);
    } catch (error, stack) {
      debugPrint('Failed to remove selection overlay: $error\n$stack');
    }
  }

  LatLng? _coordsOf(Map feature) {
    final geom = feature['geometry'];
    if (geom is! Map) return null;
    final coords = geom['coordinates'];
    if (coords is! List || coords.length < 2) return null;
    final lng = (coords[0] as num).toDouble();
    final lat = (coords[1] as num).toDouble();
    return LatLng(lat, lng);
  }
}
