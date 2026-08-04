/* eslint-disable require-jsdoc */
import {
  DocumentReference,
  Firestore,
  Timestamp,
  Transaction,
} from "firebase-admin/firestore";
import {BatchResponse, getMessaging} from "firebase-admin/messaging";
import * as logger from "firebase-functions/logger";

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

type NoticeCategory =
  "moderation" |
  "report" |
  "ban" |
  "developer" |
  "social" |
  "system";

type NoticeSeverity = "info" | "warning" | "critical";

export interface NoticeAction {
  type: "route";
  route: string;
  params?: Record<string, unknown>;
}

export interface CreateUserNoticeInput {
  category: NoticeCategory;
  severity: NoticeSeverity;
  title: string;
  body: string;
  action?: NoticeAction;
  sourceType?: string;
  sourceId?: string;
  push?: boolean;
}

interface NoticeToken {
  readonly ref: DocumentReference;
  readonly token: string;
}

export const USER_NOTICE_NOTIFICATION_EVENT = "notifyUserNotice";
const NOTICE_NOTIFICATION_LIFETIME_MILLIS = 24 * 60 * 60 * 1000;
const FCM_MULTICAST_LIMIT = 500;

function clippedText(value: string, maxLength: number): string {
  const trimmed = value.replace(/\s+/g, " ").trim();
  if (trimmed.length <= maxLength) return trimmed;
  return `${trimmed.slice(0, Math.max(0, maxLength - 3)).trimEnd()}...`;
}

/**
 * Creates a home-authoritative notice and optional durable push intent.
 *
 * @param {Firestore} sourceFirestore World where the notice originated.
 * @param {string} uid Recipient user ID.
 * @param {CreateUserNoticeInput} input Trusted notice content and behavior.
 * @return {Promise<string>} Home-world notice document ID.
 */
export async function createUserNotice(
  sourceFirestore: Firestore,
  uid: string,
  input: CreateUserNoticeInput,
): Promise<string> {
  const sourceWorld = worldIdForFirestore(sourceFirestore);
  const homeAssignment = await sourceFirestore
    .collection("userHomes")
    .doc(uid)
    .get();
  const homeWorldValue = homeAssignment.get("world");
  if (!homeAssignment.exists || typeof homeWorldValue !== "string") {
    throw new Error(`Notice recipient home is missing: ${uid}.`);
  }
  const homeWorld = WORLD_REGISTRY.requireWorld(homeWorldValue).worldId;
  const homeFirestore = worldContext(homeWorld).firestore;
  const noticeRef = homeFirestore
    .collection("users")
    .doc(uid)
    .collection("notices")
    .doc();
  const createdAt = Timestamp.now();
  const title = clippedText(input.title, 120);
  const body = clippedText(input.body, 2000);

  await homeFirestore.runTransaction(async (transaction) => {
    transaction.create(noticeRef, {
      category: input.category,
      severity: input.severity,
      title,
      body,
      action: input.action ?? null,
      sourceType: input.sourceType ?? null,
      sourceId: input.sourceId ?? null,
      createdAt,
      readAt: null,
    });
    if (input.push === true) {
      enqueueUserNoticeNotification(transaction, homeFirestore, {
        homeWorld,
        sourceWorld,
        uid,
        noticeId: noticeRef.id,
        createdAt,
      });
    }
  });
  return noticeRef.id;
}

/**
 * Adds one notice Push event to its home-world transaction.
 *
 * @param {Transaction} transaction Home-world notice transaction.
 * @param {Firestore} firestore Recipient's home Firestore database.
 * @param {object} input Trusted notice route and creation time.
 * @return {string} Deterministic notification event ID.
 */
