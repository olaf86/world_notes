import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as maplibre;

import '../../../config/app_config.dart';
import '../../../core/utils/marker_image.dart';
import '../../../core/utils/place_icon.dart';
import '../../../domain/entities/place_entity.dart';
import '../../providers/providers.dart';

class StaticNoteMiniMap extends ConsumerStatefulWidget {
  final PlaceEntity place;

  const StaticNoteMiniMap({super.key, required this.place});

  @override
  ConsumerState<StaticNoteMiniMap> createState() => _StaticNoteMiniMapState();
}

class _StaticNoteMiniMapState extends ConsumerState<StaticNoteMiniMap> {
  static const double _markerIconSize = 1.3;

  maplibre.MapLibreMapController? _map;
  bool _styleLoaded = false;

  @override
  void didUpdateWidget(StaticNoteMiniMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.place.latitude != widget.place.latitude ||
        oldWidget.place.longitude != widget.place.longitude ||
        oldWidget.place.colorHex != widget.place.colorHex ||
        oldWidget.place.icon != widget.place.icon) {
      _renderMarker();
    }
  }

  void _onMapCreated(maplibre.MapLibreMapController controller) {
    _map = controller;
  }

  Future<void> _onStyleLoaded() async {
    _styleLoaded = true;
    await _renderMarker();
  }

  Future<void> _renderMarker() async {
    final map = _map;
    if (!_styleLoaded || map == null) return;

    final place = widget.place;
    final color = parsePlaceColor(place.colorHex);
    final imageName = 'selected-note-pin-${place.id}';
    final markerBytes = await MarkerImage.render(
      iconData: placeIconData(place.icon),
      color: color,
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mapStyle = ref.watch(mapStyleProvider);
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
            ],
          ),
        ),
      ),
    );
  }
}
