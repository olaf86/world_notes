/* eslint-disable require-jsdoc */
import {createHash} from "crypto";
import {onCall, HttpsError} from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";
import {
  DocumentReference,
  DocumentSnapshot,
  FieldValue,
  Firestore,
  Timestamp,
  getFirestore,
} from "firebase-admin/firestore";
import {BatchResponse, getMessaging} from "firebase-admin/messaging";

import {
  NEARBY_NOTIFICATION_IN_RANGE_TTL_MINUTES,
  NEARBY_NOTIFICATION_LIMIT,
  NOTE_DETAIL_ACCESS_RADIUS_KM,
  REGION,
} from "./constants";

interface RegisterFcmTokenData {
  token?: unknown;
  platform?: unknown;
}

interface DeleteFcmTokenData {
  token?: unknown;
}

interface SetMyNotesNotificationEnabledData {
  enabled?: unknown;
}

interface SetMyNotesNotificationPreviewEnabledData {
  enabled?: unknown;
}

interface SetNearbyNotificationData {
  placeId?: unknown;
  enabled?: unknown;
}

interface CheckNearbyUnreadData {
  placeId?: unknown;
}

interface MarkNearbyInRangeData {
  placeId?: unknown;
  inRange?: unknown;
}

interface MarkNearbyReadData {
  placeId?: unknown;
}

type NotificationLocale = "en" | "ja";

interface MyNotesNotificationToken {
  ref: DocumentReference;
  token: string;
  showPreview: boolean;
  locale: NotificationLocale;
}

interface NotificationContent {
  title: string;
  body: string;
}

interface MyNotesNotificationGroup {
  locale: NotificationLocale;
  showPreview: boolean;
  tokens: MyNotesNotificationToken[];
}

interface MyNotesSendContext {
  placeId: string;
  messageId: string;
  locale: NotificationLocale;
  showPreview: boolean;
}

const VALID_PLATFORMS = new Set([
  "android",
  "ios",
  "macos",
  "web",
  "unknown",
]);
const DEFAULT_NOTIFICATION_LOCALE: NotificationLocale = "en";
const SUPPORTED_NOTIFICATION_LOCALES: readonly NotificationLocale[] = [
  "en",
  "ja",
];
const FCM_MULTICAST_LIMIT = 500;
const NOTIFICATION_PLACE_TITLE_MAX_LENGTH = 80;
const NOTIFICATION_MESSAGE_PREVIEW_MAX_LENGTH = 120;
const TEXT_ELLIPSIS = "...";
const INVALID_FCM_TOKEN_CODES = new Set([
  "messaging/registration-token-not-registered",
  "messaging/invalid-registration-token",
]);
const MY_NOTES_NOTIFICATION_COPY: Record<
  NotificationLocale,
  {
    fallbackNoteTitle: string;
    photoMessage: string;
    newMessage: string;
  }
> = {
  en: {
    fallbackNoteTitle: "Your note",
    photoMessage: "Photo message",
    newMessage: "New message",
  },
  ja: {
    fallbackNoteTitle: "あなたのノート",
    photoMessage: "写真メッセージ",
    newMessage: "新着メッセージ",
  },
};

function validToken(value: unknown): string {
  if (typeof value !== "string") {
    throw new HttpsError("invalid-argument", "token is required.");
  }
  const token = value.trim();
  if (token.length < 20 || token.length > 4096 || token.includes("/")) {
    throw new HttpsError("invalid-argument", "Invalid FCM token.");
  }
  return token;
}

function tokenDocId(token: string): string {
  return createHash("sha256").update(token).digest("hex");
}

function platformOf(value: unknown): string {
  if (typeof value !== "string") return "unknown";
  return VALID_PLATFORMS.has(value) ? value : "unknown";
}

function notificationLocaleOf(value: unknown): NotificationLocale {
  if (typeof value !== "string") return DEFAULT_NOTIFICATION_LOCALE;
  const language = value.trim().toLowerCase().split(/[-_]/)[0];
  return SUPPORTED_NOTIFICATION_LOCALES.includes(
    language as NotificationLocale,
  ) ?
    language as NotificationLocale :
    DEFAULT_NOTIFICATION_LOCALE;
}

function normalizedText(value: unknown): string {
  return typeof value === "string" ? value.replace(/\s+/g, " ").trim() : "";
}

