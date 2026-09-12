/* eslint-disable require-jsdoc */

import {createHash} from "node:crypto";
import {
  DocumentSnapshot,
  FieldPath,
  Firestore,
  Query,
  Timestamp,
  Transaction,
} from "firebase-admin/firestore";

import {
  accountSafetyDenialReason,
  parseAccountSafetyProjection,
} from "./accountSafety";
import {hasValidMembership, isPublishedReadablePlace} from "./likeHelpers";
import {canMaintainNote} from "./noteMaintenance";
import {
  newNotificationOutboxData,
  notificationEventId,
  NotificationDeliveryHandler,
  NotificationDeliveryResult,
  NotificationOutboxData,
  NotificationRecipientStatus,
} from "./notificationOutbox";
import {createUserNotice} from "./notices";
import {HttpsError, onCall} from "./platform/worldCallable";
import {worldContext} from "./platform/worldContext";
import {WORLD_REGISTRY} from "./platform/worldRegistry";
import {
  findUserIdsWithBlockRelationshipToViewer,
  hasUserBlockBetween,
  hasUserBlockBetweenInTransaction,
} from "./userBlocks";

interface ListMentionCandidatesData {
  placeId?: unknown;
  query?: unknown;
  limit?: unknown;
}

export interface MentionSnapshot {
  readonly userId: string;
  readonly displayName: string;
}

interface ParticipantSnapshot {
  readonly userId: string;
  readonly displayName: string;
  readonly displayNameSearchKey: string;
  readonly photoUrl: string | null;
  readonly firstParticipatedAt: Timestamp;
  readonly lastParticipatedAt: Timestamp;
}

export type NotificationLocale = "en" | "ja" | "ko" | "zh-Hans" | "zh-Hant";

interface SearchBucket {
  tokens: number;
  lastRefillAt: number;
}

const MAX_UID_LENGTH = 128;
const MAX_DISPLAY_NAME_LENGTH = 20;
const MAX_MENTION_RECIPIENTS = 3;
const MAX_CANDIDATE_LIMIT = 20;
const MIN_CANDIDATE_SCAN = 40;
const CANDIDATE_SCAN_MULTIPLIER = 5;
const MAX_CANDIDATE_SCAN = 100;
const SEARCH_RATE_LIMIT_CAPACITY = 30;
const SEARCH_RATE_LIMIT_REFILL_PER_SECOND = 1;
const MENTION_NOTIFICATION_LIFETIME_MILLIS = 24 * 60 * 60 * 1000;
const FIRESTORE_PREFIX_RANGE_END = "\uf8ff";
const RECIPIENT_STATUS_PENDING: NotificationRecipientStatus = "pending";
const RECIPIENT_STATUS_SKIPPED: NotificationRecipientStatus = "skipped";
const RECIPIENT_STATUS_COMPLETE: NotificationRecipientStatus = "complete";
export const MESSAGE_MENTION_NOTIFICATION_EVENT = "notifyMessageMention";
const searchBuckets = new Map<string, SearchBucket>();

const COPY: Record<NotificationLocale, {
  title: (senderName: string) => string;
  body: string;
}> = {
  "en": {
    title: (senderName) => `${senderName} mentioned you`,
    body: "View the note location on the map and move closer to read it.",
  },
  "ja": {
    title: (senderName) => `${senderName}さんがあなたをメンションしました`,
    body: "マップでノートの場所を確認し、近づいて内容を開いてください。",
  },
  "ko": {
    title: (senderName) => `${senderName}님이 회원님을 멘션했습니다`,
    body: "지도에서 노트 위치를 확인하고 가까이 이동한 후 내용을 열어 보세요.",
  },
  "zh-Hans": {
    title: (senderName) => `${senderName} 提及了你`,
    body: "请在地图上查看笔记位置，并靠近后打开内容。",
  },
  "zh-Hant": {
    title: (senderName) => `${senderName} 提及了你`,
    body: "請在地圖上查看筆記位置，並靠近後開啟內容。",
  },
};

