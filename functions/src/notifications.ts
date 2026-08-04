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
} from "firebase-admin/firestore";
import {BatchResponse, getMessaging} from "firebase-admin/messaging";

import {REGION} from "./constants";
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
 * Sends an actionable push to note maintainers for a public message.
 *
 * @param {string} sourceWorld World that owns the content and delivery event.
 * @param {Firestore} db Source-world Firestore instance.
 * @param {string} placeId Note id.
 * @param {string} messageId Message id.
 * @param {string} senderId User id that posted the message.
 */
export async function sendMyNotesMessageNotifications(
  sourceWorld: string,
  db: Firestore,
  placeId: string,
  messageId: string,
  senderId: string,
): Promise<void> {
  WORLD_REGISTRY.requireWorld(sourceWorld);
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

  const maintainerIds = new Set<string>(
    maintainerIdsOf(placeSnap)
      .filter((value) => typeof value === "string" && value.length > 0),
  );
  const createdBy = placeSnap.get("createdByUserId") as string | undefined;
  if (createdBy) maintainerIds.add(createdBy);
  maintainerIds.delete(senderId);
  if (maintainerIds.size === 0) return;

  const maintainerEntries = await Promise.all(
    [...maintainerIds].map(async (uid) => {
      if (await hasUserBlockBetween(db, uid, senderId)) {
        return {enabled: false, tokens: []};
      }
      const homeAssignment = await db.collection("userHomes").doc(uid).get();
      const homeWorld = homeAssignment.get("world");
      if (typeof homeWorld !== "string") {
        throw new Error(`Notification recipient home is missing: ${uid}.`);
      }
      WORLD_REGISTRY.requireWorld(homeWorld);
      const homeFirestore = worldContext(homeWorld).firestore;
      const userRef = homeFirestore.collection("users").doc(uid);
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

  const enabledMaintainerCount = maintainerEntries.filter(
    (entry) => entry.enabled,
  ).length;
  const tokenEntries = maintainerEntries.flatMap((entry) => entry.tokens);
  if (tokenEntries.length === 0) {
    logger.info(
      "sendMyNotesMessageNotifications: no registered recipient tokens.",
      {
        placeId,
        messageId,
        maintainerCount: maintainerIds.size,
        enabledMaintainerCount,
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
      sourceWorld,
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
            worldId: sourceWorld,
            placeId,
            messageId,
          },
          apns: {
            payload: {
              aps: {
                sound: "default",
                threadId: `world:${sourceWorld}:place:${placeId}`,
              },
            },
          },
          android: {
            priority: "high",
            notification: {
              sound: "default",
              tag: `world:${sourceWorld}:place:${placeId}`,
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
    {sourceWorld},
  );
}
