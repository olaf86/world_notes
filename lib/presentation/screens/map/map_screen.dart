import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';

import '../../../config/app_config.dart';
import '../../../config/route_observer.dart';
import '../../../core/map_style.dart';
import '../../../core/utils/image_upload_util.dart';
import '../../../domain/entities/pin_summary_entity.dart';
import '../../../services/location_service.dart';
import '../../providers/providers.dart';
import '../../widgets/map/location_checking_view.dart';
import '../../widgets/map/location_permission_view.dart';
import '../../widgets/map/note_marker_bottom_sheet.dart';
import 'map_notes_error_messages.dart';
import 'map_diagnostics.dart';
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
    with SingleTickerProviderStateMixin, RouteAware {
  late final NoteMapAdapter _mapAdapter;
  PageRoute<dynamic>? _observedRoute;
  bool _refreshingMapNotes = false;
  String? _activePinPreviewPlaceId;

  @override
  void initState() {
    super.initState();
    logMapDiagnostics('MapScreen.initState');
    _mapAdapter = createNoteMapAdapter(
      vsync: this,
      onPinSelected: _showPinPreview,
      onResolveMarkerImage: _loadPinMarkerImage,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is! PageRoute<dynamic> || identical(route, _observedRoute)) {
      return;
    }
    if (_observedRoute != null) {
      appRouteObserver.unsubscribe(this);
    }
    _observedRoute = route;
    appRouteObserver.subscribe(this, route);
    logMapDiagnostics('MapScreen.subscribed route=${_routeLabel(route)}');
  }

  @override
  void didPushNext() {
    logMapDiagnostics(
      'MapScreen.didPushNext tracking=${ref.read(isTrackingProvider)}',
    );
  }

  @override
  void didPopNext() {
    logMapDiagnostics(
      'MapScreen.didPopNext tracking=${ref.read(isTrackingProvider)}',
    );
  }

  @override
  void dispose() {
    logMapDiagnostics('MapScreen.dispose');
    appRouteObserver.unsubscribe(this);
    _mapAdapter.dispose();
    super.dispose();
  }

  String _routeLabel(Route<dynamic> route) {
    final name = route.settings.name;
    if (name == null || name.isEmpty) return route.runtimeType.toString();
    return name;
  }

  // ── Pin tap → bottom sheet ────────────────────────────────────────────────

  Future<Uint8List?> _loadPinMarkerImage(PinSummary pin) async {
    final storagePath = pin.pinImageStoragePath;
    if (storagePath == null) return null;
    return ref
        .read(messageImageServiceProvider)
        .imageBytes(
          storagePath,
          maxSizeBytes: ImageUploadUtil.maxPinThumbnailBytes,
        );
  }

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
    final anchor =
        ref.read(positionStreamProvider).valueOrNull ??
        ref.read(anchorPositionProvider);
    if (!mounted) return false;
    if (anchor == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not get your current location.')),
      );
      return false;
    }

    try {
      await ref
          .read(noteOpenInterstitialGateProvider)
          .beforeNoteOpen(placeId: pin.placeId);
      if (!mounted) return false;
      unawaited(
        context
            .push(
              '/note/${pin.placeId}?title=${Uri.encodeComponent(pin.title)}',
              extra: NoteAccessValidationRequest(
                placeId: pin.placeId,
                latitude: anchor.latitude,
                longitude: anchor.longitude,
              ),
            )
            .then((_) => _refreshMapNotes()),
      );
      return true;
    } catch (error, stack) {
      await reportMapNotesError(
        crashlytics: ref.read(firebaseCrashlyticsProvider),
        operation: 'navigate map pin',
        error: error,
        stack: stack,
      );
      if (!mounted) return false;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text(mapNoteOpenErrorMessage)));
      return false;
    }
  }

  // ── Tracking toggle ──────────────────────────────────────────────────────

  Future<void> _toggleTracking() async {
    final notifier = ref.read(isTrackingProvider.notifier);
    final next = !notifier.state;
    logMapDiagnostics('MapScreen.toggleTracking next=$next');
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
    logMapDiagnostics('MapScreen.toggleTracking applied next=$next');
  }

  void _onUserPanned(PointerDownEvent event) {
    final wasTracking = ref.read(isTrackingProvider);
    logMapDiagnostics(
      'MapScreen.pointerDown kind=${event.kind} '
      'position=${event.position.dx.toStringAsFixed(1)},'
      '${event.position.dy.toStringAsFixed(1)} tracking=$wasTracking',
    );
    if (!wasTracking) return;
    ref.read(isTrackingProvider.notifier).state = false;
    logMapDiagnostics('MapScreen.pointerDown disables tracking');
    _mapAdapter.setTrackingEnabled(false);
  }

  _LocationRecoveryAction? _locationRecoveryActionFor(
    LocationAvailabilityIssue? issue,
  ) {
    return switch (issue) {
      LocationAvailabilityIssue.permissionPermanentlyDenied =>
        _LocationRecoveryAction(
          label: 'Enable Location',
          tooltip: 'Open settings to enable location',
          icon: Icons.settings_outlined,
          onPressed: () {
            unawaited(Geolocator.openAppSettings());
          },
        ),
      LocationAvailabilityIssue.permissionDenied => _LocationRecoveryAction(
        label: 'Enable Location',
        tooltip: 'Allow location to add notes',
        icon: Icons.location_on_outlined,
        onPressed: () {
          ref.invalidate(positionStreamProvider);
        },
      ),
      LocationAvailabilityIssue.serviceDisabled => _LocationRecoveryAction(
        label: 'Enable Location',
        tooltip: 'Open location settings',
        icon: Icons.settings_outlined,
        onPressed: () {
          unawaited(Geolocator.openLocationSettings());
        },
      ),
      null => null,
    };
  }

  void _onAddNote() {
    if (!mounted) return;

    final user = ref.read(authStateProvider).valueOrNull;
    if (user == null) return;

    logMapDiagnostics('MapScreen.push note/create');
    context.push('/note/create');
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
    } catch (error, stack) {
      await reportMapNotesError(
        crashlytics: ref.read(firebaseCrashlyticsProvider),
        operation: 'refresh map pins',
        error: error,
        stack: stack,
      );
      if (mounted) {
        showMapNotesRefreshErrorSnackBar(context);
      }
    } finally {
      if (mounted) setState(() => _refreshingMapNotes = false);
    }
  }

  void _onCameraIdle(MapCameraSnapshot camera) {
    final center = camera.center;
    final radiusKm = MapPinSearchRadius.forZoom(camera.zoom);
    final current = ref.read(mapSearchCenterProvider);
    logMapDiagnostics(
      'MapScreen.cameraIdle center=${center.lat.toStringAsFixed(6)},'
      '${center.lng.toStringAsFixed(6)} zoom=${camera.zoom.toStringAsFixed(2)}',
    );
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
      if (distance < MapPinSearchRadius.refreshThresholdMeters(radiusKm)) {
        logMapDiagnostics(
          'MapScreen.cameraIdle ignored distance=${distance.toStringAsFixed(1)}m '
          'radiusKm=$radiusKm',
        );
        return;
      }
    }
    ref.read(mapSearchCenterProvider.notifier).state = center;
    ref.read(mapSearchRadiusKmProvider.notifier).state = radiusKm;
    logMapDiagnostics('MapScreen.cameraIdle updates search center');
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final positionAsync = ref.watch(positionStreamProvider);
    final anchor = ref.watch(anchorPositionProvider);
    final isTracking = ref.watch(isTrackingProvider);
    final isAccessAreaVisible = ref.watch(isNoteAccessAreaVisibleProvider);
    final noteAccessRadiusMeters = ref.watch(noteAccessRadiusMetersProvider);
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
    final locationRecoveryAction = _locationRecoveryActionFor(
      locationAvailabilityIssueFromError(
        positionAsync.hasError ? positionAsync.error : null,
      ),
    );

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
      final currentPosition = positionAsync.valueOrNull ?? anchor;
      return _MapView(
        anchor: anchor,
        currentPosition: currentPosition,
        mapAdapter: _mapAdapter,
        isTracking: isTracking,
        isAccessAreaVisible: isAccessAreaVisible,
        noteAccessRadiusMeters: noteAccessRadiusMeters,
        onAccessAreaToggle: () {
          final notifier = ref.read(isNoteAccessAreaVisibleProvider.notifier);
          notifier.state = !notifier.state;
        },
        onPointerDown: _onUserPanned,
        onTrackingToggle: _toggleTracking,
        onRefresh: _refreshMapNotes,
        loadingMapNotes: loadingMapNotes,
        onAddNote: _onAddNote,
        locationRecoveryAction: locationRecoveryAction,
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
        issue:
            locationAvailabilityIssueFromError(e) ??
            LocationAvailabilityIssue.permissionDenied,
        onRetry: () => ref.invalidate(positionStreamProvider),
      ),
      data: (_) => const LocationCheckingView(),
    );
  }
}

