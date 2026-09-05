import 'dart:typed_data';

import 'package:apple_maps_flutter/apple_maps_flutter.dart' as apple;
import 'package:flutter/material.dart';

import '../../../core/utils/marker_image.dart';
import '../../../core/utils/place_icon.dart';
import '../../../domain/entities/pin_summary_entity.dart';
import 'marker_icon_store.dart';
import 'note_map_adapter.dart';

class AppleMarkerIcons {
  AppleMarkerIcons({required OnResolvePinMarkerImage onResolveMarkerImage})
    : _onResolveMarkerImage = onResolveMarkerImage;

  final OnResolvePinMarkerImage _onResolveMarkerImage;
  final MarkerIconStore<apple.BitmapDescriptor> _store = MarkerIconStore();

  apple.BitmapDescriptor? preparedFor(String placeId) =>
      _store.preparedFor(placeId);

  apple.BitmapDescriptor placeholder(PinSummary pin) =>
      apple.BitmapDescriptor.defaultAnnotationWithHue(
        HSVColor.fromColor(parsePlaceColor(pin.colorHex)).hue,
      );

  void retainPlaces(Iterable<PinSummary> pins) => _store.retainPlaces(pins);

  Future<void> prepare(
    Iterable<PinSummary> pins, {
    required bool Function() isCurrent,
    required void Function() afterBatch,
  }) => _store.prepare(
    pins,
    isCurrent: isCurrent,
    load: _icon,
    afterBatch: afterBatch,
  );

  String _cacheKey(PinSummary pin, {String? imageStoragePath}) =>
      MarkerImage.cacheKey(
        namespace: 'marker',
        iconName: pin.icon,
        colorHex: pin.colorHex,
        imageStoragePath: imageStoragePath,
        variant: pin.markerVariantKey,
      );

  Future<apple.BitmapDescriptor> _icon(PinSummary pin) async {
    final fallbackId = _cacheKey(pin);
    final photoStoragePath = pin.pinImageStoragePath;
    final photoId = photoStoragePath == null
        ? null
        : _cacheKey(pin, imageStoragePath: photoStoragePath);

    final photoBytes = photoStoragePath == null
        ? null
        : await _resolveMarkerImage(pin);
    if (photoBytes != null) {
      try {
        return _store.cached(photoId!, () async {
          final bytes = await MarkerImage.render(
            iconData: placeIconData(pin.icon),
            color: parsePlaceColor(pin.colorHex),
            imageBytes: photoBytes,
            showFollowedAuthorRing: pin.isFromFollowedAuthor,
            showUnseenDot: pin.hasUnseenMessages,
          );
          return apple.BitmapDescriptor.fromBytes(bytes);
        });
      } catch (error, stack) {
        debugPrint('Failed to render Apple pin marker image: $error\n$stack');
      }
    }

    return _store.cached(fallbackId, () async {
      final bytes = await MarkerImage.render(
        iconData: placeIconData(pin.icon),
        color: parsePlaceColor(pin.colorHex),
        showFollowedAuthorRing: pin.isFromFollowedAuthor,
        showUnseenDot: pin.hasUnseenMessages,
      );
      return apple.BitmapDescriptor.fromBytes(bytes);
    });
  }

  Future<Uint8List?> _resolveMarkerImage(PinSummary pin) async {
    try {
      return await _onResolveMarkerImage(pin);
    } catch (error, stack) {
      debugPrint('Failed to load Apple pin marker image: $error\n$stack');
      return null;
    }
  }
}