export function enqueueUserNoticeNotification(
  transaction: Transaction,
  firestore: Firestore,
  input: Readonly<{
    homeWorld: string;
    sourceWorld: string;
    uid: string;
    noticeId: string;
    createdAt: Timestamp;
  }>,
): string {
  WORLD_REGISTRY.requireWorld(input.homeWorld);
  WORLD_REGISTRY.requireWorld(input.sourceWorld);
  const identity = {
    sourceEventId: input.noticeId,
    ownerWorld: input.homeWorld,
    eventType: USER_NOTICE_NOTIFICATION_EVENT,
    partition: input.uid,
  };
  const eventId = notificationEventId(identity);
  const data = newNotificationOutboxData({
    ...identity,
    eventId,
    sourceWorld: input.sourceWorld,
    entityType: "notice",
    entityId: input.noticeId,
    sourcePath: `users/${input.uid}/notices/${input.noticeId}`,
    recipientUids: [input.uid],
    expiresAt: Timestamp.fromMillis(
      input.createdAt.toMillis() + NOTICE_NOTIFICATION_LIFETIME_MILLIS,
    ),
  }, input.createdAt);
  transaction.create(
    firestore.collection("notificationOutbox").doc(eventId),
    {...data},
  );
  return eventId;
}

/** Delivers one home-owned notice through its registered device tokens. */
export const userNoticeNotificationHandler: NotificationDeliveryHandler = {
  eventType: USER_NOTICE_NOTIFICATION_EVENT,
  deliver: deliverUserNoticeNotification,
};

async function deliverUserNoticeNotification(
  {firestore, event}: Readonly<{
    firestore: Firestore;
    event: NotificationOutboxData;
  }>,
): Promise<NotificationDeliveryResult> {
  const pending = event.recipientUids.filter(
    (uid) => event.recipientResults[uid] === "pending",
  );
  if (event.eventType !== USER_NOTICE_NOTIFICATION_EVENT ||
      event.entityType !== "notice" || pending.length !== 1) {
    throw new Error("Notice notification event is invalid.");
  }
  const uid = pending[0];
  requireNoticeSourcePath(event, uid);
  const userRef = firestore.collection("users").doc(uid);
  const [homeAssignment, notice, tokenDocuments] = await Promise.all([
    firestore.collection("userHomes").doc(uid).get(),
    firestore.doc(event.sourcePath).get(),
    userRef.collection("fcmTokens").get(),
  ]);
  if (!homeAssignment.exists ||
      homeAssignment.get("world") !== event.ownerWorld) {
    throw new Error("Notice notification used the wrong home authority.");
  }
  if (!notice.exists) {
    return {recipientResults: {[uid]: "skipped"}};
  }
  const severity = noticeSeverity(notice.get("severity"));
  const title = notice.get("title");
  const body = notice.get("body");
  if (typeof title !== "string" || typeof body !== "string") {
    throw new Error("Notice notification content is invalid.");
  }
  const tokens = tokenDocuments.docs.flatMap((document) => {
    const token = document.get("token");
    return typeof token === "string" && token.length > 0 ? [{
      ref: document.ref,
      token,
    }] : [];
  });
  if (tokens.length === 0) {
    return {recipientResults: {[uid]: "skipped"}};
  }

  let delivered = false;
  let retry = false;
  let lastErrorCode: string | undefined;
  for (let index = 0; index < tokens.length; index += FCM_MULTICAST_LIMIT) {
    const chunk = tokens.slice(index, index + FCM_MULTICAST_LIMIT);
    try {
      const response = await getMessaging().sendEachForMulticast({
        tokens: chunk.map((entry) => entry.token),
        notification: {
          title: clippedText(title, 120),
          body: clippedText(body, 240),
        },
        data: {
          type: "notice",
          eventId: event.eventId,
          worldId: event.ownerWorld,
          noticeId: event.entityId,
          severity,
        },
        apns: {
          headers: {"apns-collapse-id": event.eventId},
          payload: {aps: {
            sound: severity === "critical" ? "default" : undefined,
          }},
        },
        android: {
          priority: severity === "critical" ? "high" : "normal",
          notification: {tag: `notification:${event.eventId}`},
        },
      });
      const outcome = await summarizeNoticeDeliveryResults(response, chunk);
      delivered ||= outcome.delivered;
      retry ||= outcome.retry;
      lastErrorCode ??= outcome.lastErrorCode;
      logNoticePushFailures(response, uid, event.entityId, chunk.length);
    } catch (error) {
      retry = true;
      lastErrorCode ??= providerErrorCode(error);
      logger.error("Notice notification FCM send threw.", {
        uid,
        noticeId: event.entityId,
        tokenCount: chunk.length,
        error,
      });
    }
  }

  const status: NotificationRecipientStatus = delivered ?
    "complete" : retry ? "pending" : "skipped";
  return {
    recipientResults: {[uid]: status},
    ...(lastErrorCode ? {lastErrorCode} : {}),
  };
}