function clippedText(value: string, maxLength: number): string {
  if (value.length <= maxLength) return value;
  return `${value.slice(
    0,
    Math.max(0, maxLength - TEXT_ELLIPSIS.length),
  ).trimEnd()}${TEXT_ELLIPSIS}`;
}

function noteNotificationTitle(
  placeTitle: unknown,
  locale: NotificationLocale,
): string {
  const title = normalizedText(placeTitle);
  return title.length === 0 ?
    MY_NOTES_NOTIFICATION_COPY[locale].fallbackNoteTitle :
    clippedText(title, NOTIFICATION_PLACE_TITLE_MAX_LENGTH);
}

function messageNotificationPreview(
  messageSnap: DocumentSnapshot,
  locale: NotificationLocale,
): string {
  const content = clippedText(
    normalizedText(messageSnap.get("content")),
    NOTIFICATION_MESSAGE_PREVIEW_MAX_LENGTH,
  );
  if (content.length > 0) return content;

  const imageStoragePath = normalizedText(messageSnap.get("imageStoragePath"));
  const copy = MY_NOTES_NOTIFICATION_COPY[locale];
  return imageStoragePath.length > 0 ? copy.photoMessage : copy.newMessage;
}

function myNotesNotificationContent(
  placeSnap: DocumentSnapshot,
  messageSnap: DocumentSnapshot,
  showPreview: boolean,
  locale: NotificationLocale,
): NotificationContent {
  const copy = MY_NOTES_NOTIFICATION_COPY[locale];
  return {
    title: noteNotificationTitle(placeSnap.get("title"), locale),
    body: showPreview ?
      messageNotificationPreview(messageSnap, locale) :
      copy.newMessage,
  };
}

function myNotesNotificationGroupKey(
  locale: NotificationLocale,
  showPreview: boolean,
): string {
  return `${locale}:${showPreview ? "preview" : "private"}`;
}

function groupMyNotesNotificationTokens(
  tokens: MyNotesNotificationToken[],
): MyNotesNotificationGroup[] {
  const groups = new Map<string, MyNotesNotificationGroup>();
  for (const token of tokens) {
    const key = myNotesNotificationGroupKey(token.locale, token.showPreview);
    const group = groups.get(key);
    if (group) {
      group.tokens.push(token);
      continue;
    }
    groups.set(key, {
      locale: token.locale,
      showPreview: token.showPreview,
      tokens: [token],
    });
  }
  return [...groups.values()];
}

function fcmErrorCodeCounts(response: BatchResponse): Record<string, number> {
  return response.responses.reduce<Record<string, number>>((counts, result) => {
    const code = result.error?.code;
    if (!code) return counts;
    counts[code] = (counts[code] ?? 0) + 1;
    return counts;
  }, {});
}

function logMyNotesNotificationFailures(
  response: BatchResponse,
  context: MyNotesSendContext,
  tokenCount: number,
): void {
  if (response.failureCount === 0) return;
  logger.warn("sendMyNotesMessageNotifications: FCM send failures.", {
    ...context,
    tokenCount,
    successCount: response.successCount,
    failureCount: response.failureCount,
    errorCodeCounts: fcmErrorCodeCounts(response),
  });
}

async function deleteInvalidFcmTokens(
  response: BatchResponse,
  tokens: MyNotesNotificationToken[],
): Promise<void> {
  await Promise.all(
    response.responses.map(async (result, index) => {
      const code = result.error?.code;
      if (code != null && INVALID_FCM_TOKEN_CODES.has(code)) {
        await tokens[index].ref.delete();
      }
    }),
  );
}

function placeIdOf(value: unknown): string {
  if (typeof value !== "string" || value.length === 0 || value.length > 200) {
    throw new HttpsError("invalid-argument", "placeId is required.");
  }
  return value;
}

function boolOf(value: unknown, name: string): boolean {
  if (typeof value !== "boolean") {
    throw new HttpsError("invalid-argument", `${name} is required.`);
  }
  return value;
}

function ownerIdsOf(placeSnap: DocumentSnapshot): string[] {
  const ownerIds = placeSnap.get("ownerIds") as string[] | undefined;
  return ownerIds ?? [];
}

