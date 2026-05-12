// Geohash encoding for Firestore proximity queries
// Base32 character set used by geohash
const _base32 = '0123456789bcdefghjkmnpqrstuvwxyz';

String encodeGeohash(double lat, double lng, {int precision = 5}) {
  var minLat = -90.0;
  var maxLat = 90.0;
  var minLng = -180.0;
  var maxLng = 180.0;

  final buffer = StringBuffer();
  var bits = 0;
  var hashValue = 0;
  var isEven = true;

  while (buffer.length < precision) {
    final mid = isEven ? (minLng + maxLng) / 2 : (minLat + maxLat) / 2;
    final value = isEven ? lng : lat;

    if (value >= mid) {
      hashValue = (hashValue << 1) + 1;
      if (isEven) {
        minLng = mid;
      } else {
        minLat = mid;
      }
    } else {
      hashValue = hashValue << 1;
      if (isEven) {
        maxLng = mid;
      } else {
        maxLat = mid;
      }
    }

    isEven = !isEven;
    bits++;

    if (bits == 5) {
      buffer.write(_base32[hashValue]);
      bits = 0;
      hashValue = 0;
    }
  }

  return buffer.toString();
}

// Returns geohash prefixes covering a bounding box for proximity search
List<String> getGeohashPrefixes(
  double lat,
  double lng,
  double radiusKm, {
  int precision = 5,
}) {
  final center = encodeGeohash(lat, lng, precision: precision);
  // Neighbors covering the search area (simplified: use center + 8 neighbors)
  return _getNeighbors(center)..add(center);
}

List<String> _getNeighbors(String geohash) {
  final neighbors = <String>[];
  final directions = [
    [1, 0],
    [-1, 0],
    [0, 1],
    [0, -1],
    [1, 1],
    [1, -1],
    [-1, 1],
    [-1, -1],
  ];

  for (final dir in directions) {
    final neighbor = _adjacent(geohash, dir[0], dir[1]);
    if (neighbor != null) neighbors.add(neighbor);
  }
  return neighbors;
}

String? _adjacent(String geohash, int latDir, int lngDir) {
  // Decode to lat/lng, offset slightly, re-encode
  final bounds = _decodeBounds(geohash);
  if (bounds == null) return null;

  final centerLat = (bounds[0] + bounds[1]) / 2;
  final centerLng = (bounds[2] + bounds[3]) / 2;

  // Step size for one geohash cell at this precision
  final latStep = (bounds[1] - bounds[0]);
  final lngStep = (bounds[3] - bounds[2]);

  final newLat = (centerLat + latDir * latStep).clamp(-90.0, 90.0);
  final newLng = (centerLng + lngDir * lngStep);
  final wrappedLng = ((newLng + 180) % 360) - 180;

  return encodeGeohash(newLat, wrappedLng, precision: geohash.length);
}

List<double>? _decodeBounds(String geohash) {
  var minLat = -90.0;
  var maxLat = 90.0;
  var minLng = -180.0;
  var maxLng = 180.0;
  var isEven = true;

  for (final char in geohash.split('')) {
    final index = _base32.indexOf(char);
    if (index == -1) return null;

    for (var bits = 4; bits >= 0; bits--) {
      final bitN = (index >> bits) & 1;
      if (isEven) {
        final mid = (minLng + maxLng) / 2;
        if (bitN == 1) {
          minLng = mid;
        } else {
          maxLng = mid;
        }
      } else {
        final mid = (minLat + maxLat) / 2;
        if (bitN == 1) {
          minLat = mid;
        } else {
          maxLat = mid;
        }
      }
      isEven = !isEven;
    }
  }

  return [minLat, maxLat, minLng, maxLng];
}

double haversineDistance(double lat1, double lng1, double lat2, double lng2) {
  const r = 6371.0; // Earth radius km
  final dLat = _toRad(lat2 - lat1);
  final dLng = _toRad(lng2 - lng1);
  final a = _sin2(dLat / 2) +
      _cos(_toRad(lat1)) * _cos(_toRad(lat2)) * _sin2(dLng / 2);
  final c = 2 * _atan2(_sqrt(a), _sqrt(1 - a));
  return r * c;
}

double _toRad(double deg) => deg * 3.141592653589793 / 180;
double _sin2(double x) => _sin(x) * _sin(x);

double _sin(double x) {
  // Taylor series approximation
  return x -
      (x * x * x) / 6 +
      (x * x * x * x * x) / 120 -
      (x * x * x * x * x * x * x) / 5040;
}

double _cos(double x) {
  return 1 -
      (x * x) / 2 +
      (x * x * x * x) / 24 -
      (x * x * x * x * x * x) / 720;
}

double _sqrt(double x) => x <= 0 ? 0 : x < 1 ? x : _sqrtNewton(x, x / 2);
double _sqrtNewton(double x, double g) {
  final ng = (g + x / g) / 2;
  return (ng - g).abs() < 1e-10 ? ng : _sqrtNewton(x, ng);
}

double _atan2(double y, double x) {
  if (x == 0) return y > 0 ? 1.5707963 : -1.5707963;
  final r = y / x;
  final base = r / (1 + 0.28125 * r * r);
  return x > 0 ? base : (y >= 0 ? base + 3.14159265 : base - 3.14159265);
}
