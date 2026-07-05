/* eslint-disable require-jsdoc */
import {
  DocumentReference,
  FieldValue,
  Timestamp,
  getFirestore,
} from "firebase-admin/firestore";
import {BatchResponse, getMessaging} from "firebase-admin/messaging";
import * as logger from "firebase-functions/logger";

type NoticeCategory =
  "moderation" |
  "report" |
  "ban" |
  "developer" |
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
  pushTitle?: string;
  pushBody?: string;
}

interface NoticePush {
  uid: string;
  noticeId: string;
  title: string;
  body: string;
  severity: NoticeSeverity;
}

const INVALID_FCM_TOKEN_CODES = new Set([
  "messaging/registration-token-not-registered",
  "messaging/invalid-registration-token",
]);

function clippedText(value: string, maxLength: number): string {
  const trimmed = value.replace(/\s+/g, " ").trim();
  if (trimmed.length <= maxLength) return trimmed;
  return `${trimmed.slice(0, Math.max(0, maxLength - 3)).trimEnd()}...`;
}

function logNoticePushFailures(
  response: BatchResponse,
  tokenCount: number,
  notice: NoticePush,
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
  logger.warn("sendNoticePush: FCM send failures.", {
    uid: notice.uid,
    noticeId: notice.noticeId,
    tokenCount,
    successCount: response.successCount,
    failureCount: response.failureCount,
    errorCodeCounts,
  });
}

async function deleteInvalidFcmTokens(
  response: BatchResponse,
  tokenRefs: DocumentReference[],
): Promise<void> {
  await Promise.all(
    response.responses.map(async (result, index) => {
      const code = result.error?.code;
      if (code != null && INVALID_FCM_TOKEN_CODES.has(code)) {
        await tokenRefs[index].delete();
      }
    }),
  );
}

export async function createUserNotice(
  uid: string,
  input: CreateUserNoticeInput,
): Promise<string> {
  const noticeRef = getFirestore()
    .collection("users")
    .doc(uid)
    .collection("notices")
    .doc();
  const title = clippedText(input.title, 120);
  const body = clippedText(input.body, 2000);
  await noticeRef.set({
    category: input.category,
    severity: input.severity,
    title,
    body,
    action: input.action ?? null,
    sourceType: input.sourceType ?? null,
    sourceId: input.sourceId ?? null,
    createdAt: FieldValue.serverTimestamp(),
    readAt: null,
  });

  if (input.push === true) {
    await sendNoticePush({
      uid,
      noticeId: noticeRef.id,
      title: input.pushTitle ?? title,
      body: input.pushBody ?? body,
      severity: input.severity,
    });
  }
  return noticeRef.id;
}

export async function sendNoticePush(notice: NoticePush): Promise<void> {
  const tokenSnap = await getFirestore()
    .collection("users")
    .doc(notice.uid)
    .collection("fcmTokens")
    .get();
  const tokens: string[] = [];
  const tokenRefs: DocumentReference[] = [];
  for (const doc of tokenSnap.docs) {
    const token = doc.get("token");
    if (typeof token === "string" && token.trim().length > 0) {
      tokens.push(token.trim());
      tokenRefs.push(doc.ref);
    }
  }
  if (tokens.length === 0) return;

  const response = await getMessaging().sendEachForMulticast({
    tokens,
    notification: {
      title: clippedText(notice.title, 120),
      body: clippedText(notice.body, 240),
    },
    data: {
      type: "notice",
      noticeId: notice.noticeId,
      severity: notice.severity,
    },
    apns: {
      payload: {
        aps: {
          sound: notice.severity === "critical" ? "default" : undefined,
        },
      },
    },
  });
  logNoticePushFailures(response, tokens.length, notice);
  await deleteInvalidFcmTokens(response, tokenRefs);
}

export function timestampFromFutureHours(hours: number): Timestamp {
  return Timestamp.fromMillis(Date.now() + hours * 60 * 60 * 1000);
}
