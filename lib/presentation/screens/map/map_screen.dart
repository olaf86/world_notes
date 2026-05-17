import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../../../config/app_config.dart';
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
  final Map<String, NoteBoxEntity> _symbolNoteBoxMap = {};

  // Current position used for marker queries — updated by position stream.
  double? _lat;
  double? _lng;

  // Minimum movement in metres before reloading markers.
  static const _reloadThresholdMetres = 200.0;

  @override
  void initState() {
    super.initState();
    // Seed from the already-resolved FutureProvider if available.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final pos = ref.read(currentPositionProvider).valueOrNull;
      if (pos != null) _setPosition(pos.latitude, pos.longitude);
    });
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

    // Show the map immediately using the default location.
    // Camera animates to the real position once currentPositionProvider resolves.
    return Scaffold(
      body: Stack(
        children: [
          _buildMap(
            _lat ?? AppConfig.defaultLatitude,
            _lng ?? AppConfig.defaultLongitude,
          ),
          _buildFab(),
        ],
      ),
    );
  }

  Widget _buildMap(double initialLat, double initialLng) {
    return MapLibreMap(
      styleString: AppConfig.mapStyleUrlWithKey(AppConfig.stadiaApiKey),
      initialCameraPosition: CameraPosition(
        target: LatLng(initialLat, initialLng),
        zoom: AppConfig.defaultZoom,
      ),
      myLocationEnabled: true,
      myLocationTrackingMode: MyLocationTrackingMode.tracking,
      onMapCreated: (controller) {
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
