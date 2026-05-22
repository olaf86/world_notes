import 'dart:math' show Point;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../../../config/app_config.dart';
import '../../../core/map_style.dart';
import '../../../core/utils/marker_image.dart';
import '../../../core/utils/place_icon.dart';
import '../../../domain/entities/note_entity.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/location_service.dart';
import '../../providers/providers.dart';
import '../../widgets/map/note_marker_bottom_sheet.dart';

class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen>
    with SingleTickerProviderStateMixin {
  // ── Layer / source ids ────────────────────────────────────────────────────
  static const _sourceId = 'note_places';
  static const _clusterLayerId = 'clusters';
  static const _clusterCountLayerId = 'cluster-count';
  static const _unclusteredLayerId = 'unclustered-point';

  // ── Cluster tuning ────────────────────────────────────────────────────────
  /// Pixel radius within which features are grouped into a cluster.
  static const double _clusterRadius = 50;

  /// Above this zoom level, clustering is disabled and every pin is shown
  /// individually — even pins at literally identical coordinates will still
  /// overlap, but the user will have zoomed in enough that overlap is rare.
  static const int _clusterMaxZoom = 14;

  /// How much to zoom in by when a cluster is tapped. Not pixel-perfect
  /// vs. native getClusterExpansionZoom (which this plugin doesn't expose),
  /// but feels right in practice and clamps to a sensible max.
  static const double _clusterTapZoomStep = 2.0;

  // ── Pin sizing ────────────────────────────────────────────────────────────
  /// Marker bitmap is rendered at 2x; these are the iconSize multipliers
  /// applied at render time.
  static const double _iconSizeNormal = 0.5;
  static const double _iconSizeSelected = 0.75;

  // ── Map controller state ──────────────────────────────────────────────────
  MapLibreMapController? _mapController;
  bool _mapReady = false;
  bool _sourceReady = false;
  bool _isTracking = false;

  /// Lookup by note id — populated from the same data fed to the GeoJSON
  /// source, so tap → feature.id → entity is O(1).
  final Map<String, NoteBoxEntity> _noteBoxById = {};

  /// Marker-image ids already registered with the current map style. Cleared
  /// whenever the style reloads, since [addImage] registrations don't survive
  /// a style swap.
  final Set<String> _registeredMarkerIds = {};

  // ── Selection overlay & animation ─────────────────────────────────────────
  /// Symbol overlaid on top of the layer-rendered pin while a bottom sheet
  /// is open. Used to drive the highlight animation, since per-feature
  /// iconSize on a layer can't be animated by the current plugin API.
  Symbol? _selectedSymbol;
  Symbol? _animatingSymbol;
  late final AnimationController _pinScaleController;
  late final Animation<double> _pinScaleAnimation;

  // ── Auto-reload window ────────────────────────────────────────────────────
  Position? _anchorPos;
  static const _reloadThresholdMetres = 200.0;

  // ──────────────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _pinScaleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    _pinScaleAnimation = CurvedAnimation(
      parent: _pinScaleController,
      curve: Curves.easeInOut,
    )..addListener(_onPinScaleTick);
  }

  @override
  void dispose() {
    _pinScaleController.dispose();
    super.dispose();
  }

  void _onPinScaleTick() {
    final symbol = _animatingSymbol;
    final controller = _mapController;
    if (symbol == null || controller == null) return;

    // Skip if the selection has been cleared while we were mid-animation.
    if (_selectedSymbol?.id != symbol.id) return;

    final t = _pinScaleAnimation.value;
    final size = _iconSizeNormal + (_iconSizeSelected - _iconSizeNormal) * t;
    // Fire-and-forget: awaiting per-tick would back-pressure the animation.
    controller
        .updateSymbol(symbol, SymbolOptions(iconSize: size))
        .catchError((Object error, StackTrace stack) {
      debugPrint('Pin scale updateSymbol failed: $error\n$stack');
    });
  }

  void _animatePinHighlight(Symbol symbol, {required bool toSelected}) {
    _animatingSymbol = symbol;
    if (toSelected) {
      _pinScaleController.forward();
    } else {
      _pinScaleController.reverse();
    }
  }

  // ── Position handling ─────────────────────────────────────────────────────

  void _onPositionUpdate(Position pos) {
    final prev = _anchorPos;
    if (prev != null) {
      final dist = Geolocator.distanceBetween(
        prev.latitude,
        prev.longitude,
        pos.latitude,
        pos.longitude,
      );
      if (dist < _reloadThresholdMetres) return;
    }

    setState(() => _anchorPos = pos);

    if (prev != null && !_isTracking && _mapReady && _mapController != null) {
      _mapController!.animateCamera(
        CameraUpdate.newLatLng(LatLng(pos.latitude, pos.longitude)),
      );
    }
  }

  Future<void> _toggleTracking() async {
    final controller = _mapController;
    if (controller == null || !_mapReady) return;

    if (_isTracking) {
      setState(() => _isTracking = false);
      await controller.updateMyLocationTrackingMode(MyLocationTrackingMode.none);
    } else {
      setState(() => _isTracking = true);
      await controller.updateMyLocationTrackingMode(MyLocationTrackingMode.tracking);
    }
  }

  void _onUserPanned() {
    if (!_isTracking) return;
    setState(() => _isTracking = false);
    _mapController?.updateMyLocationTrackingMode(MyLocationTrackingMode.none);
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final positionAsync = ref.watch(positionStreamProvider);

    ref.listen<AsyncValue<Position>>(positionStreamProvider, (_, next) {
      next.whenData(_onPositionUpdate);
    });

    final anchor = _anchorPos ?? positionAsync.valueOrNull;
    if (anchor != null && _anchorPos == null) {
      _anchorPos = anchor;
    }

    if (anchor != null) {
      ref
          .watch(noteBoxesProvider(latLng(anchor.latitude, anchor.longitude)))
          .whenData((noteBoxes) {
        if (_mapReady && _sourceReady) _updateMarkers(noteBoxes);
      });
    }

    ref.listen<MapStyle>(mapStyleProvider, (_, next) {
      _mapController?.setStyle(next.styleUrl(AppConfig.stadiaApiKey));
    });

    return positionAsync.when(
      loading: () => _buildCheckingView(),
      error: (e, _) => _buildPermissionDeniedView(
        permanentlyDenied:
            e is LocationPermissionDeniedException && e.permanentlyDenied,
      ),
      data: (_) => _buildMapView(anchor!),
    );
  }

  // ── Permission denied ─────────────────────────────────────────────────────

  Widget _buildPermissionDeniedView({required bool permanentlyDenied}) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: colorScheme.surfaceContainerLow,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.location_off_outlined,
                  size: 72,
                  color: colorScheme.primary,
                ),
                const SizedBox(height: 24),
                Text(
                  l10n.locationPermissionTitle,
                  style: Theme.of(context).textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  l10n.locationPermissionMessage,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                if (permanentlyDenied)
                  FilledButton.icon(
                    onPressed: Geolocator.openAppSettings,
                    icon: const Icon(Icons.settings_outlined),
                    label: Text(l10n.locationPermissionOpenSettings),
                  )
                else
                  FilledButton.icon(
                    onPressed: () =>
                        ref.invalidate(positionStreamProvider),
                    icon: const Icon(Icons.location_on_outlined),
                    label: Text(l10n.locationPermissionOpenSettings),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Waiting for first GPS fix ─────────────────────────────────────────────

  Widget _buildCheckingView() {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: colorScheme.surfaceContainerLow,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: colorScheme.primary),
            const SizedBox(height: 20),
            Text(
              l10n.locationSearching,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Map ───────────────────────────────────────────────────────────────────

  Widget _buildMapView(Position pos) {
    return Scaffold(
      body: Stack(
        children: [
          Listener(
            onPointerDown: (_) => _onUserPanned(),
            child: _buildMap(pos.latitude, pos.longitude),
          ),
          _buildTrackingButton(),
          _buildFab(pos),
        ],
      ),
    );
  }

  Widget _buildMap(double initialLat, double initialLng) {
    final style = ref.read(mapStyleProvider);
    return MapLibreMap(
      styleString: style.styleUrl(AppConfig.stadiaApiKey),
      initialCameraPosition: CameraPosition(
        target: LatLng(initialLat, initialLng),
        zoom: AppConfig.defaultZoom,
      ),
      myLocationEnabled: true,
      myLocationTrackingMode: MyLocationTrackingMode.none,
      onMapCreated: (controller) {
        _mapReady = false;
        _mapController = controller;
        _mapReady = true;
      },
      onStyleLoadedCallback: _onStyleLoaded,
      onMapClick: _onMapClick,
    );
  }

  Widget _buildTrackingButton() {
    final colorScheme = Theme.of(context).colorScheme;
    return Positioned(
      bottom: 96,
      right: 16,
      child: FloatingActionButton.small(
        heroTag: 'tracking',
        onPressed: _toggleTracking,
        backgroundColor: _isTracking ? colorScheme.primary : colorScheme.surface,
        elevation: 2,
        child: Icon(
          _isTracking ? Icons.my_location : Icons.location_searching,
          color: _isTracking ? colorScheme.onPrimary : colorScheme.primary,
        ),
      ),
    );
  }

  Widget _buildFab(Position pos) {
    return Positioned(
      bottom: 24,
      right: 16,
      child: FloatingActionButton.extended(
        onPressed: () => _onAddNote(pos),
        icon: const Icon(Icons.add_location_alt_outlined),
        label: const Text('Add Note'),
      ),
    );
  }

  Future<void> _onAddNote(Position pos) async {
    if (!mounted) return;
    context.push('/note/create?lat=${pos.latitude}&lng=${pos.longitude}');
  }

  // ── Style / source / layers ───────────────────────────────────────────────

  Future<void> _onStyleLoaded() async {
    // Style swap drops every addImage registration and every user-added
    // source/layer, so all of the per-style state has to be rebuilt.
    _registeredMarkerIds.clear();
    _sourceReady = false;
    await _clearSelection();

    await _setupSourcesAndLayers();
    _sourceReady = true;

    await _reloadMarkers();
  }

  Future<void> _setupSourcesAndLayers() async {
    final controller = _mapController;
    if (controller == null || !mounted) return;

    final colorScheme = Theme.of(context).colorScheme;
    final clusterColor = _toHex(colorScheme.primary);
    final clusterTextColor = _toHex(colorScheme.onPrimary);

    await controller.addSource(
      _sourceId,
      GeojsonSourceProperties(
        data: const {'type': 'FeatureCollection', 'features': []},
        cluster: true,
        clusterRadius: _clusterRadius,
        clusterMaxZoom: _clusterMaxZoom.toDouble(),
      ),
    );

    // Cluster bubble — circle radius grows with the count.
    await controller.addCircleLayer(
      _sourceId,
      _clusterLayerId,
      CircleLayerProperties(
        circleColor: clusterColor,
        circleRadius: [
          'step',
          ['get', 'point_count'],
          18,
          10, 22,
          30, 28,
        ],
        circleStrokeWidth: 2,
        circleStrokeColor: '#ffffff',
        circleOpacity: 0.92,
      ),
      filter: ['has', 'point_count'],
    );

    // Cluster count label sitting on top of the bubble.
    await controller.addSymbolLayer(
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

    // Individual pins — uses each feature's iconImageId property.
    await controller.addSymbolLayer(
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
      filter: ['!', ['has', 'point_count']],
    );
  }

  String _toHex(Color color) {
    // Color.toARGB32 returns 0xAARRGGBB; mask the alpha and format as #RRGGBB.
    final rgb = color.toARGB32() & 0x00FFFFFF;
    return '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';
  }

  // ── Markers ───────────────────────────────────────────────────────────────

  Future<void> _reloadMarkers() async {
    final pos = _anchorPos;
    if (pos == null) return;
    final noteBoxes = await ref.read(noteRepositoryProvider).getNoteBoxesNearby(
          latitude: pos.latitude,
          longitude: pos.longitude,
          radiusKm: AppConfig.searchRadiusKm,
        );
    await _updateMarkers(noteBoxes);
  }

  String _markerImageId(String iconName, String colorHex) =>
      'marker_${iconName}_${colorHex.replaceAll('#', '')}';

  Future<void> _ensureMarkerImage(String iconName, String colorHex) async {
    final id = _markerImageId(iconName, colorHex);
    if (_registeredMarkerIds.contains(id)) return;
    final controller = _mapController;
    if (controller == null) return;

    final bytes = await MarkerImage.render(
      iconData: placeIconData(iconName),
      color: parsePlaceColor(colorHex),
    );
    await controller.addImage(id, bytes);
    _registeredMarkerIds.add(id);
  }

  Future<void> _updateMarkers(List<NoteBoxEntity> noteBoxes) async {
    final controller = _mapController;
    if (controller == null || !_mapReady || !_sourceReady) return;

    // Refresh the lookup map and register any new marker images first so
    // the layer's data-driven iconImage never references an unloaded id.
    _noteBoxById
      ..clear()
      ..addEntries(noteBoxes.map((nb) => MapEntry(nb.note.id, nb)));

    for (final nb in noteBoxes) {
      await _ensureMarkerImage(nb.place.icon, nb.place.colorHex);
    }

    // Underlying features changed; any selection overlay is stale.
    await _clearSelection();

    final features = noteBoxes
        .map((nb) => {
              'type': 'Feature',
              'id': nb.note.id,
              'geometry': {
                'type': 'Point',
                'coordinates': [nb.place.longitude, nb.place.latitude],
              },
              'properties': {
                'iconImageId':
                    _markerImageId(nb.place.icon, nb.place.colorHex),
                'title': nb.place.title,
              },
            })
        .toList();

    await controller.setGeoJsonSource(_sourceId, {
      'type': 'FeatureCollection',
      'features': features,
    });
  }

  // ── Tap handling ──────────────────────────────────────────────────────────

  Future<void> _onMapClick(Point<double> point, LatLng _) async {
    final controller = _mapController;
    if (controller == null || !_sourceReady) return;

    final features = await controller.queryRenderedFeatures(
      point,
      [_clusterLayerId, _unclusteredLayerId],
      null,
    );
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
    final controller = _mapController;
    if (controller == null) return;

    final coords = _coordsOf(feature);
    if (coords == null) return;

    final currentZoom =
        controller.cameraPosition?.zoom ?? AppConfig.defaultZoom;
    final targetZoom = (currentZoom + _clusterTapZoomStep).clamp(0.0, 22.0);

    await controller.animateCamera(
      CameraUpdate.newLatLngZoom(coords, targetZoom),
    );
  }

  Future<void> _handlePinTap(Map feature) async {
    final controller = _mapController;
    if (controller == null || !mounted) return;

    final noteId = feature['id']?.toString();
    if (noteId == null) return;
    final noteBox = _noteBoxById[noteId];
    if (noteBox == null) return;

    final coords = _coordsOf(feature);
    if (coords == null) return;

    await _ensureMarkerImage(noteBox.place.icon, noteBox.place.colorHex);
    final imageId =
        _markerImageId(noteBox.place.icon, noteBox.place.colorHex);

    // Overlay a managed Symbol on top of the layer-rendered pin so the size
    // can be tweened. The two pins are pixel-identical at iconSize 0.5, so
    // adding/removing the overlay is visually invisible.
    final overlay = await controller.addSymbol(
      SymbolOptions(
        geometry: coords,
        iconImage: imageId,
        iconSize: _iconSizeNormal,
        iconAnchor: 'bottom',
      ),
    );

    _selectedSymbol = overlay;
    _animatePinHighlight(overlay, toSelected: true);

    if (!mounted) {
      await _removeOverlay(overlay);
      return;
    }

    await showModalBottomSheet(
      context: context,
      builder: (_) => NoteMarkerBottomSheet(noteBox: noteBox),
    );

    if (!mounted) return;
    if (_selectedSymbol?.id != overlay.id) return;

    _animatePinHighlight(overlay, toSelected: false);
    // Let the reverse animation finish so the user sees the shrink.
    await Future.delayed(_pinScaleController.duration!);
    await _removeOverlay(overlay);
  }

  Future<void> _clearSelection() async {
    final overlay = _selectedSymbol;
    _selectedSymbol = null;
    _animatingSymbol = null;
    _pinScaleController.reset();
    if (overlay != null) await _removeOverlay(overlay);
  }

  Future<void> _removeOverlay(Symbol overlay) async {
    final controller = _mapController;
    if (controller == null) return;
    try {
      await controller.removeSymbol(overlay);
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
