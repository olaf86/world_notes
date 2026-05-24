import 'dart:math' as math;

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

List<String> getGeohashPrefixes(
  double lat,
  double lng, {
  int precision = 6,
}) {
  final center = encodeGeohash(lat, lng, precision: precision);
  return _getNeighbors(center)..add(center);
}

List<String> _getNeighbors(String geohash) {
  final neighbors = <String>[];
  for (final dir in const [
    [1, 0], [-1, 0], [0, 1], [0, -1],
    [1, 1], [1, -1], [-1, 1], [-1, -1],
  ]) {
    final neighbor = _adjacent(geohash, dir[0], dir[1]);
    if (neighbor != null) neighbors.add(neighbor);
  }
  return neighbors;
}

String? _adjacent(String geohash, int latDir, int lngDir) {
  final bounds = _decodeBounds(geohash);
  if (bounds == null) return null;

  final centerLat = (bounds[0] + bounds[1]) / 2;
  final centerLng = (bounds[2] + bounds[3]) / 2;
  final latStep = bounds[1] - bounds[0];
  final lngStep = bounds[3] - bounds[2];

  final newLat = (centerLat + latDir * latStep).clamp(-90.0, 90.0);
  final wrappedLng = ((centerLng + lngDir * lngStep + 180) % 360) - 180;

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
        if (bitN == 1) { minLng = mid; } else { maxLng = mid; }
      } else {
        final mid = (minLat + maxLat) / 2;
        if (bitN == 1) { minLat = mid; } else { maxLat = mid; }
      }
      isEven = !isEven;
    }
  }

  return [minLat, maxLat, minLng, maxLng];
}

double haversineDistance(double lat1, double lng1, double lat2, double lng2) {
  const r = 6371.0;
  final dLat = _toRad(lat2 - lat1);
  final dLng = _toRad(lng2 - lng1);
  final a = math.pow(math.sin(dLat / 2), 2) +
      math.cos(_toRad(lat1)) * math.cos(_toRad(lat2)) *
          math.pow(math.sin(dLng / 2), 2);
  return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
}

double _toRad(double deg) => deg * math.pi / 180;