export function normalizeMentionSearchText(value: string): string {
  return value
    .normalize("NFKC")
    .toLocaleLowerCase("und")
    // U+30A1-U+30F6 is Katakana ァ-ヶ. The matching Hiragana code points
    // U+3041-U+3096 are exactly 0x60 earlier, so both scripts search alike.
    .replace(/[\u30a1-\u30f6]/g, (character) =>
      String.fromCharCode(character.charCodeAt(0) - 0x60))
    .replace(/\s+/g, " ")
    .trim();
}

export function mentionSearchBigrams(value: string): string[] {
  const characters = Array.from(normalizeMentionSearchText(value));
  const grams = new Set<string>();
  for (let index = 0; index + 1 < characters.length; index += 1) {
    grams.add(`${characters[index]}${characters[index + 1]}`);
  }
  return [...grams].sort();
}

export function parseMentionUserIds(
  value: unknown,
  senderId: string,
): string[] {
  if (value == null) return [];
  if (!Array.isArray(value) || value.length > MAX_MENTION_RECIPIENTS) {
    throw invalidMentions();
  }
  const userIds = value.map((entry) => {
    if (typeof entry !== "string" ||
        entry.length === 0 || entry.length > MAX_UID_LENGTH ||
        entry.includes("/")) {
      throw invalidMentions();
    }
    return entry;
  });
  if (new Set(userIds).size !== userIds.length || userIds.includes(senderId)) {
    throw invalidMentions();
  }
  return userIds;
}

export function mentionUserIdsFromMessage(message: DocumentSnapshot): string[] {
  const value = message.get("mentions");
  if (!Array.isArray(value) || value.length > MAX_MENTION_RECIPIENTS) return [];
  const ids: string[] = [];
  for (const entry of value) {
    if (typeof entry !== "object" || entry === null || Array.isArray(entry)) {
      return [];
    }
    const userId = (entry as Record<string, unknown>).userId;
    if (typeof userId !== "string" || userId.length === 0) return [];
    ids.push(userId);
  }
  return new Set(ids).size === ids.length ? ids : [];
}

export async function validateMentionTargetsInTransaction(
  transaction: Transaction,
  firestore: Firestore,
  place: DocumentSnapshot,
  senderId: string,
  userIds: readonly string[],
  now: Timestamp,
): Promise<MentionSnapshot[]> {
  if (userIds.length === 0) return [];
  const placeRef = place.ref;
  const mentions: MentionSnapshot[] = [];
  for (const userId of userIds) {
    const participantRef = placeRef.collection("participants").doc(userId);
    const administratorRef = placeRef.collection("administrators").doc(userId);
    const memberRef = placeRef.collection("members").doc(userId);
    const profileRef = firestore.collection("publicProfiles").doc(userId);
    const safetyRef = firestore.collection("accountSafety").doc(userId);
    const [participant, administrator, member, profile, safety] =
      await Promise.all([
        transaction.get(participantRef),
        transaction.get(administratorRef),
        transaction.get(memberRef),
        transaction.get(profileRef),
        transaction.get(safetyRef),
      ]);
    if (!participant.exists || participant.get("userId") !== userId ||
        !profile.exists ||
        !recipientCanAccess(place, administrator, member, userId) ||
        await hasUserBlockBetweenInTransaction(
          transaction, firestore, senderId, userId,
        ) || !accountMayReceiveMention(safety, now)) {
      throw invalidMentions();
    }
    const displayName = profile.get("displayName");
    if (typeof displayName !== "string" || displayName.length === 0 ||
        displayName.length > MAX_DISPLAY_NAME_LENGTH) {
      throw invalidMentions();
    }
    mentions.push(Object.freeze({userId, displayName}));
  }
  return mentions;
}

