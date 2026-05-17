import 'package:geolocator/geolocator.dart';

class LocationService {
  Future<Position?> getCurrentPosition() async {
    try {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        final requested = await Geolocator.requestPermission();
        if (requested == LocationPermission.denied ||
            requested == LocationPermission.deniedForever) {
          return null;
        }
      }
      if (permission == LocationPermission.deniedForever) return null;

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
