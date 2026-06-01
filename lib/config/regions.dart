import 'package:geolocator/geolocator.dart';

/// A Cloud Functions region the app can target.
class AppRegion {
  /// Firebase region id, e.g. 'asia-northeast1'.
  final String id;

  /// User-facing label shown in settings.
  final String label;

  /// Representative coordinates, used to pick the nearest region to the user.
  final double latitude;
  final double longitude;

  /// Whether Cloud Functions are actually deployed in this region. Only
  /// available regions may be selected — flip this to true ONLY after the
  /// functions are deployed there, otherwise callable lookups will fail.
  final bool available;

  const AppRegion({
    required this.id,
    required this.label,
    required this.latitude,
    required this.longitude,
    this.available = false,
  });
}

/// Region catalogue + resolution helpers.
///
/// Single source of truth for which Cloud Functions region the client targets.
/// Aligned with the multi-region DB strategy (asia / us / europe). Today only
/// Tokyo is deployed; adding a region later is a one-line `available: true`
/// flip here plus deploying the functions there.
class Regions {
  Regions._();

  /// Fallback when there is no override and no usable location.
  static const String defaultId = 'asia-northeast1';

  static const List<AppRegion> all = [
    AppRegion(
      id: 'asia-northeast1',
      label: 'Asia (Tokyo)',
      latitude: 35.6812,
      longitude: 139.7671,
      available: true,
    ),
    AppRegion(
      id: 'us-central1',
      label: 'Americas (US Central)',
      latitude: 41.2619,
      longitude: -95.8608,
    ),
    AppRegion(
      id: 'europe-west1',
      label: 'Europe (Belgium)',
      latitude: 50.4501,
      longitude: 4.3517,
    ),
  ];

  /// Regions a user may actually be routed to (functions deployed).
  static List<AppRegion> get available =>
      all.where((r) => r.available).toList();

  static AppRegion? byId(String id) {
    for (final r in all) {
      if (r.id == id) return r;
    }
    return null;
  }

  /// Id of the nearest available region to the given coordinates, or
  /// [defaultId] if none can be computed.
  static String nearestAvailableId(double latitude, double longitude) {
    final candidates = available;
    if (candidates.isEmpty) return defaultId;
    var best = candidates.first;
    var bestDistance = double.infinity;
    for (final r in candidates) {
      final d = Geolocator.distanceBetween(
        latitude,
        longitude,
        r.latitude,
        r.longitude,
      );
      if (d < bestDistance) {
        bestDistance = d;
        best = r;
      }
    }
    return best.id;
  }
}
