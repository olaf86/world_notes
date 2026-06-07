import {onCall, HttpsError} from "firebase-functions/v2/https";
import {
  getFirestore,
  FieldValue,
  Timestamp,
} from "firebase-admin/firestore";

import {encodeGeohash} from "./geohash";
import {
  DISCOVERY_GEOHASH_PRECISION,
  DISCOVERY_GRANT_MAX_PER_WINDOW,
  DISCOVERY_GRANT_MIN_INTERVAL_SECONDS,
  DISCOVERY_GRANT_RADIUS_KM,
  DISCOVERY_GRANT_TTL_MINUTES,
  DISCOVERY_GRANT_WINDOW_MINUTES,
  REGION,
} from "./constants";

interface EnsureDiscoveryGrantData {
  latitude?: unknown;
  longitude?: unknown;
}

interface DiscoveryGrantResponse {
  discoveryGeohashes: string[];
  expiresAtMillis: number;
  serverNowMillis: number;
  reused: boolean;
}

/**
 * Converts degrees to radians.
 *
 * @param {number} value Angle in degrees.
 * @return {number} Angle in radians.
 */
function toRad(value: number): number {
  return value * Math.PI / 180;
}

/**
 * Returns an approximate point offset north/east from a start point.
 *
 * @param {number} latitude Start latitude.
 * @param {number} longitude Start longitude.
 * @param {number} northKm Kilometres north, negative for south.
 * @param {number} eastKm Kilometres east, negative for west.
 * @return {{latitude: number, longitude: number}} Offset point.
 */
function pointOffset(
  latitude: number,
  longitude: number,
  northKm: number,
  eastKm: number,
): {latitude: number; longitude: number} {
  // Around Earth, 1 degree of latitude is about 111.32 km. Longitude degrees
  // shrink by cos(latitude), so east/west offsets divide by that factor.
  const lat = latitude + (northKm / 111.32);
  const cosLat = Math.max(0.1, Math.abs(Math.cos(toRad(latitude))));
  const lng = longitude + (eastKm / (111.32 * cosLat));
  const wrappedLng = ((lng + 180) % 360 + 360) % 360 - 180;
  return {
    latitude: Math.max(-90, Math.min(90, lat)),
    longitude: wrappedLng,
  };
}

/**
 * Coarse geohashes covering the discovery radius around a point.
 *
 * This intentionally approximates coverage instead of doing exact geometry:
 * sample a small square grid around the user's location, encode each sample at
 * the coarse precision, then deduplicate. Firestore Rules later allow queries
 * only for places whose stored discoveryGeohash is in this generated set.
 *
 * @param {number} latitude Centre latitude.
 * @param {number} longitude Centre longitude.
 * @return {string[]} Sorted unique coarse geohashes.
 */
function discoveryGeohashesFor(
  latitude: number,
  longitude: number,
): string[] {
  const hashes = new Set<string>();
  const stepKm = DISCOVERY_GRANT_RADIUS_KM / 2;

  for (
    let northKm = -DISCOVERY_GRANT_RADIUS_KM;
    northKm <= DISCOVERY_GRANT_RADIUS_KM;
    northKm += stepKm
  ) {
    for (
      let eastKm = -DISCOVERY_GRANT_RADIUS_KM;
      eastKm <= DISCOVERY_GRANT_RADIUS_KM;
      eastKm += stepKm
    ) {
      const point = pointOffset(latitude, longitude, northKm, eastKm);
      hashes.add(
        encodeGeohash(
          point.latitude,
          point.longitude,
          DISCOVERY_GEOHASH_PRECISION,
        ),
      );
    }
  }

  return [...hashes].sort();
}

/**
 * Issues (or reuses) a short-lived coarse geohash discovery grant.
 *
 * The grant keeps nearby Firestore streams direct and real-time while
 * preventing a signed-in client from freely querying arbitrary world regions.
 * New grant creation is rate-limited in a transaction; valid grants are reused
 * so normal refreshes do not burn the user's hourly grant window.
 */