function isOwner(placeSnap: DocumentSnapshot, uid: string): boolean {
  return placeSnap.get("createdByUserId") === uid ||
    ownerIdsOf(placeSnap).includes(uid);
}

function isPublishedPlace(placeSnap: DocumentSnapshot, nowMs: number): boolean {
  const publishAt = placeSnap.get("publishAt") as Timestamp | undefined;
  const expiresAt = placeSnap.get("expiresAt") as Timestamp | undefined;
  return placeSnap.exists &&
    placeSnap.get("isArchived") !== true &&
    publishAt != null &&
    expiresAt != null &&
    publishAt.toMillis() <= nowMs &&
    expiresAt.toMillis() > nowMs;
}

function hasValidMembership(
  placeSnap: DocumentSnapshot,
  memberSnap: DocumentSnapshot | null,
): boolean {
  if (!memberSnap?.exists) return false;
  return memberSnap.get("invited") === true ||
    memberSnap.get("viaPasswordVersion") === placeSnap.get("passwordVersion");
}

function canAccessPlace(
  placeSnap: DocumentSnapshot,
  memberSnap: DocumentSnapshot | null,
  uid: string,
): boolean {
  if (placeSnap.get("visibility") !== "private") return true;
  if (isOwner(placeSnap, uid)) return true;
  return hasValidMembership(placeSnap, memberSnap);
}

function notificationPlaceData(
  placeSnap: DocumentSnapshot,
  enabled: boolean,
  state: "active" | "archived" | "revoked",
  lastReadMessageAt: Timestamp | FieldValue,
): Record<string, unknown> {
  const expiresAt = placeSnap.get("expiresAt") as Timestamp;
  return {
    placeId: placeSnap.id,
    title: placeSnap.get("title") as string,
    colorHex: placeSnap.get("colorHex") as string,
    icon: placeSnap.get("icon") as string,
    latitude: placeSnap.get("latitude") as number,
    longitude: placeSnap.get("longitude") as number,
    radiusMeters: Math.round(NOTE_DETAIL_ACCESS_RADIUS_KM * 1000),
    expiresAt,
    enabled,
    state,
    lastReadMessageAt,
    lastNotifiedMessageAt: lastReadMessageAt,
    updatedAt: FieldValue.serverTimestamp(),
  };
}

function notificationBody(placeTitle: unknown): string {
  const title = typeof placeTitle === "string" ? placeTitle.trim() : "";
  if (title.length === 0) {
    return "A nearby note has a new message.";
  }
  const clipped = title.length > 60 ? `${title.slice(0, 57)}...` : title;
  return `"${clipped}" has a new nearby message.`;
}

export const registerFcmToken = onCall<RegisterFcmTokenData>(
  {enforceAppCheck: true, region: REGION},
  async (req) => {
    const uid = req.auth?.uid;
    if (!uid) throw new HttpsError("unauthenticated", "Sign in required.");

    const token = validToken(req.data?.token);
    const platform = platformOf(req.data?.platform);
    const ref = getFirestore()
      .collection("users")
      .doc(uid)
      .collection("fcmTokens")
      .doc(tokenDocId(token));

    await ref.set(
      {
        token,
        platform,
        updatedAt: FieldValue.serverTimestamp(),
        createdAt: FieldValue.serverTimestamp(),
      },
      {merge: true},
    );

    logger.info("registerFcmToken: registered device token.", {
      uid,
      platform,
      tokenDocumentId: ref.id,
    });
    return {ok: true};
  },
);

export const deleteFcmToken = onCall<DeleteFcmTokenData>(
  {enforceAppCheck: true, region: REGION},
  async (req) => {
    const uid = req.auth?.uid;
    if (!uid) throw new HttpsError("unauthenticated", "Sign in required.");

    const token = validToken(req.data?.token);
    await getFirestore()
      .collection("users")
      .doc(uid)
      .collection("fcmTokens")
      .doc(tokenDocId(token))
      .delete();

    return {ok: true};
  },
);

