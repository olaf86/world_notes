/* eslint-disable require-jsdoc */
import {onCall, HttpsError} from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";
import {
  DocumentSnapshot,
  FieldPath,
  Firestore,
  QuerySnapshot,
  Timestamp,
  getFirestore,
} from "firebase-admin/firestore";

import {
  encodeGeohash,
  geohashPrefixes,
  geohashPrefixesInRadius,
} from "./geohash";
import {
  MAP_PIN_GEOHASH_PRECISION,
  MAP_PIN_FINE_SEARCH_MAX_RADIUS_KM,
  MAP_PIN_MID_GEOHASH_PRECISION,
  MAP_PIN_MID_SEARCH_MAX_RADIUS_KM,
  MAP_PIN_MAX_SEARCH_RADIUS_KM,
  MAP_PIN_RESULT_LIMIT,
  MAP_PIN_ZOOMED_OUT_RESULT_LIMIT,
  NOTE_DETAIL_ACCESS_RADIUS_KM,
  PRO_NOTE_DETAIL_ACCESS_RADIUS_KM,
  DISCOVERY_GEOHASH_PRECISION,
  REGION,
} from "./constants";
import {
  findUserIdsWithBlockRelationshipToViewer,
  hasUserBlockBetween,
} from "./userBlocks";

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

interface PrefixQuery {
  fieldPath: string;
  geohashes: string[];
}

type MarkerFlag = "followedAuthorNew" | "unseenMessages";

interface PinResult {
  placeId: string;
  latitude: number;
  longitude: number;
  title: string;
  subtitle: string | null;
  colorHex: string;
  themeId: string;
  icon: string;
  pinImageStoragePath: string | null;
  creatorName: string;
  creatorPhotoUrl: string | null;
  creatorPhotoVersion: number;
  messageCount: number;
  likeCount: number;
  visitorCount: number;
  createdAtMillis: number;
  lastActivityAtMillis: number;
  expiresAtMillis: number;
  isPrivate: boolean;
  isClosed: boolean;
  footprintEnabled: boolean;
  access: "openable" | "distanceLocked";
  markerFlags: MarkerFlag[];
}

interface PinCandidate extends PinResult {
  creatorUid: string;
  publishAtMillis: number;
}

const RATE_LIMIT_CAPACITY = 80;
const RATE_LIMIT_REFILL_PER_SECOND = 2;
const GEOHASH_IN_BATCH_SIZE = 10;
const VIEWER_STATE_QUERY_BATCH_SIZE = 10;
// Refill several pins per request to avoid one getAll round trip per vacancy.
const BLOCK_LOOKUP_REFILL_PIN_COUNT = 20;
const FOLLOWED_NOTE_NEW_WINDOW_MILLIS = 7 * 24 * 60 * 60 * 1000;
// Keep the pins a user just saw around zoom 14 visible when they zoom out.
const ZOOMED_OUT_LOCAL_RADIUS_KM = 3;
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
    doc.get("isModerationHidden") === false &&
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

async function noteAccessRadiusKmForUser(
  db: Firestore,
  uid: string,
): Promise<number> {
  const userSnap = await db.collection("users").doc(uid).get();
  return userSnap.get("isPremium") === true ?
    PRO_NOTE_DETAIL_ACCESS_RADIUS_KM :
    NOTE_DETAIL_ACCESS_RADIUS_KM;
}