export const ensureDiscoveryGrant = onCall<EnsureDiscoveryGrantData>(
  {enforceAppCheck: true, region: REGION},
  async (req): Promise<DiscoveryGrantResponse> => {
    const uid = req.auth?.uid;
    if (!uid) throw new HttpsError("unauthenticated", "Sign in required.");

    const {latitude, longitude} = req.data ?? {};
    if (
      typeof latitude !== "number" ||
      typeof longitude !== "number" ||
      latitude < -90 ||
      latitude > 90 ||
      longitude < -180 ||
      longitude > 180
    ) {
      throw new HttpsError("invalid-argument", "Invalid coordinates.");
    }

    const db = getFirestore();
    const grantRef = db
      .collection("users")
      .doc(uid)
      .collection("discoveryGrants")
      .doc("current");
    const limitRef = db
      .collection("users")
      .doc(uid)
      .collection("limits")
      .doc("discoveryGrant");

    return db.runTransaction(async (tx) => {
      const nowMillis = Date.now();
      const currentDiscoveryGeohash = encodeGeohash(
        latitude,
        longitude,
        DISCOVERY_GEOHASH_PRECISION,
      );
      const grantSnap = await tx.get(grantRef);
      const limitSnap = await tx.get(limitRef);

      if (grantSnap.exists) {
        const expiresAt = grantSnap.get("expiresAt") as Timestamp | undefined;
        const hashes =
          (grantSnap.get("discoveryGeohashes") as string[] | undefined) ?? [];
        const isStillValid = expiresAt && expiresAt.toMillis() > nowMillis;
        const isCovered = hashes.includes(currentDiscoveryGeohash);

        if (isStillValid && isCovered) {
          return {
            discoveryGeohashes: hashes,
            expiresAtMillis: expiresAt.toMillis(),
            serverNowMillis: nowMillis,
            reused: true,
          };
        }
      }

      const lastIssuedAt = limitSnap.exists ?
        (limitSnap.get("lastIssuedAt") as Timestamp | undefined) :
        undefined;
      const minIntervalMs = DISCOVERY_GRANT_MIN_INTERVAL_SECONDS * 1000;
      if (lastIssuedAt && nowMillis - lastIssuedAt.toMillis() < minIntervalMs) {
        throw new HttpsError(
          "resource-exhausted",
          "Discovery was refreshed too recently. Please try again shortly.",
        );
      }

      const windowMs = DISCOVERY_GRANT_WINDOW_MINUTES * 60 * 1000;
      const previousWindowStart = limitSnap.exists ?
        (limitSnap.get("windowStartAt") as Timestamp | undefined) :
        undefined;
      const sameWindow = previousWindowStart != null &&
        nowMillis - previousWindowStart.toMillis() < windowMs;
      const issuedCount = sameWindow ?
        ((limitSnap.get("issuedCount") as number | undefined) ?? 0) :
        0;

      if (issuedCount >= DISCOVERY_GRANT_MAX_PER_WINDOW) {
        throw new HttpsError(
          "resource-exhausted",
          "Discovery refresh limit reached. Please try again later.",
        );
      }

      const discoveryGeohashes = discoveryGeohashesFor(latitude, longitude);
      const expiresAtMillis =
        nowMillis + DISCOVERY_GRANT_TTL_MINUTES * 60 * 1000;

      tx.set(grantRef, {
        discoveryGeohashes,
        centerLatitude: latitude,
        centerLongitude: longitude,
        radiusKm: DISCOVERY_GRANT_RADIUS_KM,
        precision: DISCOVERY_GEOHASH_PRECISION,
        issuedAt: Timestamp.fromMillis(nowMillis),
        expiresAt: Timestamp.fromMillis(expiresAtMillis),
      });

      tx.set(
        limitRef,
        {
          windowStartAt: sameWindow ?
            previousWindowStart :
            Timestamp.fromMillis(nowMillis),
          issuedCount: sameWindow ? FieldValue.increment(1) : 1,
          lastIssuedAt: Timestamp.fromMillis(nowMillis),
        },
        {merge: true},
      );

      return {
        discoveryGeohashes,
        expiresAtMillis,
        serverNowMillis: nowMillis,
        reused: false,
      };
    });
  },
);
