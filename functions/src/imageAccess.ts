/* eslint-disable require-jsdoc, valid-jsdoc */

import {
  DocumentSnapshot,
  Firestore,
  Timestamp,
} from "firebase-admin/firestore";

import {REGION} from "./constants";
import {hasValidMembership, isPublishedReadablePlace} from "./likeHelpers";
import {canMaintainNote} from "./noteMaintenance";
import {HttpsError, onCall} from "./platform/worldCallable";
import {WorldBucket} from "./platform/worldBucketProvider";
import {hasUserBlockBetween} from "./userBlocks";

export const SIGNED_IMAGE_URL_LIFETIME_MILLIS = 24 * 60 * 60 * 1000;
export const SIGNED_IMAGE_URL_MAX_PATHS = 50;
export const IMAGE_ACCESS_STATUS = Object.freeze({
  available: "available",
  unavailable: "unavailable",
} as const);

export type ImageAccessStatus =
  typeof IMAGE_ACCESS_STATUS[keyof typeof IMAGE_ACCESS_STATUS];

const UUID_V7 =
  "[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-" +
  "[89ab][0-9a-f]{3}-[0-9a-f]{12}";
const PATH_SEGMENT = "[^/\\s]{1,256}";
const MESSAGE_IMAGE_PATTERN = new RegExp(
  `^images/messages/(${PATH_SEGMENT})/(${PATH_SEGMENT})/` +
  `(${UUID_V7})/([0-3][.]webp)$`,
);
const PIN_IMAGE_PATTERN = new RegExp(
  `^images/pins/(${PATH_SEGMENT})/(${PATH_SEGMENT})/` +
  `(${UUID_V7}[.]webp)$`,
);
const READABLE_MODERATION_ACTIONS = new Set([
  "pending",
  "allow",
  "sensitive",
  "review",
]);

export type ImageStorageRoute =
  | Readonly<{
    kind: "message";
    storagePath: string;
    placeId: string;
    ownerUid: string;
    messageId: string;
  }>
  | Readonly<{
    kind: "pin";
    storagePath: string;
    placeId: string;
    ownerUid: string;
  }>;

export interface SignedImageAccessResult {
  readonly storagePath: string;
  readonly status: ImageAccessStatus;
  readonly url?: string;
  readonly expiresAtMillis?: number;
}

interface ImageAccessData {
  storagePaths?: unknown;
}

interface ImageAuthorizationContext {
  readonly firestore: Firestore;
  readonly uid: string;
  readonly nowMillis: number;
}

/** Parses only immutable application-owned image object paths. */
export function parseImageStorageRoute(storagePath: string): ImageStorageRoute {
  const message = MESSAGE_IMAGE_PATTERN.exec(storagePath);
  if (message !== null) {
    return Object.freeze({
      kind: "message" as const,
      storagePath,
      placeId: message[1],
      ownerUid: message[2],
      messageId: message[3],
    });
  }
  const pin = PIN_IMAGE_PATTERN.exec(storagePath);
  if (pin !== null) {
    return Object.freeze({
      kind: "pin" as const,
      storagePath,
      placeId: pin[1],
      ownerUid: pin[2],
    });
  }
  throw new HttpsError("invalid-argument", "Invalid image storage path.");
}

/** Mirrors the authoritative note access policy for image delivery. */
export function canAccessPlaceImage(
  place: DocumentSnapshot,
  member: DocumentSnapshot | null,
  uid: string,
  nowMillis: number,
  creatorBlocked: boolean,
): boolean {
  if (!place.exists || creatorBlocked ||
      !isPublishedReadablePlace(place, nowMillis)) {
    return false;
  }
  if (place.get("visibility") !== "private") return true;
  return canMaintainNote(place, uid) || hasValidMembership(place, member);
}

/** Mirrors message visibility and exact-reference checks for image delivery. */
export function canAccessMessageImage(
  place: DocumentSnapshot,
  member: DocumentSnapshot | null,
  message: DocumentSnapshot,
  route: Extract<ImageStorageRoute, {kind: "message"}>,
  uid: string,
  nowMillis: number,
  creatorBlocked: boolean,
  authorBlocked: boolean,
): boolean {
  if (!canAccessPlaceImage(
    place,
    member,
    uid,
    nowMillis,
    creatorBlocked,
  ) || !message.exists || authorBlocked) {
    return false;
  }
  const authorUid = message.get("userId");
  const paths = message.get("imageStoragePaths");
  if (authorUid !== route.ownerUid ||
      !Array.isArray(paths) || !paths.includes(route.storagePath) ||
      message.get("isDeleted") === true ||
      message.get("isVisible") !== true ||
      !READABLE_MODERATION_ACTIONS.has(message.get("moderationAction"))) {
    return false;
  }
  return message.get("isPubliclyVisible") === true || authorUid === uid;
}

