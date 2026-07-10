import 'dart:async';

import 'package:apple_maps_flutter/apple_maps_flutter.dart' as apple;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as maplibre;

import '../../../config/app_config.dart';
import '../../../core/map_style.dart';
import '../../../core/utils/marker_image.dart';
import '../../../core/utils/place_icon.dart';
import '../../../domain/entities/place_entity.dart';
import '../../providers/providers.dart';

class StaticNoteMiniMap extends ConsumerStatefulWidget {
  final PlaceEntity place;
  final Widget? topRightOverlay;

  const StaticNoteMiniMap({
    super.key,
    required this.place,
    this.topRightOverlay,
  });

  @override
  ConsumerState<StaticNoteMiniMap> createState() => _StaticNoteMiniMapState();
}

class _StaticNoteMiniMapState extends ConsumerState<StaticNoteMiniMap> {
  static const double _markerIconSize = 1.3;

  maplibre.MapLibreMapController? _map;
  apple.BitmapDescriptor? _appleMarkerIcon;
  bool _styleLoaded = false;
  int _appleMarkerRevision = 0;

  bool get _usesAppleMaps =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  @override
  void initState() {
    super.initState();
    if (_usesAppleMaps) {
      unawaited(_renderAppleMarker());
    }
  }

  @override
  void didUpdateWidget(StaticNoteMiniMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.place.latitude != widget.place.latitude ||
        oldWidget.place.longitude != widget.place.longitude ||
        oldWidget.place.colorHex != widget.place.colorHex ||
        oldWidget.place.icon != widget.place.icon ||
        oldWidget.place.pinImageStoragePath !=
            widget.place.pinImageStoragePath) {
      if (_usesAppleMaps) {
        unawaited(_renderAppleMarker());
      } else {
        unawaited(_renderMapLibreMarker());
      }
    }
  }

  void _onMapCreated(maplibre.MapLibreMapController controller) {
    _map = controller;
  }

  Future<void> _onStyleLoaded() async {
    _styleLoaded = true;
    await _renderMapLibreMarker();
  }

  Future<void> _renderMapLibreMarker() async {
    final map = _map;
    if (!_styleLoaded || map == null) return;

    final place = widget.place;
    final color = parsePlaceColor(place.colorHex);
    final imageName = _markerImageId(place);
    final imageBytes = await _pinImageBytes(place.pinImageStoragePath);
    final markerBytes = await MarkerImage.render(
      iconData: placeIconData(place.icon),
      color: color,
      imageBytes: imageBytes,
    );

    await map.clearSymbols();
    await map.addImage(imageName, markerBytes);
    await map.addSymbol(
      maplibre.SymbolOptions(
        geometry: maplibre.LatLng(place.latitude, place.longitude),
        iconImage: imageName,
        iconSize: _markerIconSize,
        iconAnchor: 'center',
      ),
    );
  }

  Future<void> _renderAppleMarker() async {
    final revision = ++_appleMarkerRevision;
    final place = widget.place;
    final imageBytes = await _pinImageBytes(place.pinImageStoragePath);
    final markerBytes = await MarkerImage.render(
      iconData: placeIconData(place.icon),
      color: parsePlaceColor(place.colorHex),
      imageBytes: imageBytes,
    );
    if (!mounted || revision != _appleMarkerRevision) return;

    setState(() {
      _appleMarkerIcon = apple.BitmapDescriptor.fromBytes(markerBytes);
    });
  }

  String _markerImageId(PlaceEntity place) {
    return MarkerImage.cacheKey(
      namespace: 'selected_note_pin_${place.id}',
      iconName: place.icon,
      colorHex: place.colorHex,
      imageStoragePath: place.pinImageStoragePath,
    );
  }

  Future<Uint8List?> _pinImageBytes(String? storagePath) async {
    final path = storagePath?.trim();
    if (path == null || path.isEmpty) return null;
    try {
      return await ref.read(messageImageServiceProvider).imageBytes(path);
    } catch (error, stack) {
      debugPrint('Failed to load static mini map pin image: $error\n$stack');
      return null;
    }
  }

  apple.MapAppearanceMode _appleAppearanceModeFor(MapStyle style) {
    return switch (style) {
      MapStyle.auto => apple.MapAppearanceMode.unspecified,
      MapStyle.dark => apple.MapAppearanceMode.dark,
      MapStyle.standard || MapStyle.pop => apple.MapAppearanceMode.light,
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mapStyle = ref.watch(mapStyleProvider).effectiveForCurrentPlatform;
    final styleUrl = mapStyle.styleUrl(AppConfig.stadiaApiKey);
    final place = widget.place;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          height: 142,
          child: Stack(
            children: [
              if (_usesAppleMaps)
                apple.AppleMap(
                  key: ValueKey('apple-${place.id}-${mapStyle.name}'),
                  initialCameraPosition: apple.CameraPosition(
                    target: apple.LatLng(place.latitude, place.longitude),
                    zoom: 14,
                  ),
                  annotations: _appleMarkerIcon == null
                      ? const <apple.Annotation>{}
                      : {
                          apple.Annotation(
                            annotationId: apple.AnnotationId(
                              'selected-note-pin-${place.id}',
                            ),
                            position: apple.LatLng(
                              place.latitude,
                              place.longitude,
                            ),
                            icon: _appleMarkerIcon!,
                            infoWindow: apple.InfoWindow.noText,
                          ),
                        },
                  appearanceMode: _appleAppearanceModeFor(mapStyle),
                  compassEnabled: false,
                  rotateGesturesEnabled: false,
                  scrollGesturesEnabled: false,
                  zoomGesturesEnabled: false,
                  pitchGesturesEnabled: false,
                  myLocationEnabled: false,
                  myLocationButtonEnabled: false,
                )
              else
                maplibre.MapLibreMap(
                  key: ValueKey(styleUrl),
                  styleString: styleUrl,
                  initialCameraPosition: maplibre.CameraPosition(
                    target: maplibre.LatLng(place.latitude, place.longitude),
                    zoom: 14,
                  ),
                  compassEnabled: false,
                  rotateGesturesEnabled: false,
                  scrollGesturesEnabled: false,
                  zoomGesturesEnabled: false,
                  tiltGesturesEnabled: false,
                  doubleClickZoomEnabled: false,
                  dragEnabled: false,
                  myLocationEnabled: false,
                  logoEnabled: false,
                  onMapCreated: _onMapCreated,
                  onStyleLoadedCallback: _onStyleLoaded,
                ),
              IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(color: theme.colorScheme.outlineVariant),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const SizedBox.expand(),
                ),
              ),
              if (widget.topRightOverlay != null)
                PositionedDirectional(
                  top: 10,
                  end: 10,
                  child: widget.topRightOverlay!,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