export const setMyNotesNotificationEnabled =
  onCall<SetMyNotesNotificationEnabledData>(
    {enforceAppCheck: true, region: REGION},
    async (req) => {
      const uid = req.auth?.uid;
      if (!uid) throw new HttpsError("unauthenticated", "Sign in required.");
      if (typeof req.data?.enabled !== "boolean") {
        throw new HttpsError("invalid-argument", "enabled is required.");
      }

      await getFirestore()
        .collection("users")
        .doc(uid)
        .collection("notificationSettings")
        .doc("main")
        .set(
          {
            myNotesEnabled: req.data.enabled,
            updatedAt: FieldValue.serverTimestamp(),
          },
          {merge: true},
        );

      return {ok: true};
    },
  );

export const setMyNotesNotificationPreviewEnabled =
  onCall<SetMyNotesNotificationPreviewEnabledData>(
    {enforceAppCheck: true, region: REGION},
    async (req) => {
      const uid = req.auth?.uid;
      if (!uid) throw new HttpsError("unauthenticated", "Sign in required.");
      if (typeof req.data?.enabled !== "boolean") {
        throw new HttpsError("invalid-argument", "enabled is required.");
      }

      await getFirestore()
        .collection("users")
        .doc(uid)
        .collection("notificationSettings")
        .doc("main")
        .set(
          {
            myNotesPreviewEnabled: req.data.enabled,
            updatedAt: FieldValue.serverTimestamp(),
          },
          {merge: true},
        );

      return {ok: true};
    },
  );

export const setNearbyNotification = onCall<SetNearbyNotificationData>(
  {enforceAppCheck: true, region: REGION},
  async (req) => {
    const uid = req.auth?.uid;
    if (!uid) throw new HttpsError("unauthenticated", "Sign in required.");

    const placeId = placeIdOf(req.data?.placeId);
    const enabled = boolOf(req.data?.enabled, "enabled");
    const db = getFirestore();
    const placeRef = db.collection("places").doc(placeId);
    const followerRef = placeRef
      .collection("nearbyNotificationFollowers")
      .doc(uid);
    const userPlaceRef = db
      .collection("users")
      .doc(uid)
      .collection("nearbyNotificationPlaces")
      .doc(placeId);

    await db.runTransaction(async (tx) => {
      const nowMs = Date.now();
      const [placeSnap, followerSnap] = await Promise.all([
        tx.get(placeRef),
        tx.get(followerRef),
      ]);
      if (!placeSnap.exists) {
        throw new HttpsError("not-found", "Note not found.");
      }

      if (!enabled) {
        const update = {
          enabled: false,
          state: "revoked",
          inRange: false,
          inRangeUntil: FieldValue.delete(),
          updatedAt: FieldValue.serverTimestamp(),
        };
        tx.set(followerRef, update, {merge: true});
        tx.set(userPlaceRef, update, {merge: true});
        return;
      }

      if (!isPublishedPlace(placeSnap, nowMs)) {
        throw new HttpsError(
          "failed-precondition",
          "This note is not available.",
        );
      }
      if (isOwner(placeSnap, uid)) {
        throw new HttpsError(
          "failed-precondition",
          "Nearby alerts are only for notes you do not own.",
        );
      }

      const memberSnap =
        placeSnap.get("visibility") === "private" ?
          await tx.get(placeRef.collection("members").doc(uid)) :
          null;
      if (!canAccessPlace(placeSnap, memberSnap, uid)) {
        throw new HttpsError(
          "permission-denied",
          "You cannot access this note.",
        );
      }

      const wasActive =
        followerSnap.exists &&
        followerSnap.get("enabled") === true &&
        followerSnap.get("state") === "active";
      if (!wasActive) {
        const activeSnap = await tx.get(
          db
            .collection("users")
            .doc(uid)
            .collection("nearbyNotificationPlaces")
            .where("enabled", "==", true)
            .where("state", "==", "active"),
        );
        if (activeSnap.size >= NEARBY_NOTIFICATION_LIMIT) {
          throw new HttpsError(
            "resource-exhausted",
            `Nearby alerts are limited to ${NEARBY_NOTIFICATION_LIMIT} notes.`,
          );
        }
      }

      const lastRead =
        (placeSnap.get("lastMessageAt") as Timestamp | undefined) ??
        Timestamp.fromMillis(nowMs);
      const followerData = {
        enabled: true,
        state: "active",
        lastReadMessageAt: lastRead,
        lastNotifiedMessageAt: lastRead,
        inRange: false,
        createdAt: followerSnap.exists ?
          followerSnap.get("createdAt") ?? FieldValue.serverTimestamp() :
          FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      };
      tx.set(followerRef, followerData, {merge: true});
      tx.set(
        userPlaceRef,
        {
          ...notificationPlaceData(placeSnap, true, "active", lastRead),
          inRange: false,
        },
        {merge: true},
      );
    });

    return {ok: true};
  },
);