export async function upsertMessageParticipant(
  transaction: Transaction,
  message: DocumentSnapshot,
  updatedAt: Timestamp,
): Promise<void> {
  const placeRef = message.ref.parent.parent;
  const userId = message.get("userId");
  const displayName = message.get("userName");
  const publishAt = message.get("publishAt");
  if (placeRef === null || typeof userId !== "string" || userId.length === 0 ||
      typeof displayName !== "string" || displayName.length === 0 ||
      displayName.length > MAX_DISPLAY_NAME_LENGTH ||
      !(publishAt instanceof Timestamp)) {
    throw new Error("Published message participant fields are invalid.");
  }
  const participantRef = placeRef.collection("participants").doc(userId);
  const existing = await transaction.get(participantRef);
  const previousLast = existing.exists ?
    existing.get("lastParticipatedAt") : undefined;
  if (previousLast instanceof Timestamp &&
      previousLast.toMillis() > publishAt.toMillis()) {
    return;
  }
  const displayNameSearchKey = normalizeMentionSearchText(displayName);
  transaction.set(participantRef, {
    userId,
    displayName,
    displayNameSearchKey,
    searchBigrams: mentionSearchBigrams(displayNameSearchKey),
    photoUrl: stringOrNull(message.get("userPhotoUrl")),
    firstParticipatedAt: existing.exists ?
      existing.get("firstParticipatedAt") : publishAt,
    lastParticipatedAt: publishAt,
    updatedAt,
  });
}

