import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../../../config/app_config.dart';
import '../../../core/map_style.dart';
import '../../../core/utils/marker_image.dart';
import '../../../core/utils/place_icon.dart';
import '../../../domain/entities/note_entity.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/location_service.dart';
import '../../providers/providers.dart';
import '../../widgets/map/note_marker_bottom_sheet.dart';

class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen>
    with SingleTickerProviderStateMixin {
  MapLibreMapController? _mapController;
  bool _mapReady = false;
  bool _isTracking = false;
  final Map<String, NoteBoxEntity> _symbolNoteBoxMap = {};

  /// Marker-image ids already registered with the current map style. Cleared
  /// whenever the style reloads, since [addImage] registrations don't survive
  /// a style swap.
  final Set<String> _registeredMarkerIds = {};

  /// Symbol currently highlighted because its bottom sheet is open. Tracked so
  /// the size can be reverted on dismissal and reset when markers are rebuilt.
  Symbol? _selectedSymbol;

  /// Drives the scale animation. value=0 → normal size, value=1 → selected.
  /// The currently-animating symbol may differ from [_selectedSymbol] briefly
  /// while the reverse animation is finishing.
  late final AnimationController _pinScaleController;
  late final Animation<double> _pinScaleAnimation;
  Symbol? _animatingSymbol;

  // Symbol bitmap is rendered at 2x; these are the [SymbolOptions.iconSize]
  // multipliers applied for display.
  static const double _iconSizeNormal = 0.5;
  static const double _iconSizeSelected = 0.75;

  /// Position used for the current marker query window. Only refreshed when
  /// the user moves further than [_reloadThresholdMetres] to avoid thrashing.
  Position? _anchorPos;

  static const _reloadThresholdMetres = 200.0;

  @override
  void initState() {
    super.initState();
    _pinScaleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    _pinScaleAnimation = CurvedAnimation(
      parent: _pinScaleController,
      curve: Curves.easeInOut,
    )..addListener(_onPinScaleTick);
  }

  @override
  void dispose() {
    _pinScaleController.dispose();
    super.dispose();
  }

  void _onPinScaleTick() {
    final symbol = _animatingSymbol;
    final controller = _mapController;
    if (symbol == null || controller == null) return;

    // Filter out the expected "stale symbol" case (markers were rebuilt
    // mid-animation) up front, so the catchError below only fires on
    // genuinely unexpected failures and they don't get silently lost.
    if (!_symbolNoteBoxMap.containsKey(symbol.id)) return;

    final t = _pinScaleAnimation.value;
    final size = _iconSizeNormal + (_iconSizeSelected - _iconSizeNormal) * t;
    // Fire-and-forget: awaiting per-tick would back-pressure the animation.
    controller
        .updateSymbol(symbol, SymbolOptions(iconSize: size))
        .catchError((Object error, StackTrace stack) {
      debugPrint('Pin scale updateSymbol failed: $error\n$stack');
    });
  }

  void _animatePinHighlight(Symbol symbol, {required bool toSelected}) {
    _animatingSymbol = symbol;
    if (toSelected) {
      _pinScaleController.forward();
    } else {
      _pinScaleController.reverse();
    }
  }

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

    if (prev != null && !_isTracking && _mapReady && _mapController != null) {
      _mapController!.animateCamera(
        CameraUpdate.newLatLng(LatLng(pos.latitude, pos.longitude)),
      );
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
    final positionAsync = ref.watch(positionStreamProvider);

    ref.listen<AsyncValue<Position>>(positionStreamProvider, (_, next) {
      next.whenData(_onPositionUpdate);
    });

    // The stream may already hold a value when this widget mounts (kept alive
    // across tab switches). ref.listen doesn't fire for that existing value,
    // so seed [_anchorPos] from the current snapshot when needed.
    final anchor = _anchorPos ?? positionAsync.valueOrNull;
    if (anchor != null && _anchorPos == null) {
      _anchorPos = anchor;
    }

    if (anchor != null) {
      ref
          .watch(noteBoxesProvider(latLng(anchor.latitude, anchor.longitude)))
          .whenData((noteBoxes) {
        if (_mapReady && _mapController != null) _updateMarkers(noteBoxes);
      });
    }

    ref.listen<MapStyle>(mapStyleProvider, (_, next) {
      _mapController?.setStyle(next.styleUrl(AppConfig.stadiaApiKey));
    });

    return positionAsync.when(
      loading: () => _buildCheckingView(),
      error: (e, _) => _buildPermissionDeniedView(
        permanentlyDenied:
            e is LocationPermissionDeniedException && e.permanentlyDenied,
      ),
      data: (_) => _buildMapView(anchor!),
    );
  }

  // ── Permission denied ─────────────────────────────────────────────────────

  Widget _buildPermissionDeniedView({required bool permanentlyDenied}) {
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
                if (permanentlyDenied)
                  FilledButton.icon(
                    onPressed: Geolocator.openAppSettings,
                    icon: const Icon(Icons.settings_outlined),
                    label: Text(l10n.locationPermissionOpenSettings),
                  )
                else
                  FilledButton.icon(
                    onPressed: () =>
                        ref.invalidate(positionStreamProvider),
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

  Widget _buildMapView(Position pos) {
    return Scaffold(
      body: Stack(
        children: [
          Listener(
            onPointerDown: (_) => _onUserPanned(),
            child: _buildMap(pos.latitude, pos.longitude),
          ),
          _buildTrackingButton(),
          _buildFab(pos),
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

  Widget _buildFab(Position pos) {
    return Positioned(
      bottom: 24,
      right: 16,
      child: FloatingActionButton.extended(
        onPressed: () => _onAddNote(pos),
        icon: const Icon(Icons.add_location_alt_outlined),
        label: const Text('Add Note'),
      ),
    );
  }

  Future<void> _onAddNote(Position pos) async {
    if (!mounted) return;
    context.push('/note/create?lat=${pos.latitude}&lng=${pos.longitude}');
  }

  // ── Markers ───────────────────────────────────────────────────────────────

  Future<void> _reloadMarkers() async {
    // A style swap drops every image registered via addImage, so the cache
    // needs to be reset before we add symbols against the new style.
    _registeredMarkerIds.clear();
    final pos = _anchorPos;
    if (pos == null) return;
    final noteBoxes = await ref.read(noteRepositoryProvider).getNoteBoxesNearby(
          latitude: pos.latitude,
          longitude: pos.longitude,
          radiusKm: AppConfig.searchRadiusKm,
        );
    _updateMarkers(noteBoxes);
  }

  String _markerImageId(String iconName, String colorHex) =>
      'marker_${iconName}_${colorHex.replaceAll('#', '')}';

  Future<void> _ensureMarkerImage(String iconName, String colorHex) async {
    final id = _markerImageId(iconName, colorHex);
    if (_registeredMarkerIds.contains(id)) return;
    final controller = _mapController;
    if (controller == null) return;

    final bytes = await MarkerImage.render(
      iconData: placeIconData(iconName),
      color: parsePlaceColor(colorHex),
    );
    await controller.addImage(id, bytes);
    _registeredMarkerIds.add(id);
  }

  Future<void> _updateMarkers(List<NoteBoxEntity> noteBoxes) async {
    if (_mapController == null || !_mapReady) return;

    // Stop any in-flight highlight animation before clearing symbols so the
    // tick callback can't fire updateSymbol on the about-to-be-deleted
    // reference during the clearSymbols await.
    _selectedSymbol = null;
    _animatingSymbol = null;
    _pinScaleController.reset();

    await _mapController!.clearSymbols();
    _symbolNoteBoxMap.clear();

    for (final noteBox in noteBoxes) {
      final imageId =
          _markerImageId(noteBox.place.icon, noteBox.place.colorHex);
      await _ensureMarkerImage(noteBox.place.icon, noteBox.place.colorHex);

      final symbol = await _mapController!.addSymbol(
        SymbolOptions(
          geometry: LatLng(noteBox.place.latitude, noteBox.place.longitude),
          iconImage: imageId,
          iconSize: _iconSizeNormal,
          iconAnchor: 'bottom',
          textField: noteBox.place.title,
          textOffset: const Offset(0, 0.4),
          textSize: 12,
          textAnchor: 'top',
        ),
      );
      _symbolNoteBoxMap[symbol.id] = noteBox;
    }
  }

  Future<void> _onSymbolTapped(Symbol symbol) async {
    final noteBox = _symbolNoteBoxMap[symbol.id];
    if (noteBox == null) return;

    _selectedSymbol = symbol;
    _animatePinHighlight(symbol, toSelected: true);

    await showModalBottomSheet(
      context: context,
      builder: (_) => NoteMarkerBottomSheet(noteBox: noteBox),
    );

    // Restore size after dismissal — but only if this symbol is still the
    // active one. A marker refresh may have nulled it out via _updateMarkers.
    if (!mounted) return;
    if (_selectedSymbol?.id == symbol.id) {
      _animatePinHighlight(symbol, toSelected: false);
      _selectedSymbol = null;
    }
  }
}