/** Authorizes each requested path without revealing why an item is denied. */
export async function authorizeImageStoragePaths(
  context: ImageAuthorizationContext,
  routes: readonly ImageStorageRoute[],
): Promise<ReadonlyMap<string, boolean>> {
  const placeCache = new Map<string, Promise<DocumentSnapshot>>();
  const memberCache = new Map<string, Promise<DocumentSnapshot>>();
  const blockCache = new Map<string, Promise<boolean>>();
  const result = new Map<string, boolean>();

  const placeFor = (placeId: string) => placeCache.get(placeId) ??
    cache(placeCache, placeId, context.firestore
      .collection("places").doc(placeId).get());
  const membershipFor = (placeId: string) => memberCache.get(placeId) ??
    cache(memberCache, placeId, context.firestore
      .collection("places").doc(placeId)
      .collection("members").doc(context.uid).get());
  const blockedWith = (peerUid: string) => blockCache.get(peerUid) ??
    cache(blockCache, peerUid, hasUserBlockBetween(
      context.firestore,
      context.uid,
      peerUid,
    ));

  await Promise.all(routes.map(async (route) => {
    const place = await placeFor(route.placeId);
    const creatorUid = place.get("createdByUserId");
    if (typeof creatorUid !== "string") {
      result.set(route.storagePath, false);
      return;
    }
    const member = place.get("visibility") === "private" ?
      await membershipFor(route.placeId) : null;
    const creatorBlocked = await blockedWith(creatorUid);
    if (route.kind === "pin") {
      result.set(
        route.storagePath,
        place.get("pinImageStoragePath") === route.storagePath &&
          canAccessPlaceImage(
            place,
            member,
            context.uid,
            context.nowMillis,
            creatorBlocked,
          ),
      );
      return;
    }

    const message = await context.firestore
      .collection("places").doc(route.placeId)
      .collection("messages").doc(route.messageId).get();
    const authorUid = message.get("userId");
    const authorBlocked = typeof authorUid === "string" ?
      await blockedWith(authorUid) : true;
    result.set(
      route.storagePath,
      canAccessMessageImage(
        place,
        member,
        message,
        route,
        context.uid,
        context.nowMillis,
        creatorBlocked,
        authorBlocked,
      ),
    );
  }));
  return result;
}

/** Issues one V4 URL whose response must stay in private caches. */
export async function signedImageUrl(
  bucket: WorldBucket,
  storagePath: string,
  expiresAtMillis: number,
): Promise<string> {
  const [url] = await bucket.file(storagePath).getSignedUrl({
    version: "v4",
    action: "read",
    expires: new Date(expiresAtMillis),
    queryParams: {
      "response-cache-control": "private,max-age=86400",
    },
  });
  return url;
}

/** Returns bounded, world-authorized signed URLs for visible images. */
export const getImageAccessUrls = onCall<ImageAccessData>(
  {enforceAppCheck: true, region: REGION},
  async (request, world) => {
    const uid = request.auth?.uid;
    if (!uid) throw new HttpsError("unauthenticated", "Sign in required.");
    const storagePaths = requireStoragePaths(request.data?.storagePaths);
    const routes = storagePaths.map(parseImageStorageRoute);
    const now = Timestamp.now();
    const authorization = await authorizeImageStoragePaths({
      firestore: world.firestore,
      uid,
      nowMillis: now.toMillis(),
    }, routes);
    const expiresAtMillis = now.toMillis() +
      SIGNED_IMAGE_URL_LIFETIME_MILLIS;
    const images: SignedImageAccessResult[] = await Promise.all(
      routes.map(async (route) => {
        if (authorization.get(route.storagePath) !== true) {
          return {
            storagePath: route.storagePath,
            status: IMAGE_ACCESS_STATUS.unavailable,
          };
        }
        return {
          storagePath: route.storagePath,
          status: IMAGE_ACCESS_STATUS.available,
          url: await signedImageUrl(
            world.bucket,
            route.storagePath,
            expiresAtMillis,
          ),
          expiresAtMillis,
        };
      }),
    );
    return {images};
  },
);

function requireStoragePaths(value: unknown): string[] {
  if (!Array.isArray(value) || value.length === 0 ||
      value.length > SIGNED_IMAGE_URL_MAX_PATHS) {
    throw new HttpsError(
      "invalid-argument",
      `storagePaths must contain between 1 and ${
        SIGNED_IMAGE_URL_MAX_PATHS
      } paths.`,
    );
  }
  const paths = value.map((path) => {
    if (typeof path !== "string" || path.length === 0 || path.length > 1024) {
      throw new HttpsError("invalid-argument", "Invalid image storage path.");
    }
    return path;
  });
  if (new Set(paths).size !== paths.length) {
    throw new HttpsError("invalid-argument", "Duplicate image storage path.");
  }
  return paths;
}

function cache<K, V>(map: Map<K, Promise<V>>, key: K, value: Promise<V>) {
  map.set(key, value);
  return value;
}
