import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../../../config/app_config.dart';
import '../../../core/map_style.dart';
import '../../../domain/entities/note_entity.dart';
import '../../../l10n/app_localizations.dart';
import '../../providers/providers.dart';
import '../../widgets/map/note_marker_bottom_sheet.dart';

enum _LocationStatus { checking, denied, ready }

class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  MapLibreMapController? _mapController;
  bool _mapReady = false;
  _LocationStatus _locationStatus = _LocationStatus.checking;
  bool _permanentlyDenied = false;
  bool _isTracking = false;
  final Map<String, NoteBoxEntity> _symbolNoteBoxMap = {};

  double? _lat;
  double? _lng;

  static const _reloadThresholdMetres = 200.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initLocation());
  }

  Future<void> _initLocation() async {
    final locationService = ref.read(locationServiceProvider);
    final permission = await locationService.ensurePermission();

    if (!mounted) return;

    if (permission == LocationPermission.deniedForever) {
      setState(() {
        _locationStatus = _LocationStatus.denied;
        _permanentlyDenied = true;
      });
      return;
    }

    if (permission == LocationPermission.denied) {
      setState(() => _locationStatus = _LocationStatus.denied);
      return;
    }

    final pos = await locationService.getCurrentPosition();
    if (!mounted) return;

    if (pos != null) {
      setState(() {
        _lat = pos.latitude;
        _lng = pos.longitude;
        _locationStatus = _LocationStatus.ready;
      });
    } else {
      setState(() => _locationStatus = _LocationStatus.checking);
    }
  }

  void _setPosition(double lat, double lng) {
    final prev = (_lat != null && _lng != null)
        ? Geolocator.distanceBetween(_lat!, _lng!, lat, lng)
        : double.infinity;

    if (prev < _reloadThresholdMetres) return;

    final wasReady = _locationStatus == _LocationStatus.ready;
    setState(() {
      _lat = lat;
      _lng = lng;
      if (_locationStatus == _LocationStatus.checking) {
        _locationStatus = _LocationStatus.ready;
      }
    });

    // When tracking, MapLibre moves the camera automatically.
    if (!_isTracking && wasReady && _mapReady && _mapController != null) {
      _mapController!.animateCamera(CameraUpdate.newLatLng(LatLng(lat, lng)));
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

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<Position>>(positionStreamProvider, (_, next) {
      next.whenData((pos) => _setPosition(pos.latitude, pos.longitude));
    });

    ref.listen<AsyncValue<Position?>>(currentPositionProvider, (_, next) {
      next.whenData((pos) {
        if (pos != null) _setPosition(pos.latitude, pos.longitude);
      });
    });

    if (_locationStatus == _LocationStatus.ready &&
        _lat != null &&
        _lng != null) {
      ref.watch(noteBoxesProvider(latLng(_lat!, _lng!))).whenData((noteBoxes) {
        if (_mapReady && _mapController != null) _updateMarkers(noteBoxes);
      });
    }

    ref.listen<MapStyle>(mapStyleProvider, (_, next) {
      _mapController?.setStyle(next.styleUrl(AppConfig.stadiaApiKey));
    });

    return switch (_locationStatus) {
      _LocationStatus.denied => _buildPermissionDeniedView(),
      _LocationStatus.checking => _buildCheckingView(),
      _LocationStatus.ready => _buildMapView(),
    };
  }

  // ── Permission denied ─────────────────────────────────────────────────────

  Widget _buildPermissionDeniedView() {
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
                if (_permanentlyDenied)
                  FilledButton.icon(
                    onPressed: Geolocator.openAppSettings,
                    icon: const Icon(Icons.settings_outlined),
                    label: Text(l10n.locationPermissionOpenSettings),
                  )
                else
                  FilledButton.icon(
                    onPressed: _initLocation,
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

  Widget _buildMapView() {
    return Scaffold(
      body: Stack(
        children: [
          // Listener detects user touch on the map to exit tracking mode.
          Listener(
            onPointerDown: (_) => _onUserPanned(),
            child: _buildMap(_lat!, _lng!),
          ),
          _buildTrackingButton(),
          _buildFab(),
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
        controller.onSymbolTapped.add(_onSymbolTapped);
      },
      onStyleLoadedCallback: _reloadMarkers,
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

  Widget _buildFab() {
    return Positioned(
      bottom: 24,
      right: 16,
      child: FloatingActionButton.extended(
        onPressed: _onAddNote,
        icon: const Icon(Icons.add_location_alt_outlined),
        label: const Text('Add Note'),
      ),
    );
  }

  Future<void> _onAddNote() async {
    final lat = _lat;
    final lng = _lng;
    if (lat == null || lng == null) return;
    if (!mounted) return;
    context.push('/note/create?lat=$lat&lng=$lng');
  }

  // ── Markers ───────────────────────────────────────────────────────────────

  Future<void> _reloadMarkers() async {
    if (_lat == null || _lng == null) return;
    final noteBoxes = await ref.read(noteRepositoryProvider).getNoteBoxesNearby(
          latitude: _lat!,
          longitude: _lng!,
          radiusKm: AppConfig.searchRadiusKm,
        );
    _updateMarkers(noteBoxes);
  }

  Future<void> _updateMarkers(List<NoteBoxEntity> noteBoxes) async {
    if (_mapController == null || !_mapReady) return;

    await _mapController!.clearSymbols();
    _symbolNoteBoxMap.clear();

    for (final noteBox in noteBoxes) {
      final symbol = await _mapController!.addSymbol(
        SymbolOptions(
          geometry: LatLng(noteBox.place.latitude, noteBox.place.longitude),
          iconImage: 'marker-15',
          iconColor: noteBox.place.colorHex,
          iconSize: 1.5,
          textField: noteBox.place.title,
          textOffset: const Offset(0, 1.5),
          textSize: 12,
        ),
      );
      _symbolNoteBoxMap[symbol.id] = noteBox;
    }
  }

  void _onSymbolTapped(Symbol symbol) {
    final noteBox = _symbolNoteBoxMap[symbol.id];
    if (noteBox == null) return;
    showModalBottomSheet(
      context: context,
      builder: (_) => NoteMarkerBottomSheet(noteBox: noteBox),
    );
  }
}
