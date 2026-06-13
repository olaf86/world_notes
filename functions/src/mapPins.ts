/* eslint-disable require-jsdoc */
import {onCall, HttpsError} from "firebase-functions/v2/https";
import {
  DocumentSnapshot,
  Timestamp,
  getFirestore,
} from "firebase-admin/firestore";

import {geohashPrefixes, geohashPrefixesInRadius} from "./geohash";
import {
  MAP_PIN_GEOHASH_PRECISION,
  MAP_PIN_FINE_SEARCH_MAX_RADIUS_KM,
  MAP_PIN_MAX_SEARCH_RADIUS_KM,
  MAP_PIN_RESULT_LIMIT,
  MAP_PIN_ZOOMED_OUT_RESULT_LIMIT,
  NOTE_DETAIL_ACCESS_RADIUS_KM,
  DISCOVERY_GEOHASH_PRECISION,
  REGION,
} from "./constants";

interface Coordinates {
  latitude: number;
  longitude: number;
}

interface ListMapPinsData {
  centerLatitude?: unknown;
  centerLongitude?: unknown;
  userLatitude?: unknown;
  userLongitude?: unknown;
  searchRadiusKm?: unknown;
}

interface ValidateNoteAccessData {
  placeId?: unknown;
  latitude?: unknown;
  longitude?: unknown;
}

interface Bucket {
  tokens: number;
  lastRefillAt: number;
}

interface FineQuery {
  discoveryGeohash: string;
  geohashes: string[];
}

const RATE_LIMIT_CAPACITY = 80;
const RATE_LIMIT_REFILL_PER_SECOND = 2;
const GEOHASH_IN_BATCH_SIZE = 10;
const buckets = new Map<string, Bucket>();

function assertCoordinatePair(
  latitude: unknown,
  longitude: unknown,
): Coordinates {
  if (
    typeof latitude !== "number" ||
    typeof longitude !== "number" ||
    !isFinite(latitude) ||
    !isFinite(longitude) ||
    latitude < -90 ||
    latitude > 90 ||
    longitude < -180 ||
    longitude > 180
  ) {
    throw new HttpsError("invalid-argument", "Invalid coordinates.");
  }
  return {latitude, longitude};
}

function consumeRateLimit(uid: string): void {
  const now = Date.now();
  const bucket = buckets.get(uid) ?? {
    tokens: RATE_LIMIT_CAPACITY,
    lastRefillAt: now,
  };
  const elapsedSeconds = Math.max(0, (now - bucket.lastRefillAt) / 1000);
  bucket.tokens = Math.min(
    RATE_LIMIT_CAPACITY,
    bucket.tokens + elapsedSeconds * RATE_LIMIT_REFILL_PER_SECOND,
  );
  bucket.lastRefillAt = now;

  if (bucket.tokens < 1) {
    buckets.set(uid, bucket);
    throw new HttpsError(
      "resource-exhausted",
      "Map exploration is being refreshed too quickly.",
    );
  }

  bucket.tokens -= 1;
  buckets.set(uid, bucket);
}

function assertSearchRadiusKm(value: unknown): number {
  if (typeof value !== "number" || !isFinite(value) || value <= 0) {
    throw new HttpsError("invalid-argument", "Invalid search radius.");
  }
  return Math.min(value, MAP_PIN_MAX_SEARCH_RADIUS_KM);
}

function toRad(value: number): number {
  return value * Math.PI / 180;
}

function distanceKm(a: Coordinates, b: Coordinates): number {
  const radiusKm = 6371.0;
  const dLat = toRad(b.latitude - a.latitude);
  const dLng = toRad(b.longitude - a.longitude);
  const h = Math.sin(dLat / 2) ** 2 +
    Math.cos(toRad(a.latitude)) *
    Math.cos(toRad(b.latitude)) *
    Math.sin(dLng / 2) ** 2;
  return radiusKm * 2 * Math.atan2(Math.sqrt(h), Math.sqrt(1 - h));
}

function isPublishedPlace(
  doc: DocumentSnapshot,
  nowMillis: number,
): boolean {
  const publishAt = doc.get("publishAt") as Timestamp | undefined;
  const expiresAt = doc.get("expiresAt") as Timestamp | undefined;
  return doc.get("isArchived") !== true &&
    publishAt != null &&
    expiresAt != null &&
    publishAt.toMillis() <= nowMillis &&
    expiresAt.toMillis() > nowMillis;
}

function placeCoordinates(doc: DocumentSnapshot): Coordinates {
  return {
    latitude: doc.get("latitude") as number,
    longitude: doc.get("longitude") as number,
  };
}

function canOpenFrom(user: Coordinates, place: Coordinates): boolean {
  return distanceKm(user, place) <= NOTE_DETAIL_ACCESS_RADIUS_KM;
}

function fineQueries(center: Coordinates, radiusKm: number): FineQuery[] {
  const geohashes = geohashPrefixesInRadius(
    center.latitude,
    center.longitude,
    MAP_PIN_GEOHASH_PRECISION,
    radiusKm,
  );
  const byDiscovery = new Map<string, string[]>();
  for (const geohash of geohashes) {
    const discovery = geohash.substring(0, DISCOVERY_GEOHASH_PRECISION);
    byDiscovery.set(
      discovery,
      [...(byDiscovery.get(discovery) ?? []), geohash],
    );
  }

  const queries: FineQuery[] = [];
  for (const [discoveryGeohash, group] of byDiscovery) {
    for (let i = 0; i < group.length; i += GEOHASH_IN_BATCH_SIZE) {
      queries.push({
        discoveryGeohash,
        geohashes: group.slice(i, i + GEOHASH_IN_BATCH_SIZE),
      });
    }
  }
  return queries;
}

