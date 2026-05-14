import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

  @override
  Widget build(BuildContext context) {
    final positionAsync = ref.watch(currentPositionProvider);

    return Scaffold(
      body: Stack(
        children: [
          positionAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, st) => _buildMap(
              AppConfig.defaultLatitude,
              AppConfig.defaultLongitude,
            ),
            data: (pos) => _buildMap(
              pos?.latitude ?? AppConfig.defaultLatitude,
              pos?.longitude ?? AppConfig.defaultLongitude,
            ),
          ),
          _buildFab(),
        ],
      ),
    );
  }

  Widget _buildMap(double lat, double lng) {
    _loadNoteBoxes(lat, lng);

    return MapLibreMap(
      styleString: AppConfig.mapStyleUrlWithKey(AppConfig.stadiaApiKey),
      initialCameraPosition: CameraPosition(
        target: LatLng(lat, lng),
        zoom: AppConfig.defaultZoom,
      ),
      myLocationEnabled: true,
      myLocationTrackingMode: MyLocationTrackingMode.tracking,
      onMapCreated: (controller) {
        _mapController = controller;
        _mapReady = true;
        controller.onSymbolTapped.add(_onSymbolTapped);
      },
      onStyleLoadedCallback: () => _reloadMarkers(),
    );
  }

  void _loadNoteBoxes(double lat, double lng) {
    if (!mounted) return;
    final noteBoxesAsync = ref.watch(noteBoxesProvider(latLng(lat, lng)));
    noteBoxesAsync.whenData((noteBoxes) {
      if (_mapReady && _mapController != null) {
        _updateMarkers(noteBoxes);
      }
    });
  }

  Future<void> _reloadMarkers() async {
    final pos = ref.read(currentPositionProvider).valueOrNull;
    if (pos == null) return;
    final noteBoxes = await ref
        .read(noteRepositoryProvider)
        .getNoteBoxesNearby(
          latitude: pos.latitude,
          longitude: pos.longitude,
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
          geometry: LatLng(
            noteBox.place.latitude,
            noteBox.place.longitude,
          ),
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
    final pos = ref.read(currentPositionProvider).valueOrNull;
    if (pos == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not get your location')),
      );
      return;
    }
    if (!mounted) return;
    context.push(
      '/note/create?lat=${pos.latitude}&lng=${pos.longitude}',
    );
  }
}
