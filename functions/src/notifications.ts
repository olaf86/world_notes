/* eslint-disable require-jsdoc */
import {createHash} from "crypto";
import {onCall, HttpsError} from "./platform/worldCallable";
import * as logger from "firebase-functions/logger";
import {
  DocumentReference,
  DocumentSnapshot,
  FieldValue,
  Firestore,
  Timestamp,
  Transaction,
} from "firebase-admin/firestore";
import {BatchResponse, getMessaging} from "firebase-admin/messaging";

import {REGION} from "./constants";
import {
  classifyFcmError,
  newNotificationOutboxData,
  notificationEventId,
  NotificationDeliveryHandler,
  NotificationDeliveryResult,
  NotificationOutboxData,
  NotificationRecipientStatus,
} from "./notificationOutbox";
import {worldContext} from "./platform/worldContext";
import {WORLD_REGISTRY} from "./platform/worldRegistry";
import {maintainerIdsOf} from "./noteMaintenance";
import {hasUserBlockBetween} from "./userBlocks";

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

type NotificationLocale = "en" | "ja";

interface MyNotesNotificationToken {
  uid: string;
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
  sourceWorld: string;
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
const NOTIFICATION_LIFETIME_MILLIS = 24 * 60 * 60 * 1000;
const NOTIFICATION_PLACE_TITLE_MAX_LENGTH = 80;
const NOTIFICATION_MESSAGE_PREVIEW_MAX_LENGTH = 120;
const TEXT_ELLIPSIS = "...";
export const MY_NOTES_MESSAGE_NOTIFICATION_EVENT = "notifyNoteMessage";
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