class _MapView extends ConsumerWidget {
  final Position anchor;
  final Position currentPosition;
  final NoteMapAdapter mapAdapter;
  final bool isTracking;
  final bool isAccessAreaVisible;
  final int noteAccessRadiusMeters;
  final ValueChanged<PointerDownEvent> onPointerDown;
  final VoidCallback onTrackingToggle;
  final VoidCallback onAccessAreaToggle;
  final VoidCallback onRefresh;
  final bool loadingMapNotes;
  final VoidCallback onAddNote;
  final _LocationRecoveryAction? locationRecoveryAction;
  final VoidCallback? onShowList;
  final ValueChanged<MapCameraSnapshot> onCameraIdle;

  const _MapView({
    required this.anchor,
    required this.currentPosition,
    required this.mapAdapter,
    required this.isTracking,
    required this.isAccessAreaVisible,
    required this.noteAccessRadiusMeters,
    required this.onPointerDown,
    required this.onTrackingToggle,
    required this.onAccessAreaToggle,
    required this.onRefresh,
    required this.loadingMapNotes,
    required this.onAddNote,
    required this.locationRecoveryAction,
    required this.onShowList,
    required this.onCameraIdle,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mapStyle = ref.watch(mapStyleProvider).effectiveForCurrentPlatform;
    final styleUrl = mapStyle.styleUrl(AppConfig.stadiaApiKey);
    final colorScheme = Theme.of(context).colorScheme;
    unawaited(
      mapAdapter.updateAccessArea(
        center: currentPosition,
        visible: isAccessAreaVisible,
        radiusMeters: noteAccessRadiusMeters.toDouble(),
        colorScheme: colorScheme,
      ),
    );

    return Semantics(
      identifier: 'screen-map',
      child: Stack(
        children: [
          Listener(
            onPointerDown: onPointerDown,
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
          _AccessAreaButton(
            visible: isAccessAreaVisible,
            radiusMeters: noteAccessRadiusMeters,
            onPressed: onAccessAreaToggle,
          ),
          _RefreshButton(onPressed: onRefresh, refreshing: loadingMapNotes),
          _TrackingButton(isTracking: isTracking, onPressed: onTrackingToggle),
          _AddNoteFab(
            onPressed: onAddNote,
            locationRecoveryAction: locationRecoveryAction,
          ),
        ],
      ),
    );
  }
}

class _LocationRecoveryAction {
  final String label;
  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  const _LocationRecoveryAction({
    required this.label,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });
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

String _radiusLabel(int radiusMeters) {
  if (radiusMeters >= 1000 && radiusMeters % 1000 == 0) {
    return '${radiusMeters ~/ 1000} km';
  }
  return '$radiusMeters m';
}

class _AccessAreaButton extends StatelessWidget {
  final bool visible;
  final int radiusMeters;
  final VoidCallback onPressed;

  const _AccessAreaButton({
    required this.visible,
    required this.radiusMeters,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Positioned(
      bottom: 264,
      right: 16,
      child: Semantics(
        identifier: 'action-toggle-access-area',
        button: true,
        child: FloatingActionButton.small(
          heroTag: 'noteAccessArea',
          tooltip: visible
              ? 'Hide ${_radiusLabel(radiusMeters)} access area'
              : 'Show ${_radiusLabel(radiusMeters)} access area',
          onPressed: onPressed,
          backgroundColor: visible ? colorScheme.primary : colorScheme.surface,
          elevation: 2,
          child: Icon(
            Icons.radar_outlined,
            color: visible ? colorScheme.onPrimary : colorScheme.primary,
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
      child: Semantics(
        identifier: 'action-refresh-map-notes',
        button: true,
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
      child: Semantics(
        identifier: 'action-show-map-notes-list',
        button: true,
        child: FloatingActionButton.small(
          heroTag: 'mapNotesList',
          tooltip: 'List',
          onPressed: onPressed,
          backgroundColor: colorScheme.surface,
          elevation: 2,
          child: Icon(Icons.list_alt_outlined, color: colorScheme.primary),
        ),
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
      child: Semantics(
        identifier: 'action-toggle-tracking',
        button: true,
        child: FloatingActionButton.small(
          heroTag: 'tracking',
          onPressed: onPressed,
          backgroundColor: isTracking
              ? colorScheme.primary
              : colorScheme.surface,
          elevation: 2,
          child: Icon(
            isTracking ? Icons.my_location : Icons.location_searching,
            color: isTracking ? colorScheme.onPrimary : colorScheme.primary,
          ),
        ),
      ),
    );
  }
}

class _AddNoteFab extends StatelessWidget {
  final VoidCallback onPressed;
  final _LocationRecoveryAction? locationRecoveryAction;

  const _AddNoteFab({
    required this.onPressed,
    required this.locationRecoveryAction,
  });

  @override
  Widget build(BuildContext context) {
    final recoveryAction = locationRecoveryAction;
    return Positioned(
      bottom: 24,
      right: 16,
      child: Semantics(
        identifier: 'action-add-note',
        button: true,
        child: FloatingActionButton.extended(
          heroTag: 'mapAddNote',
          tooltip: recoveryAction?.tooltip ?? 'Add Note',
          onPressed: recoveryAction?.onPressed ?? onPressed,
          icon: Icon(recoveryAction?.icon ?? Icons.add_location_alt_outlined),
          label: Text(recoveryAction?.label ?? 'Add Note'),
        ),
      ),
    );
  }
}