export const listMapPins = onCall<ListMapPinsData>(
  {enforceAppCheck: true, region: REGION},
  async (req) => {
    const uid = req.auth?.uid;
    if (!uid) throw new HttpsError("unauthenticated", "Sign in required.");
    consumeRateLimit(uid);

    const center = assertCoordinatePair(
      req.data?.centerLatitude,
      req.data?.centerLongitude,
    );
    const user = assertCoordinatePair(
      req.data?.userLatitude,
      req.data?.userLongitude,
    );
    const searchRadiusKm = assertSearchRadiusKm(req.data?.searchRadiusKm);

    const db = getFirestore();
    const nowMillis = Date.now();
    const publishedAt = Timestamp.fromMillis(nowMillis);
    const expiresAfter = Timestamp.fromMillis(nowMillis);
    const useFineSearch =
      searchRadiusKm <= MAP_PIN_FINE_SEARCH_MAX_RADIUS_KM;
    const fineQuerySpecs = useFineSearch ?
      fineQueries(center, searchRadiusKm) :
      [];
    const coarsePrefixes = useFineSearch ?
      [] :
      geohashPrefixes(
        center.latitude,
        center.longitude,
        DISCOVERY_GEOHASH_PRECISION,
      );
    const queryCount = useFineSearch ?
      fineQuerySpecs.length :
      coarsePrefixes.length;
    const resultLimit = useFineSearch ?
      MAP_PIN_RESULT_LIMIT :
      MAP_PIN_ZOOMED_OUT_RESULT_LIMIT;
    const perQueryLimit = Math.max(
      10,
      Math.ceil(resultLimit / Math.max(queryCount, 1)),
    );
    const snapshots = useFineSearch ?
      await Promise.all(
        fineQuerySpecs.map((query) => db
          .collection("places")
          .where("geohash", "in", query.geohashes)
          .where("discoveryGeohash", "==", query.discoveryGeohash)
          .where("isArchived", "==", false)
          .where("publishAt", "<=", publishedAt)
          .where("expiresAt", ">", expiresAfter)
          .orderBy("publishAt")
          .orderBy("expiresAt")
          .limit(perQueryLimit)
          .get()),
      ) :
      await Promise.all(
        coarsePrefixes.map((prefix) => db
          .collection("places")
          .where("discoveryGeohash", "==", prefix)
          .where("isArchived", "==", false)
          .where("publishAt", "<=", publishedAt)
          .where("expiresAt", ">", expiresAfter)
          .orderBy("publishAt")
          .orderBy("expiresAt")
          .limit(perQueryLimit)
          .get()),
      );

    const seen = new Set<string>();
    const pins = [];
    for (const snap of snapshots) {
      for (const doc of snap.docs) {
        if (seen.has(doc.id) || !isPublishedPlace(doc, nowMillis)) continue;
        const coords = placeCoordinates(doc);
        seen.add(doc.id);
        const lastMessageAt = doc.get("lastMessageAt") as Timestamp | undefined;
        const createdAt = doc.get("createdAt") as Timestamp | undefined;
        const expiresAt = doc.get("expiresAt") as Timestamp;
        pins.push({
          placeId: doc.id,
          latitude: coords.latitude,
          longitude: coords.longitude,
          title: doc.get("title") as string,
          subtitle: (doc.get("subtitle") as string | undefined) ?? null,
          colorHex: doc.get("colorHex") as string,
          icon: doc.get("icon") as string,
          messageCount: (doc.get("messageCount") as number | undefined) ?? 0,
          lastActivityAtMillis:
            (lastMessageAt ?? createdAt)?.toMillis() ?? nowMillis,
          expiresAtMillis: expiresAt.toMillis(),
          isPrivate: doc.get("visibility") === "private",
          isClosed: doc.get("isOpen") !== true,
          access: canOpenFrom(user, coords) ? "openable" : "distanceLocked",
        });
      }
    }

    pins.sort((a, b) => b.lastActivityAtMillis - a.lastActivityAtMillis);
    return {pins: pins.slice(0, resultLimit)};
  },
);

export const validateNoteAccess = onCall<ValidateNoteAccessData>(
  {enforceAppCheck: true, region: REGION},
  async (req) => {
    const uid = req.auth?.uid;
    if (!uid) throw new HttpsError("unauthenticated", "Sign in required.");

    const {placeId} = req.data ?? {};
    if (typeof placeId !== "string" || placeId.length === 0) {
      throw new HttpsError("invalid-argument", "placeId is required.");
    }
    const user = assertCoordinatePair(req.data?.latitude, req.data?.longitude);

    const snap = await getFirestore().collection("places").doc(placeId).get();
    if (!snap.exists) throw new HttpsError("not-found", "Note not found.");
    const nowMillis = Date.now();
    if (!isPublishedPlace(snap, nowMillis)) {
      throw new HttpsError(
        "failed-precondition",
        "This note is not available.",
      );
    }
    if (!canOpenFrom(user, placeCoordinates(snap))) {
      throw new HttpsError(
        "permission-denied",
        "Move closer to this note to open it.",
      );
    }

    return {ok: true};
  },
);
