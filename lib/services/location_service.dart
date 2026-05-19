import 'package:geolocator/geolocator.dart';

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

  Future<Position?> getCurrentPosition() async {
    try {
      final permission = await ensurePermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return null;
      }

      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      ).timeout(const Duration(seconds: 10));
    } catch (_) {
      // Covers TimeoutException, PermissionDefinitionsNotFoundException, etc.
      return null;
    }
  }

  Stream<Position> watchPosition() async* {
    // Ensure permission is granted before opening the stream.
    final pos = await getCurrentPosition();
    if (pos == null) return; // Permission denied — emit nothing.

    yield pos; // Emit the initial position immediately.
    yield* Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 20,
      ),
    );
  }
}