  const imageStoragePaths = messageSnap.get("imageStoragePaths");
  const hasImages =
    Array.isArray(imageStoragePaths) && imageStoragePaths.length > 0;
  const copy = MY_NOTES_NOTIFICATION_COPY[locale];
  return hasImages ? copy.photoMessage : copy.newMessage;
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

function groupMyNotesNotificationTokens(
  tokens: MyNotesNotificationToken[],
): MyNotesNotificationGroup[] {
  const groups = new Map<string, MyNotesNotificationGroup>();
  for (const token of tokens) {
    const key = `${token.locale}:${token.showPreview ? "preview" : "private"}`;
    const group = groups.get(key);
    if (group) {
      group.tokens.push(token);
    } else {
      groups.set(key, {
        locale: token.locale,
        showPreview: token.showPreview,
        tokens: [token],
      });
    }
  }
  return [...groups.values()];
}

function fcmErrorCodeCounts(response: BatchResponse): Record<string, number> {
  return response.responses.reduce<Record<string, number>>((counts, result) => {
    const code = result.error?.code;
    if (code) counts[code] = (counts[code] ?? 0) + 1;
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

export const registerFcmToken = onCall<RegisterFcmTokenData>(
  {enforceAppCheck: true, region: REGION, requireHomeWorld: true},
  async (req, world) => {
    const uid = req.auth?.uid;
    if (!uid) throw new HttpsError("unauthenticated", "Sign in required.");

    const token = validToken(req.data?.token);
    const platform = platformOf(req.data?.platform);
    const ref = world.firestore
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
  {enforceAppCheck: true, region: REGION, requireHomeWorld: true},
  async (req, world) => {
    const uid = req.auth?.uid;
    if (!uid) throw new HttpsError("unauthenticated", "Sign in required.");

    const token = validToken(req.data?.token);
    await world.firestore
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
    {enforceAppCheck: true, region: REGION, requireHomeWorld: true},
    async (req, world) => {
      const uid = req.auth?.uid;
      if (!uid) throw new HttpsError("unauthenticated", "Sign in required.");
      if (typeof req.data?.enabled !== "boolean") {
        throw new HttpsError("invalid-argument", "enabled is required.");
      }

      await world.firestore
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
    {enforceAppCheck: true, region: REGION, requireHomeWorld: true},
    async (req, world) => {
      const uid = req.auth?.uid;
      if (!uid) throw new HttpsError("unauthenticated", "Sign in required.");
      if (typeof req.data?.enabled !== "boolean") {
        throw new HttpsError("invalid-argument", "enabled is required.");
      }

      await world.firestore
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

/**
 * Creates one durable source-world notification intent in a transaction.
 *
 * @param {Transaction} transaction Message-publication transaction.
 * @param {Firestore} firestore Source-world Firestore database.
 * @param {object} input Trusted message and recipient source values.
 * @return {string | null} Event ID, or null when nobody should be notified.
 */
export function enqueueMyNotesMessageNotification(
  transaction: Transaction,
  firestore: Firestore,
  input: Readonly<{
    sourceWorld: string;
    place: DocumentSnapshot;
    messageId: string;
    senderId: string;
    createdAt: Timestamp;
  }>,
): string | null {
  WORLD_REGISTRY.requireWorld(input.sourceWorld);
  const recipients = currentMaintainerIds(input.place);
  recipients.delete(input.senderId);
  if (recipients.size === 0) return null;

  const placeId = input.place.id;
  const identity = {
    sourceEventId: input.messageId,
    ownerWorld: input.sourceWorld,
    eventType: MY_NOTES_MESSAGE_NOTIFICATION_EVENT,
    partition: createHash("sha256").update(placeId).digest("hex"),
  };
  const eventId = notificationEventId(identity);
  const data = newNotificationOutboxData({
    ...identity,
    eventId,
    sourceWorld: input.sourceWorld,
    entityType: "message",
    entityId: input.messageId,
    sourcePath: `places/${placeId}/messages/${input.messageId}`,
    recipientUids: [...recipients].sort(),
    expiresAt: Timestamp.fromMillis(
      input.createdAt.toMillis() + NOTIFICATION_LIFETIME_MILLIS,
    ),
  }, input.createdAt);
  transaction.create(
    firestore.collection("notificationOutbox").doc(eventId),
    {...data},
  );
  return eventId;
}

/** Delivers durable message-notification events from their source world. */
export const myNotesMessageNotificationHandler: NotificationDeliveryHandler = {
  eventType: MY_NOTES_MESSAGE_NOTIFICATION_EVENT,
  deliver: deliverMyNotesMessageNotification,
};

async function deliverMyNotesMessageNotification(
  {firestore, event}: Readonly<{
    firestore: Firestore;
    event: NotificationOutboxData;
  }>,
): Promise<NotificationDeliveryResult> {
  const pendingRecipients = event.recipientUids.filter(
    (uid) => event.recipientResults[uid] === "pending",
  );
  const skipped = resultForRecipients(pendingRecipients, "skipped");
  if (event.ownerWorld !== event.sourceWorld ||
      event.eventType !== MY_NOTES_MESSAGE_NOTIFICATION_EVENT ||
      event.entityType !== "message") {
    throw new Error("Message notification event route is invalid.");
  }

  const route = requireMessageSourceRoute(event);
  const placeRef = firestore.collection("places").doc(route.placeId);
  const [place, message] = await Promise.all([
    placeRef.get(),
    firestore.doc(event.sourcePath).get(),
  ]);
  if (!isDeliverableMessage(place, message)) {
    return {recipientResults: skipped};
  }
  const senderId = message.get("userId");
  if (typeof senderId !== "string" || senderId.length === 0) {
    throw new Error("Message notification sender is invalid.");
  }

  const maintainers = currentMaintainerIds(place);
  const recipientEntries = await Promise.all(pendingRecipients.map(
    (uid) => notificationRecipientEntry(
      firestore,
      uid,
      senderId,
      maintainers.has(uid),
    ),
  ));
  const recipientResults: Record<string, NotificationRecipientStatus> = {};
  const tokens: MyNotesNotificationToken[] = [];
  for (const entry of recipientEntries) {
    if (!entry.enabled || entry.tokens.length === 0) {
      recipientResults[entry.uid] = "skipped";
    } else {
      recipientResults[entry.uid] = "pending";
      tokens.push(...entry.tokens);
    }
  }

  const retryUids = new Set<string>();
  const successfulUids = new Set<string>();
  let lastErrorCode: string | undefined;
  for (const group of groupMyNotesNotificationTokens(tokens)) {
    const notification = myNotesNotificationContent(
      place,
      message,
      group.showPreview,
      group.locale,
    );
    for (let i = 0; i < group.tokens.length; i += FCM_MULTICAST_LIMIT) {
      const chunk = group.tokens.slice(i, i + FCM_MULTICAST_LIMIT);
      const context: MyNotesSendContext = {
        sourceWorld: event.sourceWorld,
        placeId: route.placeId,
        messageId: event.entityId,
        locale: group.locale,
        showPreview: group.showPreview,
      };
      try {
        const response = await getMessaging().sendEachForMulticast({
          tokens: chunk.map((entry) => entry.token),
          notification,
          data: {
            type: "my_note_message",
            eventId: event.eventId,
            worldId: event.sourceWorld,
            placeId: route.placeId,
            messageId: event.entityId,
          },
          apns: {
            headers: {"apns-collapse-id": event.eventId},
            payload: {aps: {
              sound: "default",
              threadId: `world:${event.sourceWorld}:place:${route.placeId}`,
            }},
          },
          android: {
            priority: "high",
            notification: {
              sound: "default",
              tag: `notification:${event.eventId}`,
            },
          },
        });
        logMyNotesNotificationFailures(response, context, chunk.length);
        const classified = await classifyDeliveryResults(response, chunk);
        classified.successfulUids.forEach((uid) => successfulUids.add(uid));
        classified.retryUids.forEach((uid) => retryUids.add(uid));
        lastErrorCode ??= classified.lastErrorCode;
      } catch (error) {
        chunk.forEach((token) => retryUids.add(token.uid));
        lastErrorCode ??= notificationProviderErrorCode(error);
        logger.error("Message notification FCM send threw.", {
          ...context,
          tokenCount: chunk.length,
          error,
        });
      }
    }
  }

  for (const entry of recipientEntries) {
    if (successfulUids.has(entry.uid)) {
      recipientResults[entry.uid] = "complete";
    } else if (retryUids.has(entry.uid)) {
      recipientResults[entry.uid] = "pending";
    } else if (recipientResults[entry.uid] === "pending") {
      recipientResults[entry.uid] = "skipped";
    }
  }
  return {recipientResults, ...(lastErrorCode ? {lastErrorCode} : {})};
}

function currentMaintainerIds(place: DocumentSnapshot): Set<string> {
  const maintainers = new Set(
    maintainerIdsOf(place).filter(
      (uid) => typeof uid === "string" && uid.length > 0,
    ),
  );
  const creator = place.get("createdByUserId");
  if (typeof creator === "string" && creator.length > 0) {
    maintainers.add(creator);
  }
  return maintainers;
}

function requireMessageSourceRoute(
  event: NotificationOutboxData,
): {placeId: string} {
  const segments = event.sourcePath.split("/");
  if (segments.length !== 4 || segments[0] !== "places" ||
      segments[2] !== "messages" || segments[3] !== event.entityId) {
    throw new Error("Message notification source path is invalid.");
  }
  return {placeId: segments[1]};
}

function isDeliverableMessage(
  place: DocumentSnapshot,
  message: DocumentSnapshot,
): boolean {
  if (!place.exists || !message.exists || place.get("isArchived") === true) {
    return false;
  }
  const expiresAt = place.get("expiresAt");
  const moderationAction = message.get("moderationAction");
  return expiresAt instanceof Timestamp &&
    expiresAt.toMillis() > Date.now() &&
    (moderationAction === "allow" ||
     moderationAction === "sensitive" ||
     moderationAction === "review") &&
    message.get("isDeleted") !== true &&
    message.get("isVisible") === true &&
    message.get("isPubliclyVisible") === true;
}

async function notificationRecipientEntry(
  sourceFirestore: Firestore,
  uid: string,
  senderId: string,
  isMaintainer: boolean,
): Promise<{
  uid: string;
  enabled: boolean;
  tokens: MyNotesNotificationToken[];
}> {
  if (!isMaintainer || await hasUserBlockBetween(
    sourceFirestore,
    uid,
    senderId,
  )) {
    return {uid, enabled: false, tokens: []};
  }
  const homeAssignment = await sourceFirestore
    .collection("userHomes")
    .doc(uid)
    .get();
  const homeWorld = homeAssignment.get("world");
  if (typeof homeWorld !== "string") {
    return {uid, enabled: false, tokens: []};
  }
  try {
    WORLD_REGISTRY.requireWorld(homeWorld);
  } catch {
    return {uid, enabled: false, tokens: []};
  }
  const userRef = worldContext(homeWorld).firestore
    .collection("users")
    .doc(uid);
  const [user, settings, tokenDocuments] = await Promise.all([
    userRef.get(),
    userRef.collection("notificationSettings").doc("main").get(),
    userRef.collection("fcmTokens").get(),
  ]);
  if (settings.get("myNotesEnabled") !== true) {
    return {uid, enabled: false, tokens: []};
  }
  const showPreview = settings.get("myNotesPreviewEnabled") !== false;
  const locale = notificationLocaleOf(user.get("languagePreference"));
  const tokens = tokenDocuments.docs.flatMap((document) => {
    const token = document.get("token");
    return typeof token === "string" && token.length > 0 ? [{
      uid,
      ref: document.ref,
      token,
      showPreview,
      locale,
    }] : [];
  });
  return {uid, enabled: true, tokens};
}

async function classifyDeliveryResults(
  response: BatchResponse,
  tokens: MyNotesNotificationToken[],
): Promise<{
  successfulUids: Set<string>;
  retryUids: Set<string>;
  lastErrorCode?: string;
}> {
  const successfulUids = new Set<string>();
  const retryUids = new Set<string>();
  const deletions: Promise<unknown>[] = [];
  let lastErrorCode: string | undefined;
  response.responses.forEach((result, index) => {
    const token = tokens[index];
    if (result.success) {
      successfulUids.add(token.uid);
      return;
    }
    const code = result.error?.code ?? "messaging/unknown-error";
    const disposition = classifyFcmError(code);
    if (disposition === "deleteToken") {
      deletions.push(token.ref.delete());
    } else if (disposition === "retry" || disposition === "deploymentFault") {
      retryUids.add(token.uid);
      lastErrorCode ??= code;
    } else {
      logger.error("Message notification payload was rejected.", {code});
    }
  });
  const deletionResults = await Promise.allSettled(deletions);
  if (deletionResults.some((result) => result.status === "rejected")) {
    logger.warn("Could not delete one or more invalid FCM tokens.");
  }
  return {successfulUids, retryUids, ...(lastErrorCode ? {lastErrorCode} : {})};
}

function notificationProviderErrorCode(error: unknown): string {
  if (typeof error === "object" && error !== null && "code" in error) {
    const code = String((error as {code: unknown}).code);
    if (/^[A-Za-z0-9_.:/-]{1,128}$/.test(code)) return code;
  }
  return "fcm-send-error";
}

function resultForRecipients(
  recipients: readonly string[],
  status: NotificationRecipientStatus,
): Record<string, NotificationRecipientStatus> {
  return Object.fromEntries(recipients.map((uid) => [uid, status]));
}