export const listMentionCandidates = onCall<ListMentionCandidatesData>(
  {auditAction: "mention.candidates.list", enforceAppCheck: true},
  async (request, world) => {
    const uid = request.auth?.uid;
    if (!uid) throw new HttpsError("unauthenticated", "Sign in required.");
    consumeMentionSearchRateLimit(uid);
    const placeId = requiredId(request.data?.placeId, "placeId");
    const queryText = request.data?.query == null ? "" : request.data.query;
    if (typeof queryText !== "string" || queryText.length > 40) {
      throw new HttpsError("invalid-argument", "Invalid mention query.");
    }
    const requestedLimit = request.data?.limit ?? MAX_CANDIDATE_LIMIT;
    if (typeof requestedLimit !== "number" ||
        !Number.isInteger(requestedLimit) || requestedLimit < 1 ||
        requestedLimit > MAX_CANDIDATE_LIMIT) {
      throw new HttpsError("invalid-argument", "Invalid mention limit.");
    }

    const firestore = world.firestore;
    const placeRef = firestore.collection("places").doc(placeId);
    const [place, administrator, member] = await Promise.all([
      placeRef.get(),
      placeRef.collection("administrators").doc(uid).get(),
      placeRef.collection("members").doc(uid).get(),
    ]);
    const now = Timestamp.now();
    if (!isPublishedReadablePlace(place, now.toMillis()) ||
        !recipientCanAccess(place, administrator, member, uid)) {
      throw new HttpsError("permission-denied", "You cannot access this note.");
    }
    const creator = place.get("createdByUserId");
    if (typeof creator !== "string" ||
        await hasUserBlockBetween(firestore, uid, creator)) {
      throw new HttpsError("permission-denied", "You cannot access this note.");
    }

    const normalized = normalizeMentionSearchText(queryText);
    // Fetch extra rows because block, safety, and access checks below can
    // discard candidates: at least 40, normally 5x the requested result,
    // and never more than 100.
    const scanLimit = Math.min(
      MAX_CANDIDATE_SCAN,
      Math.max(
        MIN_CANDIDATE_SCAN,
        requestedLimit * CANDIDATE_SCAN_MULTIPLIER,
      ),
    );
    let candidateQuery: Query = placeRef.collection("participants");
    if (normalized.length === 0) {
      candidateQuery = candidateQuery
        .orderBy("lastParticipatedAt", "desc")
        .orderBy(FieldPath.documentId())
        .limit(scanLimit);
    } else if (Array.from(normalized).length === 1) {
      candidateQuery = candidateQuery
        .orderBy("displayNameSearchKey")
        .orderBy(FieldPath.documentId())
        .startAt(normalized)
        // U+F8FF is a high private-use code point. Appending it forms the
        // inclusive upper bound for ordinary strings sharing this prefix.
        .endAt(`${normalized}${FIRESTORE_PREFIX_RANGE_END}`)
        .limit(scanLimit);
    } else {
      candidateQuery = candidateQuery
        .where("searchBigrams", "array-contains",
          mentionSearchBigrams(normalized)[0])
        .orderBy("lastParticipatedAt", "desc")
        .orderBy(FieldPath.documentId())
        .limit(scanLimit);
    }
    const snapshot = await candidateQuery.get();
    const parsed: Array<{
      document: DocumentSnapshot;
      participant: ParticipantSnapshot;
    }> = [];
    for (const document of snapshot.docs) {
      try {
        const participant = parseParticipant(document);
        if (participant.userId === uid ||
            (normalized.length > 0 &&
             !participant.displayNameSearchKey.includes(normalized))) {
          continue;
        }
        parsed.push({document, participant});
      } catch {
        continue;
      }
    }
    const blocked = await findUserIdsWithBlockRelationshipToViewer(
      firestore,
      uid,
      parsed.map((entry) => entry.participant.userId),
    );
    const filtered = parsed.filter(
      (entry) => !blocked.has(entry.participant.userId),
    );
    const relatedSnapshots = await Promise.all(filtered.map(async (entry) => {
      const candidateUid = entry.participant.userId;
      const [profile, safety, candidateAdministrator, candidateMember] =
        await Promise.all([
          firestore.collection("publicProfiles").doc(candidateUid).get(),
          firestore.collection("accountSafety").doc(candidateUid).get(),
          placeRef.collection("administrators").doc(candidateUid).get(),
          placeRef.collection("members").doc(candidateUid).get(),
        ]);
      return {entry, profile, safety, candidateAdministrator, candidateMember};
    }));
    const candidates: Array<{
      userId: string;
      displayName: string;
      photoUrl: string | null;
    }> = [];
    for (const candidate of relatedSnapshots) {
      const userId = candidate.entry.participant.userId;
      const displayName = candidate.profile.exists ?
        candidate.profile.get("displayName") : undefined;
      if (typeof displayName !== "string" ||
          displayName.length === 0 ||
          !accountMayReceiveMention(candidate.safety, now) ||
          !recipientCanAccess(
            place,
            candidate.candidateAdministrator,
            candidate.candidateMember,
            userId,
          )) {
        continue;
      }
      candidates.push({
        userId,
        displayName,
        photoUrl: stringOrNull(candidate.profile.get("photoUrl")),
      });
      if (candidates.length === requestedLimit) break;
    }
    return {candidates};
  },
);

export function enqueueMessageMentionNotification(
  transaction: Transaction,
  firestore: Firestore,
  input: Readonly<{
    sourceWorld: string;
    place: DocumentSnapshot;
    message: DocumentSnapshot;
    createdAt: Timestamp;
  }>,
): string | null {
  WORLD_REGISTRY.requireWorld(input.sourceWorld);
  const senderId = input.message.get("userId");
  if (typeof senderId !== "string" || senderId.length === 0) {
    throw new Error("Mention notification sender is invalid.");
  }
  const recipients = mentionUserIdsFromMessage(input.message)
    .filter((uid) => uid !== senderId)
    .sort();
  if (recipients.length === 0) return null;
  const identity = messageMentionNotificationIdentity(
    input.sourceWorld,
    input.place.id,
    input.message.id,
  );
  const eventId = notificationEventId(identity);
  const data = newNotificationOutboxData({
    ...identity,
    eventId,
    sourceWorld: input.sourceWorld,
    entityType: "message",
    entityId: input.message.id,
    sourcePath: `places/${input.place.id}/messages/${input.message.id}`,
    recipientUids: recipients,
    expiresAt: Timestamp.fromMillis(
      input.createdAt.toMillis() + MENTION_NOTIFICATION_LIFETIME_MILLIS,
    ),
  }, input.createdAt);
  transaction.create(firestore.collection("notificationOutbox").doc(eventId), {
    ...data,
  });
  return eventId;
}

