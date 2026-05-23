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
///   * watching the anchor position, tracking flag, note data, and style
///     providers
///   * pushing data and style changes into the [NoteMapController]
///   * opening the bottom-sheet preview when the controller reports a pin tap
///
/// All persistent state — anchor position with its movement-threshold rule,
/// tracking toggle — lives in Riverpod, not in this widget's State. That
/// makes the state independent of widget lifecycle and accessible from
/// other screens (e.g. a "follow me" indicator in the bottom nav).
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

  // ── Tracking toggle ──────────────────────────────────────────────────────

  Future<void> _toggleTracking() async {
    final notifier = ref.read(isTrackingProvider.notifier);
    final next = !notifier.state;
    notifier.state = next;
    await _mapController.setTrackingMode(
      next ? MyLocationTrackingMode.tracking : MyLocationTrackingMode.none,
    );
  }

  void _onUserPanned() {
    if (!ref.read(isTrackingProvider)) return;
    ref.read(isTrackingProvider.notifier).state = false;
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
    final anchor = ref.watch(anchorPositionProvider);
    final isTracking = ref.watch(isTrackingProvider);

    if (anchor != null) {
      ref
          .watch(noteBoxesProvider(latLng(anchor.latitude, anchor.longitude)))
          .whenData(_mapController.updateMarkers);
    }

    ref.listen<MapStyle>(mapStyleProvider, (_, next) {
      _mapController.changeStyle(next.styleUrl(AppConfig.stadiaApiKey));
    });

    if (anchor != null) {
      return _MapView(
        anchor: anchor,
        mapController: _mapController,
        isTracking: isTracking,
        onPointerDown: _onUserPanned,
        onTrackingToggle: _toggleTracking,
        onAddNote: () => _onAddNote(anchor),
      );
    }

    // anchor is null until the first GPS fix lands in the notifier; fall
    // back to whatever positionStreamProvider is currently reporting so we
    // can surface "denied" vs. "still searching" in the meantime.
    return positionAsync.when(
      loading: () => const LocationCheckingView(),
      error: (e, _) => LocationPermissionView(
        permanentlyDenied:
            e is LocationPermissionDeniedException && e.permanentlyDenied,
        onRetry: () => ref.invalidate(positionStreamProvider),
      ),
      data: (_) => const LocationCheckingView(),
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
