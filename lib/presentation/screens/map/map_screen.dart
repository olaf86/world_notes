import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../../../config/app_config.dart';
import '../../../core/map_style.dart';
import '../../../domain/entities/place_entity.dart';
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

  Future<void> _showPinPreview(PlaceEntity place) async {
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      builder: (_) => NoteMarkerBottomSheet(place: place),
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

    final user = ref.read(authStateProvider).valueOrNull;
    if (user == null) return;

    // Fast client-side PRE-CHECK only (for UX) — blocks opening the creation
    // form when the user is already at their cap, so they don't fill it out
    // just to be rejected. This is NOT the source of truth and is bypassable
    // by a direct Firestore write: rules can't aggregate a per-user count.
    // Authoritative enforcement of the free (3) / premium (10) cap moves to a
    // `createNote` Cloud Function in Phase 3, which counts and creates inside
    // a transaction (rules will then deny direct client place creation).
    final limit = ref.read(noteLimitProvider);
    final isPremium = ref.read(isPremiumProvider).valueOrNull ?? false;
    final current =
        await ref.read(placeRepositoryProvider).countUserActivePlaces(user.id);
    if (!mounted) return;

    if (current >= limit) {
      await _showLimitReachedDialog(limit: limit, isPremium: isPremium);
      return;
    }

    if (!mounted) return;
    context.push('/note/create?lat=${pos.latitude}&lng=${pos.longitude}');
  }

  Future<void> _showLimitReachedDialog({
    required int limit,
    required bool isPremium,
  }) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Note limit reached'),
        content: Text(
          isPremium
              ? 'You\'ve reached the maximum of $limit active notes. '
                  'Archive or let an existing note expire to create a new one.'
              : 'Free accounts can keep $limit active notes. '
                  'Upgrade to Premium for up to ${AppConfig.premiumNoteLimit}, '
                  'or let an existing note expire to free up a slot.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
          if (!isPremium)
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                context.push('/subscription');
              },
              child: const Text('Go Premium'),
            ),
        ],
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final positionAsync = ref.watch(positionStreamProvider);
    final anchor = ref.watch(anchorPositionProvider);
    final isTracking = ref.watch(isTrackingProvider);

    if (anchor != null) {
      ref
          .watch(placesNearbyProvider(latLng(anchor.latitude, anchor.longitude)))
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
              featureTapsTriggersMapClick: true,
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
        heroTag: 'mapAddNote',
        onPressed: onPressed,
        icon: const Icon(Icons.add_location_alt_outlined),
        label: const Text('Add Note'),
      ),
    );
  }
}
