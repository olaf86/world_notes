/**
 * Standard base-32 geohash encoder.
 *
 * Places are created and queried server-side by geohash prefix, so encoding
 * and neighbor traversal must stay internally consistent.
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

/**
 * Returns the encoded cell and its eight neighboring cells.
 *
 * @param {number} lat Latitude in degrees.
 * @param {number} lng Longitude in degrees.
 * @param {number} precision Number of geohash characters to produce.
 * @return {string[]} Geohash prefixes covering a 3x3 grid.
 */
export function geohashPrefixes(
  lat: number,
  lng: number,
  precision = 6,
): string[] {
  const center = encodeGeohash(lat, lng, precision);
  const hashes = new Set<string>([center]);
  for (const [latDir, lngDir] of [
    [1, 0], [-1, 0], [0, 1], [0, -1],
    [1, 1], [1, -1], [-1, 1], [-1, -1],
  ]) {
    const hash = adjacent(center, latDir, lngDir);
    if (hash != null) hashes.add(hash);
  }
  return [...hashes];
}

/**
 * Returns the geohash directly adjacent to another cell.
 *
 * @param {string} geohash Existing geohash.
 * @param {number} latDir Latitude direction (-1, 0, 1).
 * @param {number} lngDir Longitude direction (-1, 0, 1).
 * @return {string | null} Adjacent geohash, or null for invalid input.
 */
function adjacent(
  geohash: string,
  latDir: number,
  lngDir: number,
): string | null {
  const bounds = decodeBounds(geohash);
  if (bounds == null) return null;

  const centerLat = (bounds.minLat + bounds.maxLat) / 2;
  const centerLng = (bounds.minLng + bounds.maxLng) / 2;
  const latStep = bounds.maxLat - bounds.minLat;
  const lngStep = bounds.maxLng - bounds.minLng;
  const newLat = Math.max(-90, Math.min(90, centerLat + latDir * latStep));
  const wrappedLng =
    ((centerLng + lngDir * lngStep + 180) % 360 + 360) % 360 - 180;

  return encodeGeohash(newLat, wrappedLng, geohash.length);
}

/**
 * Decodes a geohash into its latitude/longitude bounds.
 *
 * @param {string} geohash Geohash to decode.
 * @return {Object|null} Bounds for the cell, or null for invalid input.
 */
function decodeBounds(geohash: string): {
  minLat: number;
  maxLat: number;
  minLng: number;
  maxLng: number;
} | null {
  let minLat = -90.0;
  let maxLat = 90.0;
  let minLng = -180.0;
  let maxLng = 180.0;
  let isEven = true;

  for (const char of geohash.split("")) {
    const index = BASE32.indexOf(char);
    if (index === -1) return null;

    for (let bits = 4; bits >= 0; bits--) {
      const bitN = (index >> bits) & 1;
      if (isEven) {
        const mid = (minLng + maxLng) / 2;
        if (bitN === 1) {
          minLng = mid;
        } else {
          maxLng = mid;
        }
      } else {
        const mid = (minLat + maxLat) / 2;
        if (bitN === 1) {
          minLat = mid;
        } else {
          maxLat = mid;
        }
      }
      isEven = !isEven;
    }
  }

  return {minLat, maxLat, minLng, maxLng};
}
