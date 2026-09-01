import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as google;

import '../../../core/utils/marker_image.dart';
import '../../../core/utils/place_icon.dart';
import '../../../domain/entities/pin_summary_entity.dart';
import 'marker_icon_store.dart';
import 'note_map_adapter.dart';

class GoogleMarkerIcons {
  GoogleMarkerIcons({required OnResolvePinMarkerImage onResolveMarkerImage})
    : _onResolveMarkerImage = onResolveMarkerImage;

  static const double _normalMarkerWidth = 48;
  static const double _selectedMarkerWidth = 72;

  final OnResolvePinMarkerImage _onResolveMarkerImage;
  final MarkerIconStore<google.BitmapDescriptor> _store = MarkerIconStore();

  google.BitmapDescriptor? preparedFor(String placeId) =>
      _store.preparedFor(placeId);

  google.BitmapDescriptor placeholder(PinSummary pin) =>
      google.BitmapDescriptor.defaultMarkerWithHue(
        HSVColor.fromColor(parsePlaceColor(pin.colorHex)).hue,
      );

  void retainPlaces(Iterable<PinSummary> pins) => _store.retainPlaces(pins);

  Future<void> prepareFallbacks(
    Iterable<PinSummary> pins, {
    required bool Function() isCurrent,
  }) => _store.prepare(
    pins,
    isCurrent: isCurrent,
    load: (pin) => _icon(pin, selected: false, includePhoto: false),
  );

  Future<void> preparePhotos(
    Iterable<PinSummary> pins, {
    required bool Function() isCurrent,
    required void Function() afterBatch,
  }) => _store.prepare(
    pins.where((pin) => pin.pinImageStoragePath != null),
    isCurrent: isCurrent,
    load: (pin) => _icon(pin, selected: false, includePhoto: true),
    afterBatch: afterBatch,
  );

  Future<google.BitmapDescriptor> selected(PinSummary pin) =>
      _icon(pin, selected: true, includePhoto: true);

  String _cacheKey(PinSummary pin, {String? imageStoragePath}) =>
      MarkerImage.cacheKey(
        namespace: 'google_marker',
        iconName: pin.icon,
        colorHex: pin.colorHex,
        imageStoragePath: imageStoragePath,
        variant: pin.markerVariantKey,
      );

  Future<google.BitmapDescriptor> _icon(
    PinSummary pin, {
    required bool selected,
    required bool includePhoto,
  }) async {
    final photoStoragePath = includePhoto ? pin.pinImageStoragePath : null;
    final suffix = selected ? 'selected' : 'normal';
    final fallbackCacheId = '${_cacheKey(pin)}-$suffix';
    final photoCacheId = photoStoragePath == null
        ? null
        : '${_cacheKey(pin, imageStoragePath: photoStoragePath)}-$suffix';

    final photoBytes = photoStoragePath == null
        ? null
        : await _resolveMarkerImage(pin);
    final cacheId = photoBytes == null ? fallbackCacheId : photoCacheId!;
    return _store.cached(cacheId, () async {
      final bytes = await _renderMarker(pin, photoBytes: photoBytes);
      return google.BitmapDescriptor.bytes(
        bytes,
        width: selected ? _selectedMarkerWidth : _normalMarkerWidth,
      );
    });
  }

  Future<Uint8List> _renderMarker(
    PinSummary pin, {
    Uint8List? photoBytes,
  }) async {
    try {
      return await MarkerImage.render(
        iconData: placeIconData(pin.icon),
        color: parsePlaceColor(pin.colorHex),
        imageBytes: photoBytes,
        showFollowedAuthorRing: pin.isFromFollowedAuthor,
        showUnseenDot: pin.hasUnseenMessages,
      );
    } catch (error, stack) {
      debugPrint('Failed to render Google pin marker image: $error\n$stack');
      return MarkerImage.render(
        iconData: placeIconData(pin.icon),
        color: parsePlaceColor(pin.colorHex),
        showFollowedAuthorRing: pin.isFromFollowedAuthor,
        showUnseenDot: pin.hasUnseenMessages,
      );
    }
  }

  Future<Uint8List?> _resolveMarkerImage(PinSummary pin) async {
    try {
      return await _onResolveMarkerImage(pin);
    } catch (error, stack) {
      debugPrint('Failed to load Google pin marker image: $error\n$stack');
      return null;
    }
  }
}