export const markNearbyNotificationRead = onCall<MarkNearbyReadData>(
  {enforceAppCheck: true, region: REGION},
  async (req) => {
    const uid = req.auth?.uid;
    if (!uid) throw new HttpsError("unauthenticated", "Sign in required.");

    const placeId = placeIdOf(req.data?.placeId);
    const db = getFirestore();
    const placeRef = db.collection("places").doc(placeId);
    const followerRef = placeRef
      .collection("nearbyNotificationFollowers")
      .doc(uid);
    const userPlaceRef = db
      .collection("users")
      .doc(uid)
      .collection("nearbyNotificationPlaces")
      .doc(placeId);

    await db.runTransaction(async (tx) => {
      const [placeSnap, followerSnap] = await Promise.all([
        tx.get(placeRef),
        tx.get(followerRef),
      ]);
      if (!placeSnap.exists || !followerSnap.exists) return;
      if (followerSnap.get("enabled") !== true) return;
      const lastRead =
        (placeSnap.get("lastMessageAt") as Timestamp | undefined) ??
        Timestamp.now();
      const update = {
        lastReadMessageAt: lastRead,
        lastNotifiedMessageAt: lastRead,
        updatedAt: FieldValue.serverTimestamp(),
      };
      tx.set(followerRef, update, {merge: true});
      tx.set(userPlaceRef, update, {merge: true});
    });

    return {ok: true};
  },
);

export const markNearbyNotificationInRange =
  onCall<MarkNearbyInRangeData>(
    {enforceAppCheck: true, region: REGION},
    async (req) => {
      const uid = req.auth?.uid;
      if (!uid) throw new HttpsError("unauthenticated", "Sign in required.");

      const placeId = placeIdOf(req.data?.placeId);
      const inRange = boolOf(req.data?.inRange, "inRange");
      const now = Timestamp.now();
      const until = Timestamp.fromMillis(
        now.toMillis() +
          NEARBY_NOTIFICATION_IN_RANGE_TTL_MINUTES * 60 * 1000,
      );
      const db = getFirestore();
      const followerRef = db
        .collection("places")
        .doc(placeId)
        .collection("nearbyNotificationFollowers")
        .doc(uid);
      const userPlaceRef = db
        .collection("users")
        .doc(uid)
        .collection("nearbyNotificationPlaces")
        .doc(placeId);
      const update = inRange ?
        {
          inRange: true,
          inRangeUntil: until,
          lastEnteredAt: now,
          updatedAt: FieldValue.serverTimestamp(),
        } :
        {
          inRange: false,
          inRangeUntil: FieldValue.delete(),
          lastExitedAt: now,
          updatedAt: FieldValue.serverTimestamp(),
        };
      await Promise.all([
        followerRef.set(update, {merge: true}),
        userPlaceRef.set(update, {merge: true}),
      ]);
      logger.info("markNearbyNotificationInRange: state updated.", {
        placeId,
        inRange,
      });
      return {ok: true};
    },
  );

async function latestUnreadMessage(
  db: Firestore,
  placeId: string,
  uid: string,
  cutoff: Timestamp,
) {
  const snap = await db
    .collection("places")
    .doc(placeId)
    .collection("messages")
    .where("isPubliclyVisible", "==", true)
    .where("isVisible", "==", true)
    .orderBy("publishAt", "desc")
    .limit(20)
    .get();

  return snap.docs.find((doc) => {
    const publishAt = doc.get("publishAt") as Timestamp | undefined;
    return publishAt != null &&
      publishAt.toMillis() > cutoff.toMillis() &&
      doc.get("isDeleted") !== true &&
      doc.get("userId") !== uid;
  });
}