export function messageMentionNotificationEventId(
  sourceWorld: string,
  placeId: string,
  messageId: string,
): string {
  return notificationEventId(messageMentionNotificationIdentity(
    sourceWorld,
    placeId,
    messageId,
  ));
}

function messageMentionNotificationIdentity(
  sourceWorld: string,
  placeId: string,
  messageId: string,
) {
  return {
    sourceEventId: messageId,
    ownerWorld: sourceWorld,
    eventType: MESSAGE_MENTION_NOTIFICATION_EVENT,
    partition: createHash("sha256").update(placeId).digest("hex"),
  };
}

export const messageMentionNotificationHandler: NotificationDeliveryHandler = {
  eventType: MESSAGE_MENTION_NOTIFICATION_EVENT,
  deliver: deliverMessageMentionNotification,
};

async function deliverMessageMentionNotification(
  {firestore, event}: Readonly<{
    firestore: Firestore;
    event: NotificationOutboxData;
  }>,
): Promise<NotificationDeliveryResult> {
  if (event.ownerWorld !== event.sourceWorld ||
      event.eventType !== MESSAGE_MENTION_NOTIFICATION_EVENT ||
      event.entityType !== "message") {
    throw new Error("Mention notification event route is invalid.");
  }
  const placeId = requireMentionSourceRoute(event);
  const placeRef = firestore.collection("places").doc(placeId);
  const [place, message] = await Promise.all([
    placeRef.get(),
    firestore.doc(event.sourcePath).get(),
  ]);
  const pending = event.recipientUids.filter(
    (uid) => event.recipientResults[uid] === RECIPIENT_STATUS_PENDING,
  );
  if (!isDeliverableMention(place, message)) {
    return {recipientResults: statuses(pending, RECIPIENT_STATUS_SKIPPED)};
  }
  const senderId = message.get("userId");
  const senderName = message.get("userName");
  if (typeof senderId !== "string" || typeof senderName !== "string") {
    throw new Error("Mention notification sender is invalid.");
  }
  const mentions = new Set(mentionUserIdsFromMessage(message));
  const results = await Promise.allSettled(pending.map(async (uid) => {
    if (!mentions.has(uid) || uid === senderId ||
        !await recipientMayReceive(firestore, place, uid, senderId)) {
      return {uid, status: RECIPIENT_STATUS_SKIPPED};
    }
    const preference = await mentionPreference(firestore, uid);
    if (preference === null) {
      return {uid, status: RECIPIENT_STATUS_SKIPPED};
    }
    const location = requirePlaceLocation(place);
    const copy = mentionNotificationCopy(preference.locale, senderName);
    await createUserNotice(firestore, uid, {
      noticeId: event.eventId,
      category: "mention",
      severity: "info",
      title: copy.title,
      body: copy.body,
      action: {
        type: "route",
        route: "mapNote",
        params: {
          worldId: event.sourceWorld,
          placeId,
          messageId: message.id,
          latitude: location.latitude,
          longitude: location.longitude,
        },
      },
      sourceType: "messageMention",
      sourceId: senderId,
      push: preference.pushEnabled,
    });
    return {uid, status: RECIPIENT_STATUS_COMPLETE};
  }));
  const recipientResults: Record<string, NotificationRecipientStatus> = {};
  let lastErrorCode: string | undefined;
  results.forEach((result, index) => {
    const uid = pending[index];
    if (result.status === "fulfilled") {
      recipientResults[uid] = result.value.status;
    } else {
      recipientResults[uid] = RECIPIENT_STATUS_PENDING;
      lastErrorCode ??= providerErrorCode(result.reason);
    }
  });
  return {recipientResults, ...(lastErrorCode ? {lastErrorCode} : {})};
}

