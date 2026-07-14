import 'package:geolocator/geolocator.dart';

import '../../../domain/entities/pin_summary_entity.dart';

/// Applies the locally observable, distance-based part of a pin's access
/// state. The Cloud Function remains the authority when a note is opened.
///
/// Pin discovery is deliberately throttled by [anchorPositionProvider], but
/// access affordances must react to the live GPS stream. Keeping this mapping
/// local avoids a map-pins request for every location update.
PinSummary pinWithLiveAccess(
  PinSummary pin, {
  required Position position,
  required double accessRadiusMeters,
}) {
  final distanceMeters = Geolocator.distanceBetween(
    position.latitude,
    position.longitude,
    pin.latitude,
    pin.longitude,
  );
  final access = distanceMeters <= accessRadiusMeters
      ? PinAccess.openable
      : PinAccess.distanceLocked;
  return pin.access == access ? pin : pin.copyWith(access: access);
}

List<PinSummary> pinsWithLiveAccess(
  List<PinSummary> pins, {
  required Position position,
  required double accessRadiusMeters,
}) {
  return [
    for (final pin in pins)
      pinWithLiveAccess(
        pin,
        position: position,
        accessRadiusMeters: accessRadiusMeters,
      ),
  ];
}