export const checkNearbyUnread = onCall<CheckNearbyUnreadData>(
  {enforceAppCheck: true, region: REGION},
  async (req) => {
    const uid = req.auth?.uid;
    if (!uid) throw new HttpsError("unauthenticated", "Sign in required.");

    const placeId = placeIdOf(req.data?.placeId);
    const db = getFirestore();
    const placeRef = db.collection("places").doc(placeId);
    const followerRef = placeRef
      .collection("nearbyNotificationFollowers")
      .doc(uid);
    const userPlaceRef = db
      .collection("users")
      .doc(uid)
      .collection("nearbyNotificationPlaces")
      .doc(placeId);
    const [placeSnap, followerSnap] = await Promise.all([
      placeRef.get(),
      followerRef.get(),
    ]);
    if (!placeSnap.exists || !followerSnap.exists) {
      throw new HttpsError("not-found", "Nearby alert not found.");
    }
    if (followerSnap.get("enabled") !== true) {
      return {hasUnread: false};
    }
    if (!isPublishedPlace(placeSnap, Date.now())) {
      const update = {
        enabled: false,
        state: "archived",
        inRange: false,
        updatedAt: FieldValue.serverTimestamp(),
      };
      await Promise.all([
        followerRef.set(update, {merge: true}),
        userPlaceRef.set(update, {merge: true}),
      ]);
      return {hasUnread: false};
    }
    const memberSnap =
      placeSnap.get("visibility") === "private" ?
        await placeRef.collection("members").doc(uid).get() :
        null;
    if (!canAccessPlace(placeSnap, memberSnap, uid)) {
      const update = {
        enabled: false,
        state: "revoked",
        inRange: false,
        updatedAt: FieldValue.serverTimestamp(),
      };
      await Promise.all([
        followerRef.set(update, {merge: true}),
        userPlaceRef.set(update, {merge: true}),
      ]);
      return {hasUnread: false};
    }

    const now = Timestamp.now();
    const inRangeUntil = Timestamp.fromMillis(
      now.toMillis() +
        NEARBY_NOTIFICATION_IN_RANGE_TTL_MINUTES * 60 * 1000,
    );
    await Promise.all([
      followerRef.set(
        {
          inRange: true,
          inRangeUntil,
          lastEnteredAt: now,
          updatedAt: FieldValue.serverTimestamp(),
        },
        {merge: true},
      ),
      userPlaceRef.set(
        {
          inRange: true,
          inRangeUntil,
          lastEnteredAt: now,
          updatedAt: FieldValue.serverTimestamp(),
        },
        {merge: true},
      ),
    ]);

    const lastRead =
      (followerSnap.get("lastReadMessageAt") as Timestamp | undefined) ??
      Timestamp.fromMillis(0);
    const lastNotified =
      (followerSnap.get("lastNotifiedMessageAt") as Timestamp | undefined) ??
      Timestamp.fromMillis(0);
    const cutoff =
      lastRead.toMillis() > lastNotified.toMillis() ? lastRead : lastNotified;
    const unread = await latestUnreadMessage(db, placeId, uid, cutoff);
    if (!unread) {
      logger.info("checkNearbyUnread: no unread message.", {placeId});
      return {hasUnread: false};
    }

    const publishAt = unread.get("publishAt") as Timestamp;
    const update = {
      lastNotifiedMessageAt: publishAt,
      updatedAt: FieldValue.serverTimestamp(),
    };
    await Promise.all([
      followerRef.set(update, {merge: true}),
      userPlaceRef.set(update, {merge: true}),
    ]);

    logger.info("checkNearbyUnread: unread message found.", {placeId});
    return {
      hasUnread: true,
      placeId,
      messageId: unread.id,
      title: placeSnap.get("title") as string,
    };
  },
);

/**
 * Sends a push notification to note owners when somebody else posts a message.
 *
 * @param {Firestore} db Firestore instance.
 * @param {string} placeId Note id.
 * @param {string} messageId Message id.
 * @param {string} senderId User id that posted the message.
 */