function parseParticipant(document: DocumentSnapshot): ParticipantSnapshot {
  const data = document.data();
  if (!document.exists || data === undefined ||
      Object.keys(data).some((field) => ![
        "userId", "displayName", "displayNameSearchKey", "searchBigrams",
        "photoUrl", "firstParticipatedAt", "lastParticipatedAt", "updatedAt",
      ].includes(field))) {
    throw new Error("Mention participant is invalid.");
  }
  const userId = data.userId;
  const displayName = data.displayName;
  const displayNameSearchKey = data.displayNameSearchKey;
  const photoUrl = data.photoUrl;
  const firstParticipatedAt = data.firstParticipatedAt;
  const lastParticipatedAt = data.lastParticipatedAt;
  if (typeof userId !== "string" || userId !== document.id ||
      typeof displayName !== "string" || displayName.length === 0 ||
      typeof displayNameSearchKey !== "string" ||
      !Array.isArray(data.searchBigrams) ||
      data.searchBigrams.some((gram) => typeof gram !== "string") ||
      (photoUrl !== null && typeof photoUrl !== "string") ||
      !(firstParticipatedAt instanceof Timestamp) ||
      !(lastParticipatedAt instanceof Timestamp) ||
      !(data.updatedAt instanceof Timestamp)) {
    throw new Error("Mention participant is invalid.");
  }
  return {
    userId,
    displayName,
    displayNameSearchKey,
    photoUrl,
    firstParticipatedAt,
    lastParticipatedAt,
  };
}

function recipientCanAccess(
  place: DocumentSnapshot,
  administrator: DocumentSnapshot,
  member: DocumentSnapshot,
  uid: string,
): boolean {
  if (!place.exists) return false;
  if (place.get("visibility") !== "private") return true;
  return canMaintainNote(place, administrator, uid) ||
    hasValidMembership(place, member);
}

function accountMayReceiveMention(
  safety: DocumentSnapshot,
  now: Timestamp,
): boolean {
  try {
    return accountSafetyDenialReason(
      parseAccountSafetyProjection(safety),
      "participation",
      now,
    ) === null;
  } catch {
    return false;
  }
}

async function recipientMayReceive(
  firestore: Firestore,
  place: DocumentSnapshot,
  uid: string,
  senderId: string,
): Promise<boolean> {
  if (await hasUserBlockBetween(firestore, uid, senderId)) return false;
  const placeRef = place.ref;
  const [profile, safety, administrator, member] = await Promise.all([
    firestore.collection("publicProfiles").doc(uid).get(),
    firestore.collection("accountSafety").doc(uid).get(),
    placeRef.collection("administrators").doc(uid).get(),
    placeRef.collection("members").doc(uid).get(),
  ]);
  return profile.exists && accountMayReceiveMention(safety, Timestamp.now()) &&
    recipientCanAccess(place, administrator, member, uid);
}

async function mentionPreference(
  sourceFirestore: Firestore,
  uid: string,
): Promise<{locale: NotificationLocale; pushEnabled: boolean} | null> {
  const home = await sourceFirestore.collection("userHomes").doc(uid).get();
  if (!home.exists) return null;
  const homeWorld = home.get("world");
  if (typeof homeWorld !== "string") return null;
  try {
    WORLD_REGISTRY.requireWorld(homeWorld);
  } catch {
    return null;
  }
  const userRef = worldContext(homeWorld).firestore
    .collection("users").doc(uid);
  const [user, settings] = await Promise.all([
    userRef.get(),
    userRef.collection("notificationSettings").doc("main").get(),
  ]);
  if (!user.exists) return null;
  return {
    locale: mentionNotificationLocaleOf(user.get("languagePreference")),
    pushEnabled: settings.get("mentionsEnabled") === true,
  };
}

