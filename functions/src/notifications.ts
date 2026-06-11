/* eslint-disable require-jsdoc */
import {createHash} from "crypto";
import {onCall, HttpsError} from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";
import {
  FieldValue,
  Firestore,
  Timestamp,
  getFirestore,
} from "firebase-admin/firestore";
import {getMessaging} from "firebase-admin/messaging";

import {REGION} from "./constants";

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

const VALID_PLATFORMS = new Set([
  "android",
  "ios",
  "macos",
  "web",
  "unknown",
]);

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

function compactBody(placeTitle: unknown): string {
  const title = typeof placeTitle === "string" ? placeTitle.trim() : "";
  if (title.length === 0) return "Your note has a new message.";
  const clipped = title.length > 60 ? `${title.slice(0, 57)}...` : title;
  return `New message on "${clipped}"`;
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
      const settingsRef = db
        .collection("users")
        .doc(uid)
        .collection("notificationSettings")
        .doc("main");
      const tokensRef = db
        .collection("users")
        .doc(uid)
        .collection("fcmTokens");
      const [settingsSnap, tokensSnap] = await Promise.all([
        settingsRef.get(),
        tokensRef.get(),
      ]);
      const enabled = settingsSnap.get("myNotesEnabled") === true;
      if (!enabled) return [];
      return tokensSnap.docs.flatMap((doc) => {
        const token = doc.get("token");
        return typeof token === "string" && token.length > 0 ?
          [{ref: doc.ref, token}] :
          [];
      });
    }),
  );

  const tokenEntries = ownerEntries.flat();
  if (tokenEntries.length === 0) return;

  const body = compactBody(placeSnap.get("title"));
  let sent = 0;
  for (let i = 0; i < tokenEntries.length; i += 500) {
    const chunk = tokenEntries.slice(i, i + 500);
    const response = await getMessaging().sendEachForMulticast({
      tokens: chunk.map((entry) => entry.token),
      notification: {
        title: "World Notes",
        body,
      },
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

    sent += response.successCount;
    await Promise.all(
      response.responses.map(async (result, index) => {
        const code = result.error?.code;
        if (
          code === "messaging/registration-token-not-registered" ||
          code === "messaging/invalid-registration-token"
        ) {
          await chunk[index].ref.delete();
        }
      }),
    );
  }

  logger.info(
    `sendMyNotesMessageNotifications: sent ${sent}/${tokenEntries.length}` +
      ` for places/${placeId}/messages/${messageId}.`,
  );
}