export async function sendMyNotesMessageNotifications(
  db: Firestore,
  placeId: string,
  messageId: string,
  senderId: string,
): Promise<void> {
  const placeRef = db.collection("places").doc(placeId);
  const messageRef = placeRef.collection("messages").doc(messageId);
  const [placeSnap, messageSnap] = await Promise.all([
    placeRef.get(),
    messageRef.get(),
  ]);

  if (!placeSnap.exists || !messageSnap.exists) return;
  if (placeSnap.get("isArchived") === true) return;
  const expiresAt = placeSnap.get("expiresAt") as Timestamp | undefined;
  if (!expiresAt || expiresAt.toMillis() <= Date.now()) return;
  if (messageSnap.get("isDeleted") === true) return;
  if (messageSnap.get("isVisible") !== true) return;
  if (messageSnap.get("isPubliclyVisible") !== true) return;

  const ownerIds = new Set<string>(
    ((placeSnap.get("ownerIds") as string[] | undefined) ?? [])
      .filter((value) => typeof value === "string" && value.length > 0),
  );
  const createdBy = placeSnap.get("createdByUserId") as string | undefined;
  if (createdBy) ownerIds.add(createdBy);
  ownerIds.delete(senderId);
  if (ownerIds.size === 0) return;

  const ownerEntries = await Promise.all(
    [...ownerIds].map(async (uid) => {
      const userRef = db.collection("users").doc(uid);
      const settingsRef = userRef
        .collection("notificationSettings")
        .doc("main");
      const tokensRef = userRef.collection("fcmTokens");
      const [userSnap, settingsSnap, tokensSnap] = await Promise.all([
        userRef.get(),
        settingsRef.get(),
        tokensRef.get(),
      ]);
      const enabled = settingsSnap.get("myNotesEnabled") === true;
      if (!enabled) return {enabled: false, tokens: []};
      const showPreview = settingsSnap.get("myNotesPreviewEnabled") !== false;
      const locale = notificationLocaleOf(userSnap.get("locale"));
      const tokens = tokensSnap.docs.flatMap((doc) => {
        const token = doc.get("token");
        return typeof token === "string" && token.length > 0 ?
          [{ref: doc.ref, token, showPreview, locale}] :
          [];
      });
      return {enabled: true, tokens};
    }),
  );

  const enabledOwnerCount = ownerEntries.filter((entry) => entry.enabled)
    .length;
  const tokenEntries = ownerEntries.flatMap((entry) => entry.tokens);
  if (tokenEntries.length === 0) {
    logger.info(
      "sendMyNotesMessageNotifications: no registered recipient tokens.",
      {
        placeId,
        messageId,
        ownerCount: ownerIds.size,
        enabledOwnerCount,
      },
    );
    return;
  }

  const sendToGroup = async (
    group: MyNotesNotificationGroup,
  ): Promise<number> => {
    const notification = myNotesNotificationContent(
      placeSnap,
      messageSnap,
      group.showPreview,
      group.locale,
    );
    const context: MyNotesSendContext = {
      placeId,
      messageId,
      locale: group.locale,
      showPreview: group.showPreview,
    };
    let successCount = 0;
    for (let i = 0; i < group.tokens.length; i += FCM_MULTICAST_LIMIT) {
      const chunk = group.tokens.slice(i, i + FCM_MULTICAST_LIMIT);
      try {
        const response = await getMessaging().sendEachForMulticast({
          tokens: chunk.map((entry) => entry.token),
          notification,
          data: {
            type: "my_note_message",
            placeId,
            messageId,
          },
          apns: {
            payload: {
              aps: {
                sound: "default",
              },
            },
          },
          android: {
            priority: "high",
            notification: {
              sound: "default",
            },
          },
        });

        successCount += response.successCount;
        logMyNotesNotificationFailures(response, context, chunk.length);
        await deleteInvalidFcmTokens(response, chunk);
      } catch (error) {
        logger.error("sendMyNotesMessageNotifications: FCM send threw.", {
          ...context,
          tokenCount: chunk.length,
          error,
        });
        throw error;
      }
    }
    return successCount;
  };

  let sent = 0;
  for (const group of groupMyNotesNotificationTokens(tokenEntries)) {
    sent += await sendToGroup(group);
  }

  logger.info(
    `sendMyNotesMessageNotifications: sent ${sent}/${tokenEntries.length}` +
      ` for places/${placeId}/messages/${messageId}.`,
  );
}

/**
 * Sends a push notification to non-owner nearby followers currently in range.
 *
 * @param {Firestore} db Firestore instance.
 * @param {string} placeId Note id.
 * @param {string} messageId Message id.
 * @param {string} senderId User id that posted the message.
 */
