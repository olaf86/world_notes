import 'package:geolocator/geolocator.dart';

import '../../../domain/entities/pin_summary_entity.dart';

/// Presentation data derived from a server-provided [pin] and live GPS.
///
/// [PinSummary.access] remains the state returned by the Cloud Function,
/// while [canOpen] is the UI's current, local distance estimate. The Cloud
/// Function remains authoritative when a note is opened.
class MapPinDisplay {
  final PinSummary pin;
  final double? distanceMeters;
  final bool canOpen;

  const MapPinDisplay({
    required this.pin,
    required this.distanceMeters,
    required this.canOpen,
  });

  /// Falls back to the server snapshot before a local position is available.
  factory MapPinDisplay.withServerAccess(PinSummary pin) =>
      MapPinDisplay(pin: pin, distanceMeters: null, canOpen: pin.canOpen);
}

/// Combines a server pin with the locally observable, distance-based state.
/// Pin discovery is deliberately throttled by [anchorPositionProvider], but
/// access affordances must react to the live GPS stream. Keeping this mapping
/// local avoids a map-pins request for every location update.
MapPinDisplay mapPinDisplay(
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
  return MapPinDisplay(
    pin: pin,
    distanceMeters: distanceMeters,
    canOpen: distanceMeters <= accessRadiusMeters,
  );
}

List<MapPinDisplay> mapPinDisplays(
  List<PinSummary> pins, {
  required Position position,
  required double accessRadiusMeters,
}) {
  return [
    for (final pin in pins)
      mapPinDisplay(
        pin,
        position: position,
        accessRadiusMeters: accessRadiusMeters,
      ),
  ];
}
