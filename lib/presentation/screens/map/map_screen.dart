import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../../../config/app_config.dart';
import '../../../core/map_style.dart';
import '../../../domain/entities/note_entity.dart';
import '../../providers/providers.dart';
import '../../widgets/map/note_marker_bottom_sheet.dart';

class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  MapLibreMapController? _mapController;
  bool _mapReady = false;
  bool _locationEnabled = false;
  double _bearing = 0.0;
  final Map<String, NoteBoxEntity> _symbolNoteBoxMap = {};

  // Current position used for marker queries — updated by position stream.
  double? _lat;
  double? _lng;

  // Minimum movement in metres before reloading markers.
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Location access is disabled. Enable it in Settings.'),
          action: SnackBarAction(
            label: 'Settings',
            onPressed: Geolocator.openAppSettings,
          ),
          duration: const Duration(seconds: 6),
        ),
      );
      return;
    }

    if (permission == LocationPermission.denied) return;

    setState(() => _locationEnabled = true);

    final pos = ref.read(currentPositionProvider).valueOrNull;
    if (pos != null) _setPosition(pos.latitude, pos.longitude);
  }

  void _setPosition(double lat, double lng) {
    final prev = (_lat != null && _lng != null)
        ? Geolocator.distanceBetween(_lat!, _lng!, lat, lng)
        : double.infinity;

    if (prev < _reloadThresholdMetres) return;

    setState(() {
      _lat = lat;
      _lng = lng;
    });

    // Animate camera to the new position when the map is already ready.
    if (_mapReady && _mapController != null) {
      _mapController!.animateCamera(
        CameraUpdate.newLatLng(LatLng(lat, lng)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Listen to the position stream; update markers on significant movement.
    ref.listen<AsyncValue<Position>>(positionStreamProvider, (_, next) {
      next.whenData((pos) => _setPosition(pos.latitude, pos.longitude));
    });

    // Animate to the user's real position as soon as it resolves.
    ref.listen<AsyncValue<Position?>>(currentPositionProvider, (_, next) {
      next.whenData((pos) {
        if (pos != null) _setPosition(pos.latitude, pos.longitude);
      });
    });


    // Watch note boxes for the current position.
    if (_lat != null && _lng != null) {
      ref.watch(noteBoxesProvider(latLng(_lat!, _lng!))).whenData((noteBoxes) {
        if (_mapReady && _mapController != null) _updateMarkers(noteBoxes);
      });
    }

    // Switch the map style at runtime via the official setStyle() API
    // (available since maplibre_gl 0.26.0).
    // onStyleLoadedCallback fires after the new tiles load and reloads markers.
    ref.listen<MapStyle>(mapStyleProvider, (_, next) {
      _mapController?.setStyle(next.styleUrl(AppConfig.stadiaApiKey));
    });

    // Show the map immediately using the default location.
    // Camera animates to the real position once currentPositionProvider resolves.
    return Scaffold(
      body: Stack(
        children: [
          _buildMap(
            _lat ?? AppConfig.defaultLatitude,
            _lng ?? AppConfig.defaultLongitude,
          ),
          if (_locationEnabled) _buildCompassButton(),
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
      myLocationEnabled: _locationEnabled,
      myLocationTrackingMode: _locationEnabled
          ? MyLocationTrackingMode.tracking
          : MyLocationTrackingMode.none,
      onMapCreated: (controller) {
        // Reset in case we are reinitialising after a style change.
        _mapReady = false;
        _mapController = controller;
        _mapReady = true;
        controller.onSymbolTapped.add(_onSymbolTapped);
        // Position may have resolved before the map was ready — jump to it now.
        if (_lat != null && _lng != null) {
          controller.animateCamera(
            CameraUpdate.newLatLng(LatLng(_lat!, _lng!)),
          );
        }
      },
      onCameraMove: (position) {
        if (mounted && position.bearing != _bearing) {
          setState(() => _bearing = position.bearing);
        }
      },
      onStyleLoadedCallback: _reloadMarkers,
    );
  }

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

  Widget _buildCompassButton() {
    final colorScheme = Theme.of(context).colorScheme;
    final isNorth = _bearing.abs() < 0.5;
    return Positioned(
      top: MediaQuery.of(context).padding.top + 16,
      right: 16,
      child: FloatingActionButton.small(
        heroTag: 'compass',
        onPressed: _onRecenter,
        backgroundColor: colorScheme.surface,
        elevation: 2,
        child: Transform.rotate(
          angle: -_bearing * math.pi / 180,
          child: Icon(
            Icons.navigation,
            color: isNorth ? colorScheme.onSurface : colorScheme.primary,
          ),
        ),
      ),
    );
  }

  Future<void> _onRecenter() async {
    final lat = _lat;
    final lng = _lng;
    if (lat == null || lng == null || _mapController == null) return;
    final zoom = _mapController!.cameraPosition?.zoom ?? AppConfig.defaultZoom;
    await _mapController!.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(target: LatLng(lat, lng), bearing: 0, zoom: zoom),
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
    if (lat == null || lng == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not get your location')),
      );
      return;
    }
    if (!mounted) return;
    context.push('/note/create?lat=$lat&lng=$lng');
  }
}