async function summarizeNoticeDeliveryResults(
  response: BatchResponse,
  tokens: readonly NoticeToken[],
): Promise<{
  delivered: boolean;
  retry: boolean;
  lastErrorCode?: string;
}> {
  let delivered = false;
  let retry = false;
  let lastErrorCode: string | undefined;
  const deletions: Promise<unknown>[] = [];
  response.responses.forEach((result, index) => {
    if (result.success) {
      delivered = true;
      return;
    }
    const code = result.error?.code ?? "messaging/unknown-error";
    const disposition = classifyFcmError(code);
    if (disposition === "deleteToken") {
      deletions.push(tokens[index].ref.delete());
    } else if (disposition === "retry" || disposition === "deploymentFault") {
      retry = true;
      lastErrorCode ??= code;
    } else {
      logger.error("Notice notification payload was rejected.", {code});
    }
  });
  const deletionResults = await Promise.allSettled(deletions);
  if (deletionResults.some((result) => result.status === "rejected")) {
    logger.warn("Could not delete one or more invalid notice FCM tokens.");
  }
  return {delivered, retry, ...(lastErrorCode ? {lastErrorCode} : {})};
}

function requireNoticeSourcePath(
  event: NotificationOutboxData,
  uid: string,
): void {
  const segments = event.sourcePath.split("/");
  if (segments.length !== 4 || segments[0] !== "users" ||
      segments[1] !== uid || segments[2] !== "notices" ||
      segments[3] !== event.entityId) {
    throw new Error("Notice notification source path is invalid.");
  }
}

function noticeSeverity(value: unknown): NoticeSeverity {
  if (value !== "info" && value !== "warning" && value !== "critical") {
    throw new Error("Notice severity is invalid.");
  }
  return value;
}

function worldIdForFirestore(firestore: Firestore): string {
  const world = WORLD_REGISTRY.catalog.worlds.find(
    (candidate) => candidate.databaseId === firestore.databaseId,
  );
  if (world === undefined) {
    throw new Error("Notice source database is not in the world catalog.");
  }
  return world.worldId;
}

function providerErrorCode(error: unknown): string {
  if (typeof error === "object" && error !== null && "code" in error) {
    const code = String((error as {code: unknown}).code);
    if (/^[A-Za-z0-9_.:/-]{1,128}$/.test(code)) return code;
  }
  return "fcm-send-error";
}

function logNoticePushFailures(
  response: BatchResponse,
  uid: string,
  noticeId: string,
  tokenCount: number,
): void {
  if (response.failureCount === 0) return;
  const errorCodeCounts = response.responses.reduce<Record<string, number>>(
    (counts, result) => {
      const code = result.error?.code;
      if (code) counts[code] = (counts[code] ?? 0) + 1;
      return counts;
    },
    {},
  );
  logger.warn("Notice notification FCM failures.", {
    uid,
    noticeId,
    tokenCount,
    successCount: response.successCount,
    failureCount: response.failureCount,
    errorCodeCounts,
  });
}

export function timestampFromFutureHours(hours: number): Timestamp {
  return Timestamp.fromMillis(Date.now() + hours * 60 * 60 * 1000);
}