export function mentionNotificationLocaleOf(
  value: unknown,
): NotificationLocale {
  if (typeof value !== "string") return "en";
  switch (value.trim().replace(/_/g, "-").toLowerCase()) {
  case "ja":
    return "ja";
  case "ko":
    return "ko";
  case "zh-hans":
    return "zh-Hans";
  case "zh-hant":
    return "zh-Hant";
  default:
    // "system" has no device locale on the server, so English is stable.
    return "en";
  }
}

export function mentionNotificationCopy(
  locale: NotificationLocale,
  senderName: string,
): {title: string; body: string} {
  const copy = COPY[locale];
  return {title: copy.title(senderName), body: copy.body};
}

function isDeliverableMention(
  place: DocumentSnapshot,
  message: DocumentSnapshot,
): boolean {
  if (!isPublishedReadablePlace(place, Date.now()) || !message.exists) {
    return false;
  }
  const moderationAction = message.get("moderationAction");
  return (moderationAction === "allow" ||
          moderationAction === "sensitive" ||
          moderationAction === "review") &&
    message.get("isDeleted") !== true &&
    message.get("isVisible") === true &&
    message.get("isPubliclyVisible") === true;
}

function requireMentionSourceRoute(event: NotificationOutboxData): string {
  const segments = event.sourcePath.split("/");
  if (segments.length !== 4 || segments[0] !== "places" ||
      segments[2] !== "messages" || segments[3] !== event.entityId) {
    throw new Error("Mention notification source path is invalid.");
  }
  return segments[1];
}

function requirePlaceLocation(place: DocumentSnapshot): {
  latitude: number; longitude: number;
} {
  const latitude = place.get("latitude");
  const longitude = place.get("longitude");
  if (typeof latitude !== "number" || !Number.isFinite(latitude) ||
      typeof longitude !== "number" || !Number.isFinite(longitude)) {
    throw new Error("Mention note location is invalid.");
  }
  return {latitude, longitude};
}

function requiredId(value: unknown, field: string): string {
  if (typeof value !== "string" || value.length === 0 ||
      value.length > 256 || value.includes("/")) {
    throw new HttpsError("invalid-argument", `${field} is required.`);
  }
  return value;
}

function consumeMentionSearchRateLimit(uid: string): void {
  const now = Date.now();
  const bucket = searchBuckets.get(uid) ?? {
    tokens: SEARCH_RATE_LIMIT_CAPACITY,
    lastRefillAt: now,
  };
  const elapsedSeconds = Math.max(0, (now - bucket.lastRefillAt) / 1_000);
  bucket.tokens = Math.min(
    SEARCH_RATE_LIMIT_CAPACITY,
    bucket.tokens + elapsedSeconds * SEARCH_RATE_LIMIT_REFILL_PER_SECOND,
  );
  bucket.lastRefillAt = now;
  if (bucket.tokens < 1) {
    searchBuckets.set(uid, bucket);
    throw new HttpsError(
      "resource-exhausted",
      "Mention search is being refreshed too quickly.",
    );
  }
  bucket.tokens -= 1;
  searchBuckets.set(uid, bucket);
}

function stringOrNull(value: unknown): string | null {
  return typeof value === "string" && value.length > 0 ? value : null;
}

function invalidMentions(): HttpsError {
  return new HttpsError(
    "failed-precondition",
    "One or more mention recipients are no longer available.",
    {reason: "invalid_mentions"},
  );
}

function statuses(
  recipients: readonly string[],
  status: NotificationRecipientStatus,
): Record<string, NotificationRecipientStatus> {
  return Object.fromEntries(recipients.map((uid) => [uid, status]));
}

function providerErrorCode(error: unknown): string {
  if (typeof error === "object" && error !== null && "code" in error) {
    const code = String((error as {code: unknown}).code);
    if (/^[A-Za-z0-9_.:/-]{1,128}$/.test(code)) return code;
  }
  return "mention-notice-error";
}
