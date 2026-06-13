import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';

import '../../../config/app_config.dart';
import '../../../core/map_style.dart';
import '../../../domain/entities/pin_summary_entity.dart';
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
  bool _refreshingMapNotes = false;
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

  Future<void> _showPinPreview(PinSummary pin) async {
    if (!mounted || _activePinPreviewPlaceId != null) return;

    _activePinPreviewPlaceId = pin.placeId;
    try {
      await showModalBottomSheet<void>(
        context: context,
        builder: (_) => NoteMarkerBottomSheet(pin: pin, onOpen: _openPin),
      );
    } finally {
      if (_activePinPreviewPlaceId == pin.placeId) {
        _activePinPreviewPlaceId = null;
      }
    }
  }

  Future<bool> _openPin(PinSummary pin) async {
    final anchor = ref.read(anchorPositionProvider);
    if (!mounted) return false;
    if (anchor == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not get your current location.')),
      );
      return false;
    }

    try {
      await ref
          .read(placeRepositoryProvider)
          .validateNoteAccess(
            placeId: pin.placeId,
            latitude: anchor.latitude,
            longitude: anchor.longitude,
          );
    } catch (e) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Move closer to open this note: $e')),
      );
      return false;
    }

    if (!mounted) return false;
    try {
      unawaited(
        context.push(
          '/note/${pin.placeId}?title=${Uri.encodeComponent(pin.title)}',
        ),
      );
      return true;
    } catch (e) {
      if (!mounted) return false;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not open this note: $e')));
      return false;
    }
  }

  // ── Tracking toggle ──────────────────────────────────────────────────────

  Future<void> _toggleTracking() async {
    final notifier = ref.read(isTrackingProvider.notifier);
    final next = !notifier.state;
    notifier.state = next;
    final anchor = ref.read(anchorPositionProvider);
    if (next && anchor != null) {
      ref.read(mapSearchCenterProvider.notifier).state = latLng(
        anchor.latitude,
        anchor.longitude,
      );
      ref.read(mapSearchRadiusKmProvider.notifier).state =
          MapPinSearchRadius.forZoom(AppConfig.defaultZoom);
    }
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

  Future<void> _refreshMapNotes() async {
    final anchor = ref.read(anchorPositionProvider);
    if (anchor == null || _refreshingMapNotes) return;
    setState(() => _refreshingMapNotes = true);
    final center =
        ref.read(mapSearchCenterProvider) ??
        latLng(anchor.latitude, anchor.longitude);
    final radiusKm = ref.read(mapSearchRadiusKmProvider);
    final provider = mapPinsProvider(
      MapPinsRequest(
        center: center,
        user: latLng(anchor.latitude, anchor.longitude),
        radiusKm: radiusKm,
      ),
    );
    ref.invalidate(provider);
    try {
      await ref.read(provider.future);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not refresh map notes: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _refreshingMapNotes = false);
    }
  }

  void _onCameraIdle(MapCameraSnapshot camera) {
    final center = camera.center;
    final radiusKm = MapPinSearchRadius.forZoom(camera.zoom);
    final currentRadiusKm = ref.read(mapSearchRadiusKmProvider);
    final current = ref.read(mapSearchCenterProvider);
    if (current != null) {
      final distance = Geolocator.distanceBetween(
        current.lat,
        current.lng,
        center.lat,
        center.lng,
      );
      // Camera idle can fire for tiny movements and platform-level camera
      // settling. Keep exploration requests coarse relative to the loaded
      // radius so panning feels smooth and the map-pins API is not refreshed
      // for sub-cell jitter.
      if (distance < MapPinSearchRadius.refreshThresholdMeters(radiusKm) &&
          currentRadiusKm == radiusKm) {
        return;
      }
    }
    ref.read(mapSearchCenterProvider.notifier).state = center;
    ref.read(mapSearchRadiusKmProvider.notifier).state = radiusKm;
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
    final searchCenter = ref.watch(mapSearchCenterProvider);
    final searchRadiusKm = ref.watch(mapSearchRadiusKmProvider);
    final effectiveCenter = anchor == null
        ? null
        : searchCenter ?? latLng(anchor.latitude, anchor.longitude);
    final pinsAsync = anchor == null || effectiveCenter == null
        ? null
        : ref.watch(
            mapPinsProvider(
              MapPinsRequest(
                center: effectiveCenter,
                user: latLng(anchor.latitude, anchor.longitude),
                radiusKm: searchRadiusKm,
              ),
            ),
          );
    final loadingMapNotes =
        _refreshingMapNotes || (pinsAsync?.isLoading ?? false);

    pinsAsync?.whenData(_mapAdapter.updateMarkers);

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
        onRefresh: _refreshMapNotes,
        loadingMapNotes: loadingMapNotes,
        onAddNote: () => _onAddNote(anchor),
        onShowList: widget.onShowList,
        onCameraIdle: _onCameraIdle,
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
  final bool loadingMapNotes;
  final VoidCallback onAddNote;
  final VoidCallback? onShowList;
  final ValueChanged<MapCameraSnapshot> onCameraIdle;

  const _MapView({
    required this.anchor,
    required this.mapAdapter,
    required this.isTracking,
    required this.onPointerDown,
    required this.onTrackingToggle,
    required this.onRefresh,
    required this.loadingMapNotes,
    required this.onAddNote,
    required this.onShowList,
    required this.onCameraIdle,
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
            onCameraIdle: onCameraIdle,
          ),
        ),
        _MapNotesLoadingStatus(visible: loadingMapNotes),
        if (onShowList != null) _ListButton(onPressed: onShowList!),
        _RefreshButton(onPressed: onRefresh, refreshing: loadingMapNotes),
        _TrackingButton(isTracking: isTracking, onPressed: onTrackingToggle),
        _AddNoteFab(onPressed: onAddNote),
      ],
    );
  }
}

class _MapNotesLoadingStatus extends StatelessWidget {
  final bool visible;

  const _MapNotesLoadingStatus({required this.visible});

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
                          'Loading map notes...',
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
        heroTag: 'mapNotesRefresh',
        tooltip: 'Refresh map notes',
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
        heroTag: 'mapNotesList',
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
