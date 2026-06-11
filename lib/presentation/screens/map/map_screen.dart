import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';

import '../../../config/app_config.dart';
import '../../../core/map_style.dart';
import '../../../domain/entities/place_entity.dart';
import '../../../services/location_service.dart';
import '../../providers/providers.dart';
import '../../widgets/map/location_checking_view.dart';
import '../../widgets/map/location_permission_view.dart';
import '../../widgets/map/note_marker_bottom_sheet.dart';
import 'note_map_adapter.dart';
import 'note_map_adapter_factory.dart';

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
  final VoidCallback? onShowList;

  const MapScreen({super.key, this.onShowList});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen>
    with SingleTickerProviderStateMixin {
  late final NoteMapAdapter _mapAdapter;
  bool _refreshingNearby = false;
  String? _activePinPreviewPlaceId;

  @override
  void initState() {
    super.initState();
    _mapAdapter = createNoteMapAdapter(
      vsync: this,
      onPinSelected: _showPinPreview,
    );
  }

  @override
  void dispose() {
    _mapAdapter.dispose();
    super.dispose();
  }

  // ── Pin tap → bottom sheet ────────────────────────────────────────────────

  Future<void> _showPinPreview(PlaceEntity place) async {
    if (!mounted || _activePinPreviewPlaceId != null) return;

    _activePinPreviewPlaceId = place.id;
    try {
      await showModalBottomSheet<void>(
        context: context,
        builder: (_) => NoteMarkerBottomSheet(place: place),
      );
    } finally {
      if (_activePinPreviewPlaceId == place.id) {
        _activePinPreviewPlaceId = null;
      }
    }
  }

  // ── Tracking toggle ──────────────────────────────────────────────────────

  Future<void> _toggleTracking() async {
    final notifier = ref.read(isTrackingProvider.notifier);
    final next = !notifier.state;
    notifier.state = next;
    await _mapAdapter.setTrackingEnabled(next);
  }

  void _onUserPanned() {
    if (!ref.read(isTrackingProvider)) return;
    ref.read(isTrackingProvider.notifier).state = false;
    _mapAdapter.setTrackingEnabled(false);
  }

  Future<void> _onAddNote(Position pos) async {
    if (!mounted) return;

    final user = ref.read(authStateProvider).valueOrNull;
    if (user == null) return;

    // Fast client-side PRE-CHECK only (for UX) — blocks opening the creation
    // form when the user is already at their cap, so they don't fill it out
    // just to be rejected. This is NOT the source of truth and is bypassable
    // by a direct Firestore write: rules can't aggregate a per-user count.
    // Authoritative enforcement of the free / premium cap lives in the
    // `createNote` Cloud Function in Phase 3, which counts and creates inside
    // a transaction (rules will then deny direct client place creation).
    final limit = ref.read(noteLimitProvider);
    final isPremium = ref.read(isPremiumProvider).valueOrNull ?? false;
    final current = await ref
        .read(placeRepositoryProvider)
        .countUserActivePlaces(user.id);
    if (!mounted) return;

    if (current >= limit) {
      await _showLimitReachedDialog(limit: limit, isPremium: isPremium);
      return;
    }

    if (!mounted) return;
    context.push('/note/create?lat=${pos.latitude}&lng=${pos.longitude}');
  }

  Future<void> _refreshNearby() async {
    final anchor = ref.read(anchorPositionProvider);
    if (anchor == null || _refreshingNearby) return;
    setState(() => _refreshingNearby = true);
    final provider = placesNearbyProvider(
      latLng(anchor.latitude, anchor.longitude),
    );
    ref.invalidate(provider);
    try {
      await ref.read(provider.future);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not refresh nearby notes: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _refreshingNearby = false);
    }
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
                    'Upgrade to PRO for up to ${AppConfig.proNoteLimit}, '
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
              child: const Text('Go PRO'),
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
    final placesAsync = anchor == null
        ? null
        : ref.watch(
            placesNearbyProvider(latLng(anchor.latitude, anchor.longitude)),
          );
    final loadingNearbyNotes =
        _refreshingNearby || (placesAsync?.isLoading ?? false);

    placesAsync?.whenData(_mapAdapter.updateMarkers);

    if (_mapAdapter.supportsMapStyle) {
      ref.listen<MapStyle>(mapStyleProvider, (_, next) {
        _mapAdapter.changeStyle(
          next.effectiveForCurrentPlatform,
          AppConfig.stadiaApiKey,
        );
      });
    }

    if (anchor != null) {
      return _MapView(
        anchor: anchor,
        mapAdapter: _mapAdapter,
        isTracking: isTracking,
        onPointerDown: _onUserPanned,
        onTrackingToggle: _toggleTracking,
        onRefresh: _refreshNearby,
        loadingNearbyNotes: loadingNearbyNotes,
        onAddNote: () => _onAddNote(anchor),
        onShowList: widget.onShowList,
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
  final NoteMapAdapter mapAdapter;
  final bool isTracking;
  final VoidCallback onPointerDown;
  final VoidCallback onTrackingToggle;
  final VoidCallback onRefresh;
  final bool loadingNearbyNotes;
  final VoidCallback onAddNote;
  final VoidCallback? onShowList;

  const _MapView({
    required this.anchor,
    required this.mapAdapter,
    required this.isTracking,
    required this.onPointerDown,
    required this.onTrackingToggle,
    required this.onRefresh,
    required this.loadingNearbyNotes,
    required this.onAddNote,
    required this.onShowList,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mapStyle = ref.watch(mapStyleProvider).effectiveForCurrentPlatform;
    final styleUrl = mapStyle.styleUrl(AppConfig.stadiaApiKey);
    final colorScheme = Theme.of(context).colorScheme;

    return Stack(
      children: [
        Listener(
          onPointerDown: (_) => onPointerDown(),
          child: mapAdapter.buildMap(
            anchor: anchor,
            colorScheme: colorScheme,
            mapStyle: mapStyle,
            styleUrl: styleUrl,
          ),
        ),
        _NearbyNotesLoadingStatus(visible: loadingNearbyNotes),
        if (onShowList != null) _ListButton(onPressed: onShowList!),
        _RefreshButton(onPressed: onRefresh, refreshing: loadingNearbyNotes),
        _TrackingButton(isTracking: isTracking, onPressed: onTrackingToggle),
        _AddNoteFab(onPressed: onAddNote),
      ],
    );
  }
}

class _NearbyNotesLoadingStatus extends StatelessWidget {
  final bool visible;

  const _NearbyNotesLoadingStatus({required this.visible});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Positioned(
      top: 12,
      left: 16,
      right: 16,
      child: SafeArea(
        child: IgnorePointer(
          child: AnimatedSlide(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            offset: visible ? Offset.zero : const Offset(0, -0.18),
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              opacity: visible ? 1 : 0,
              child: Align(
                alignment: Alignment.topCenter,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: colorScheme.surface.withValues(alpha: 0.94),
                    borderRadius: BorderRadius.circular(999),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.12),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: colorScheme.primary,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'Loading nearby notes...',
                          style: Theme.of(context).textTheme.labelLarge
                              ?.copyWith(color: colorScheme.onSurface),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RefreshButton extends StatelessWidget {
  final VoidCallback onPressed;
  final bool refreshing;

  const _RefreshButton({required this.onPressed, required this.refreshing});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Positioned(
      bottom: 208,
      right: 16,
      child: FloatingActionButton.small(
        heroTag: 'nearbyRefresh',
        tooltip: 'Refresh nearby notes',
        onPressed: refreshing ? null : onPressed,
        backgroundColor: colorScheme.surface,
        elevation: 2,
        child: refreshing
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(Icons.refresh_outlined, color: colorScheme.primary),
      ),
    );
  }
}

class _ListButton extends StatelessWidget {
  final VoidCallback onPressed;

  const _ListButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Positioned(
      bottom: 152,
      right: 16,
      child: FloatingActionButton.small(
        heroTag: 'nearbyList',
        tooltip: 'List',
        onPressed: onPressed,
        backgroundColor: colorScheme.surface,
        elevation: 2,
        child: Icon(Icons.list_alt_outlined, color: colorScheme.primary),
      ),
    );
  }
}

class _TrackingButton extends StatelessWidget {
  final bool isTracking;
  final VoidCallback onPressed;

  const _TrackingButton({required this.isTracking, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Positioned(
      bottom: 96,
      right: 16,
      child: FloatingActionButton.small(
        heroTag: 'tracking',
        onPressed: onPressed,
        backgroundColor: isTracking ? colorScheme.primary : colorScheme.surface,
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
