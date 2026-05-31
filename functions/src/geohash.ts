/**
 * Standard base-32 geohash encoder.
 *
 * This is a direct port of the Dart `encodeGeohash` in
 * lib/core/utils/geohash_util.dart. It MUST stay byte-for-byte compatible:
 * places are created here (server) but queried on the client by geohash
 * prefix, so a divergent algorithm would break proximity search.
 */
const BASE32 = "0123456789bcdefghjkmnpqrstuvwxyz";

/**
 * Encodes a latitude/longitude into a base-32 geohash string.
 *
 * @param {number} lat Latitude in degrees.
 * @param {number} lng Longitude in degrees.
 * @param {number} precision Number of geohash characters to produce.
 * @return {string} The geohash of the given precision.
 */
export function encodeGeohash(
  lat: number,
  lng: number,
  precision = 6,
): string {
  let minLat = -90.0;
  let maxLat = 90.0;
  let minLng = -180.0;
  let maxLng = 180.0;

  let hash = "";
  let bits = 0;
  let hashValue = 0;
  let isEven = true;

  while (hash.length < precision) {
    const mid = isEven ? (minLng + maxLng) / 2 : (minLat + maxLat) / 2;
    const value = isEven ? lng : lat;

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

    if (bits === 5) {
      hash += BASE32[hashValue];
      bits = 0;
      hashValue = 0;
    }
  }

  return hash;
}