function canOpenFrom(
  user: Coordinates,
  place: Coordinates,
  radiusKm: number,
): boolean {
  return distanceKm(user, place) <= radiusKm;
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

function prefixQuery(center: Coordinates, radiusKm: number): PrefixQuery {
  if (radiusKm > MAP_PIN_MID_SEARCH_MAX_RADIUS_KM) {
    return {
      fieldPath: "discoveryGeohash",
      geohashes: [
        encodeGeohash(
          center.latitude,
          center.longitude,
          DISCOVERY_GEOHASH_PRECISION,
        ),
      ],
    };
  }

  return {
    fieldPath: "mapGeohashMid",
    geohashes: geohashPrefixes(
      center.latitude,
      center.longitude,
      MAP_PIN_MID_GEOHASH_PRECISION,
    ),
  };
}

function pinFromDoc(
  doc: DocumentSnapshot,
  user: Coordinates,
  noteAccessRadiusKm: number,
  nowMillis: number,
): PinCandidate {
  const coords = placeCoordinates(doc);
  const lastMessageAt = doc.get("lastMessageAt") as Timestamp | undefined;
  const createdAt = doc.get("createdAt") as Timestamp | undefined;
  const publishAt = doc.get("publishAt") as Timestamp;
  const expiresAt = doc.get("expiresAt") as Timestamp;
  const creatorName = doc.get("creatorName") as string;
  const creatorPhotoUrl = doc.get("creatorPhotoUrl") as string | null;
  const creatorPhotoVersion = doc.get("creatorPhotoVersion") as number;
  const storedPinImageStoragePath = doc.get("pinImageStoragePath");
  return {
    placeId: doc.id,
    latitude: coords.latitude,
    longitude: coords.longitude,
    title: doc.get("title") as string,
    subtitle: (doc.get("subtitle") as string | undefined) ?? null,
    colorHex: doc.get("colorHex") as string,
    themeId: doc.get("themeId") as string,
    icon: doc.get("icon") as string,
    pinImageStoragePath:
      typeof storedPinImageStoragePath === "string" &&
        storedPinImageStoragePath.trim().length > 0 ?
        storedPinImageStoragePath.trim() :
        null,
    creatorName,
    creatorPhotoUrl,
    creatorPhotoVersion,
    messageCount: (doc.get("messageCount") as number | undefined) ?? 0,
    likeCount: doc.get("likeCount") as number,
    visitorCount: (doc.get("visitorCount") as number | undefined) ?? 0,
    createdAtMillis: createdAt?.toMillis() ?? nowMillis,
    lastActivityAtMillis:
      (lastMessageAt ?? createdAt)?.toMillis() ?? nowMillis,
    expiresAtMillis: expiresAt.toMillis(),
    isPrivate: doc.get("visibility") === "private",
    isClosed: doc.get("isOpen") !== true,
    footprintEnabled: doc.get("footprintEnabled") !== false,
    access: canOpenFrom(user, coords, noteAccessRadiusKm) ?
      "openable" :
      "distanceLocked",
    markerFlags: [],
    creatorUid: doc.get("createdByUserId") as string,
    publishAtMillis: publishAt.toMillis(),
  };
}

function collectPins(
  snapshots: QuerySnapshot[],
  user: Coordinates,
  noteAccessRadiusKm: number,
  nowMillis: number,
  seen: Set<string>,
): PinCandidate[] {
  const pins: PinCandidate[] = [];
  for (const snap of snapshots) {
    for (const doc of snap.docs) {
      if (seen.has(doc.id) || !isPublishedPlace(doc, nowMillis)) continue;
      seen.add(doc.id);
      pins.push(pinFromDoc(doc, user, noteAccessRadiusKm, nowMillis));
    }
  }
  pins.sort((a, b) => b.lastActivityAtMillis - a.lastActivityAtMillis);
  return pins;
}

function chunksOf<T>(values: T[], size: number): T[][] {
  const chunks: T[][] = [];
  for (let index = 0; index < values.length; index += size) {
    chunks.push(values.slice(index, index + size));
  }
  return chunks;
}

/**
 * Takes the first visible pins while resolving block relationships in stages.
 *
 * The first lookup covers only the result window. Later candidates are checked
 * only when blocked pins leave vacancies. Results are cached by creator so a
 * creator appearing in more than one batch is never read from Firestore twice.
 *
 * @param {T[]} pins Ordered map pin candidates.
 * @param {number} resultLimit Maximum visible pins to return.
 * @param {Function} findBlockedCreatorUids Resolves one unchecked user batch.
 * @return {Promise<T[]>} Ordered pins with blocked creators removed.
 */
export async function takeVisibleMapPins<
  T extends {creatorUid: string},
>(
  pins: T[],
  resultLimit: number,
  findBlockedCreatorUids: (
    candidateUids: string[],
  ) => Promise<Set<string>>,
): Promise<T[]> {
  const visiblePins: T[] = [];
  const blockRelationshipByCreatorUid = new Map<string, boolean>();
  let cursor = 0;

  while (cursor < pins.length && visiblePins.length < resultLimit) {
    const missingPinCount = resultLimit - visiblePins.length;
    const batchSize = cursor === 0 ?
      missingPinCount :
      Math.max(missingPinCount, BLOCK_LOOKUP_REFILL_PIN_COUNT);
    const batch = pins.slice(cursor, cursor + batchSize);
    cursor += batch.length;

    const uncheckedCreatorUids = [...new Set(
      batch
        .map((pin) => pin.creatorUid)
        .filter((creatorUid) =>
          !blockRelationshipByCreatorUid.has(creatorUid)
        ),
    )];
    if (uncheckedCreatorUids.length > 0) {
      const blockedCreatorUids =
        await findBlockedCreatorUids(uncheckedCreatorUids);
      for (const creatorUid of uncheckedCreatorUids) {
        blockRelationshipByCreatorUid.set(
          creatorUid,
          blockedCreatorUids.has(creatorUid),
        );
      }
    }

    for (const pin of batch) {
      if (blockRelationshipByCreatorUid.get(pin.creatorUid) !== true) {
        visiblePins.push(pin);
        if (visiblePins.length === resultLimit) break;
      }
    }
  }

  return visiblePins;
}

async function addMarkerFlagsToPins(
  db: Firestore,
  uid: string,
  pins: PinCandidate[],
  nowMillis: number,
): Promise<PinResult[]> {
  if (pins.length === 0) return [];

  const placeIds = [...new Set(pins.map((pin) => pin.placeId))];
  const followedCreatorCandidateUids = [...new Set(
    pins
      .map((pin) => pin.creatorUid)
      .filter((creatorUid) => creatorUid.length > 0 && creatorUid !== uid),
  )];
  const followedCreatorUidChunks = chunksOf(
    followedCreatorCandidateUids,
    VIEWER_STATE_QUERY_BATCH_SIZE,
  );
  const noteStatesRef = db
    .collection("users")
    .doc(uid)
    .collection("noteStates");

  const [noteStateSnapshots, followSnapshots] = await Promise.all([
    Promise.all(
      chunksOf(placeIds, VIEWER_STATE_QUERY_BATCH_SIZE).map((placeIdChunk) =>
        noteStatesRef
          .where(FieldPath.documentId(), "in", placeIdChunk)
          .get(),
      ),
    ),
    Promise.all(
      followedCreatorUidChunks.map((creatorUidChunk) =>
        db
          .collection("socialEdges")
          .where("followerUid", "==", uid)
          .where("followeeUid", "in", creatorUidChunk)
          .get(),
      ),
    ),
  ]);

  const noteStateByPlaceId = new Map<string, DocumentSnapshot>();
  for (const snapshot of noteStateSnapshots) {
    for (const doc of snapshot.docs) noteStateByPlaceId.set(doc.id, doc);
  }
  const followedCreatorUids = new Set<string>();
  for (const snapshot of followSnapshots) {
    for (const doc of snapshot.docs) {
      const followeeUid = doc.get("followeeUid");
      if (typeof followeeUid === "string") followedCreatorUids.add(followeeUid);
    }
  }
  return pins.map((pin) => {
    const noteState = noteStateByPlaceId.get(pin.placeId);
    const lastSeenMessageCount =
      (noteState?.get("lastSeenMessageCount") as number | undefined) ?? 0;
    const discoverySeenAt =
      noteState?.get("discoverySeenAt") as Timestamp | undefined;
    const hasUnseenMessages =
      noteState != null && pin.messageCount > lastSeenMessageCount;
    const followedAuthorNew =
      !pin.isPrivate &&
      followedCreatorUids.has(pin.creatorUid) &&
      pin.publishAtMillis >= nowMillis - FOLLOWED_NOTE_NEW_WINDOW_MILLIS &&
      (discoverySeenAt == null ||
        discoverySeenAt.toMillis() < pin.publishAtMillis);
    const markerFlags: MarkerFlag[] = [];
    if (followedAuthorNew) markerFlags.push("followedAuthorNew");
    if (hasUnseenMessages) markerFlags.push("unseenMessages");
    const {creatorUid: _creatorUid, publishAtMillis: _publishAt, ...result} =
      pin;
    void _creatorUid;
    void _publishAt;
    return {...result, markerFlags};
  });
}

export const listMapPins = onCall<ListMapPinsData>(
  {enforceAppCheck: true, region: REGION},
  async (req) => {
    const startedAt = Date.now();
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
    const noteAccessRadiusKm = await noteAccessRadiusKmForUser(db, uid);
    const nowMillis = Date.now();
    const publishedAt = Timestamp.fromMillis(nowMillis);
    const expiresAfter = Timestamp.fromMillis(nowMillis);
    const useFineSearch =
      searchRadiusKm <= MAP_PIN_FINE_SEARCH_MAX_RADIUS_KM;
    const fineQuerySpecs = useFineSearch ?
      fineQueries(center, searchRadiusKm) :
      fineQueries(center, ZOOMED_OUT_LOCAL_RADIUS_KM);
    const prefixQuerySpec = useFineSearch ?
      null :
      prefixQuery(center, searchRadiusKm);
    const prefixQuerySpecs = prefixQuerySpec == null ?
      [] :
      [prefixQuerySpec];
    const queryCount = useFineSearch ?
      fineQuerySpecs.length :
      prefixQuerySpecs.length;
    const resultLimit = useFineSearch ?
      MAP_PIN_RESULT_LIMIT :
      MAP_PIN_ZOOMED_OUT_RESULT_LIMIT;
    const localPerQueryLimit = useFineSearch ?
      Math.max(
        10,
        Math.ceil(resultLimit / Math.max(queryCount, 1)),
      ) :
      Math.max(
        1,
        Math.ceil(resultLimit / Math.max(fineQuerySpecs.length, 1)),
      );
    const prefixPerQueryLimit = Math.max(
      10,
      Math.ceil(resultLimit / Math.max(queryCount, 1)),
    );
    const localSnapshots = await Promise.all(
      fineQuerySpecs.map((query) => db
        .collection("places")
        .where("geohash", "in", query.geohashes)
        .where("discoveryGeohash", "==", query.discoveryGeohash)
        .where("isArchived", "==", false)
        .where("publishAt", "<=", publishedAt)
        .where("expiresAt", ">", expiresAfter)
        .orderBy("publishAt")
        .orderBy("expiresAt")
        .limit(localPerQueryLimit)
        .get()),
    );
    const prefixSnapshots = useFineSearch ?
      [] :
      await Promise.all(
        prefixQuerySpecs.map((query) => db
          .collection("places")
          .where(query.fieldPath, "in", query.geohashes)
          .where("isArchived", "==", false)
          .where("publishAt", "<=", publishedAt)
          .where("expiresAt", ">", expiresAfter)
          .orderBy("publishAt")
          .orderBy("expiresAt")
          .limit(prefixPerQueryLimit)
          .get()),
      );
    const seen = new Set<string>();
    // Preserve center-near pins first, then fill any remaining zoomed-out
    // budget with wider-area results.
    const localPins = collectPins(
      localSnapshots,
      user,
      noteAccessRadiusKm,
      nowMillis,
      seen,
    );
    const prefixPins = collectPins(
      prefixSnapshots,
      user,
      noteAccessRadiusKm,
      nowMillis,
      seen,
    );
    const pins = [...localPins, ...prefixPins];
    const visiblePins = await takeVisibleMapPins(
      pins,
      resultLimit,
      (candidateUids) => findUserIdsWithBlockRelationshipToViewer(
        db,
        uid,
        candidateUids,
      ),
    );
    const basePinsReadyAt = Date.now();
    const enrichedPins = await addMarkerFlagsToPins(
      db,
      uid,
      visiblePins,
      nowMillis,
    );
    logger.debug("listMapPins: composed viewer marker states.", {
      pinCount: enrichedPins.length,
      baseQueryMillis: basePinsReadyAt - startedAt,
      viewerStateMillis: Date.now() - basePinsReadyAt,
      totalMillis: Date.now() - startedAt,
    });
    return {pins: enrichedPins};
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

    const db = getFirestore();
    const [snap, noteAccessRadiusKm] = await Promise.all([
      db.collection("places").doc(placeId).get(),
      noteAccessRadiusKmForUser(db, uid),
    ]);
    if (!snap.exists) throw new HttpsError("not-found", "Note not found.");
    const creatorUid = snap.get("createdByUserId") as string;
    if (await hasUserBlockBetween(db, uid, creatorUid)) {
      throw new HttpsError(
        "permission-denied",
        "This note is not available.",
        {reason: "user_blocked"},
      );
    }
    const nowMillis = Date.now();
    if (!isPublishedPlace(snap, nowMillis)) {
      throw new HttpsError(
        "failed-precondition",
        "This note is not available.",
      );
    }
    if (!canOpenFrom(user, placeCoordinates(snap), noteAccessRadiusKm)) {
      throw new HttpsError(
        "permission-denied",
        "Move closer to this note to open it.",
      );
    }

    return {ok: true};
  },
);