export async function sendNearbyInRangeMessageNotifications(
  db: Firestore,
  placeId: string,
  messageId: string,
  senderId: string,
): Promise<void> {
  const placeRef = db.collection("places").doc(placeId);
  const messageRef = placeRef.collection("messages").doc(messageId);
  const now = Timestamp.now();
  const [placeSnap, messageSnap, followersSnap] = await Promise.all([
    placeRef.get(),
    messageRef.get(),
    placeRef
      .collection("nearbyNotificationFollowers")
      .where("enabled", "==", true)
      .where("state", "==", "active")
      .where("inRangeUntil", ">", now)
      .get(),
  ]);

  if (!placeSnap.exists || !messageSnap.exists || followersSnap.empty) return;
  if (!isPublishedPlace(placeSnap, Date.now())) return;
  if (messageSnap.get("isDeleted") === true) return;
  if (messageSnap.get("isVisible") !== true) return;
  if (messageSnap.get("isPubliclyVisible") !== true) return;

  const publishAt = messageSnap.get("publishAt") as Timestamp | undefined;
  if (!publishAt) return;

  const userEntries = await Promise.all(
    followersSnap.docs.map(async (followerDoc) => {
      const uid = followerDoc.id;
      if (uid === senderId || isOwner(placeSnap, uid)) return [];
      const lastRead =
        (followerDoc.get("lastReadMessageAt") as Timestamp | undefined) ??
        Timestamp.fromMillis(0);
      const lastNotified =
        (followerDoc.get("lastNotifiedMessageAt") as Timestamp | undefined) ??
        Timestamp.fromMillis(0);
      const cutoff =
        lastRead.toMillis() > lastNotified.toMillis() ? lastRead : lastNotified;
      if (publishAt.toMillis() <= cutoff.toMillis()) return [];

      const memberSnap =
        placeSnap.get("visibility") === "private" ?
          await placeRef.collection("members").doc(uid).get() :
          null;
      if (!canAccessPlace(placeSnap, memberSnap, uid)) return [];

      const tokensSnap = await db
        .collection("users")
        .doc(uid)
        .collection("fcmTokens")
        .get();
      return tokensSnap.docs.flatMap((tokenDoc) => {
        const token = tokenDoc.get("token");
        return typeof token === "string" && token.length > 0 ?
          [{
            uid,
            followerRef: followerDoc.ref,
            userPlaceRef: db
              .collection("users")
              .doc(uid)
              .collection("nearbyNotificationPlaces")
              .doc(placeId),
            tokenRef: tokenDoc.ref,
            token,
          }] :
          [];
      });
    }),
  );

  const tokenEntries = userEntries.flat();
  if (tokenEntries.length === 0) return;

  const body = notificationBody(placeSnap.get("title"));
  let sent = 0;
  const notifiedUserIds = new Set<string>();
  for (let i = 0; i < tokenEntries.length; i += 500) {
    const chunk = tokenEntries.slice(i, i + 500);
    const response = await getMessaging().sendEachForMulticast({
      tokens: chunk.map((entry) => entry.token),
      notification: {
        title: "World Notes",
        body,
      },
      data: {
        type: "nearby_note_message",
        placeId,
        messageId,
      },
      apns: {
        payload: {
          aps: {
            sound: "default",
          },
        },
      },
      android: {
        priority: "high",
        notification: {
          sound: "default",
        },
      },
    });

    sent += response.successCount;
    await Promise.all(
      response.responses.map(async (result, index) => {
        const entry = chunk[index];
        if (result.success) {
          notifiedUserIds.add(entry.uid);
          return;
        }
        const code = result.error?.code;
        if (
          code === "messaging/registration-token-not-registered" ||
          code === "messaging/invalid-registration-token"
        ) {
          await entry.tokenRef.delete();
        }
      }),
    );
  }

  await Promise.all(
    [...notifiedUserIds].map(async (uid) => {
      const entry = tokenEntries.find((item) => item.uid === uid);
      if (!entry) return;
      const update = {
        lastNotifiedMessageAt: publishAt,
        updatedAt: FieldValue.serverTimestamp(),
      };
      await Promise.all([
        entry.followerRef.set(update, {merge: true}),
        entry.userPlaceRef.set(update, {merge: true}),
      ]);
    }),
  );

  logger.info(
    "sendNearbyInRangeMessageNotifications: sent " +
      `${sent}/${tokenEntries.length} for places/${placeId}/` +
      `messages/${messageId}.`,
  );
}
