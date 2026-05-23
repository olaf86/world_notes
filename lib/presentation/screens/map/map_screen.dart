import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../../../config/app_config.dart';
import '../../../core/map_style.dart';
import '../../../domain/entities/note_entity.dart';
import '../../../services/location_service.dart';
import '../../providers/providers.dart';
import '../../widgets/map/location_checking_view.dart';
import '../../widgets/map/location_permission_view.dart';
import '../../widgets/map/note_marker_bottom_sheet.dart';
import 'note_map_controller.dart';

/// Composition root of the map tab.
///
/// Responsibilities are intentionally limited to:
///   * subscribing to position / notes / map style providers
///   * applying a movement threshold before re-running the notes query
///   * pushing position changes, data changes, and style changes into the
///     [NoteMapController]
///   * opening the bottom-sheet preview when the controller reports a pin tap
///
/// Everything about MapLibre itself — source/layer setup, clustering,
/// marker images, the selection-overlay animation — lives behind the
/// controller's interface in [NoteMapController]. UI fragments that don't
/// touch the map (permission denied, GPS spinner) live in their own widgets
/// in `widgets/map/`.
class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen>
    with SingleTickerProviderStateMixin {
  late final NoteMapController _mapController;

  /// Anchor position for the current notes query window. Only updated when
  /// the user moves further than [_reloadThresholdMetres] to avoid thrashing
  /// the Firestore subscription.
  Position? _anchorPos;
  bool _isTracking = false;

  static const _reloadThresholdMetres = 200.0;

  @override
  void initState() {
    super.initState();
    _mapController = NoteMapController(
      vsync: this,
      onPinSelected: _showPinPreview,
    );
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  // ── Pin tap → bottom sheet ────────────────────────────────────────────────

  Future<void> _showPinPreview(NoteBoxEntity noteBox) async {
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      builder: (_) => NoteMarkerBottomSheet(noteBox: noteBox),
    );
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
    // Camera is intentionally left alone: tracking ON uses MapLibre's
    // built-in mode (follows automatically), and tracking OFF means the
    // user chose to keep whatever view they have — re-centering on every
    // GPS step would silently override that choice.
  }

  Future<void> _toggleTracking() async {
    final next = !_isTracking;
    setState(() => _isTracking = next);
    await _mapController.setTrackingMode(
      next ? MyLocationTrackingMode.tracking : MyLocationTrackingMode.none,
    );
  }

  void _onUserPanned() {
    if (!_isTracking) return;
    setState(() => _isTracking = false);
    _mapController.setTrackingMode(MyLocationTrackingMode.none);
  }

  Future<void> _onAddNote(Position pos) async {
    if (!mounted) return;
    context.push('/note/create?lat=${pos.latitude}&lng=${pos.longitude}');
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final positionAsync = ref.watch(positionStreamProvider);

    ref.listen<AsyncValue<Position>>(positionStreamProvider, (_, next) {
      next.whenData(_onPositionUpdate);
    });

    // The stream may already hold a value when this widget mounts (kept
    // alive across tab switches). ref.listen doesn't fire for that existing
    // value, so seed [_anchorPos] from the current snapshot when needed.
    final anchor = _anchorPos ?? positionAsync.valueOrNull;
    if (anchor != null && _anchorPos == null) {
      _anchorPos = anchor;
    }

    if (anchor != null) {
      ref
          .watch(noteBoxesProvider(latLng(anchor.latitude, anchor.longitude)))
          .whenData(_mapController.updateMarkers);
    }

    ref.listen<MapStyle>(mapStyleProvider, (_, next) {
      _mapController.changeStyle(next.styleUrl(AppConfig.stadiaApiKey));
    });

    return positionAsync.when(
      loading: () => const LocationCheckingView(),
      error: (e, _) => LocationPermissionView(
        permanentlyDenied:
            e is LocationPermissionDeniedException && e.permanentlyDenied,
        onRetry: () => ref.invalidate(positionStreamProvider),
      ),
      data: (_) => _MapView(
        anchor: anchor!,
        mapController: _mapController,
        isTracking: _isTracking,
        onPointerDown: _onUserPanned,
        onTrackingToggle: _toggleTracking,
        onAddNote: () => _onAddNote(anchor),
      ),
    );
  }
}

class _MapView extends ConsumerWidget {
  final Position anchor;
  final NoteMapController mapController;
  final bool isTracking;
  final VoidCallback onPointerDown;
  final VoidCallback onTrackingToggle;
  final VoidCallback onAddNote;

  const _MapView({
    required this.anchor,
    required this.mapController,
    required this.isTracking,
    required this.onPointerDown,
    required this.onTrackingToggle,
    required this.onAddNote,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final styleUrl =
        ref.read(mapStyleProvider).styleUrl(AppConfig.stadiaApiKey);
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: Stack(
        children: [
          Listener(
            onPointerDown: (_) => onPointerDown(),
            child: MapLibreMap(
              styleString: styleUrl,
              initialCameraPosition: CameraPosition(
                target: LatLng(anchor.latitude, anchor.longitude),
                zoom: AppConfig.defaultZoom,
              ),
              myLocationEnabled: true,
              myLocationTrackingMode: MyLocationTrackingMode.none,
              onMapCreated: mapController.attach,
              onStyleLoadedCallback: () =>
                  mapController.onStyleLoaded(colorScheme),
              onMapClick: (point, _) => mapController.onMapClick(point),
            ),
          ),
          _TrackingButton(
            isTracking: isTracking,
            onPressed: onTrackingToggle,
          ),
          _AddNoteFab(onPressed: onAddNote),
        ],
      ),
    );
  }
}

class _TrackingButton extends StatelessWidget {
  final bool isTracking;
  final VoidCallback onPressed;

  const _TrackingButton({
    required this.isTracking,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Positioned(
      bottom: 96,
      right: 16,
      child: FloatingActionButton.small(
        heroTag: 'tracking',
        onPressed: onPressed,
        backgroundColor:
            isTracking ? colorScheme.primary : colorScheme.surface,
        elevation: 2,
        child: Icon(
          isTracking ? Icons.my_location : Icons.location_searching,
          color: isTracking ? colorScheme.onPrimary : colorScheme.primary,
        ),
      ),
    );
  }
}

class _AddNoteFab extends StatelessWidget {
  final VoidCallback onPressed;

  const _AddNoteFab({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: 24,
      right: 16,
      child: FloatingActionButton.extended(
        onPressed: onPressed,
        icon: const Icon(Icons.add_location_alt_outlined),
        label: const Text('Add Note'),
      ),
    );
  }
}
