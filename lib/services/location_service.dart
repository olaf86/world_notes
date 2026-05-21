import 'package:geolocator/geolocator.dart';

class LocationPermissionDeniedException implements Exception {
  final bool permanentlyDenied;
  const LocationPermissionDeniedException({this.permanentlyDenied = false});

  @override
  String toString() => 'LocationPermissionDeniedException('
      'permanentlyDenied: $permanentlyDenied)';
}

class LocationService {
  /// Checks the current permission and requests it if not yet determined.
  /// Returns the final [LocationPermission] after any request dialog.
  Future<LocationPermission> ensurePermission() async {
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    return permission;
  }

  /// Live position stream. Yields the cached last-known position first (if
  /// available) so callers can render instantly, then continues with live
  /// GPS updates. Throws [LocationPermissionDeniedException] when permission
  /// is denied so [StreamProvider]s can surface the denial as an error state.
  Stream<Position> watchPosition() async* {
    final permission = await ensurePermission();
    if (permission == LocationPermission.denied) {
      throw const LocationPermissionDeniedException();
    }
    if (permission == LocationPermission.deniedForever) {
      throw const LocationPermissionDeniedException(permanentlyDenied: true);
    }

    final lastKnown = await Geolocator.getLastKnownPosition();
    if (lastKnown != null) yield lastKnown;

    yield* Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 20,
      ),
    );
  }
}
