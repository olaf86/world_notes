/* eslint-disable require-jsdoc */
import {onCall, HttpsError} from "./platform/worldCallable";
import {
  DocumentReference,
  DocumentSnapshot,
  FieldValue,
  Firestore,
  Timestamp,
  Transaction,
} from "firebase-admin/firestore";

import {
  assertAccountSafetyAllows,
  assertAccountSafetyPreflight,
} from "./accountSafety";
import {
  MAX_MESSAGE_IMAGES,
  MAX_MESSAGE_PUBLISH_DELAY_DAYS,
  MAX_MESSAGES_PER_THREAD,
  REGION,
} from "./constants";
import {
  type AppModerationRiskSignal,
  detectAppModerationRiskSignals,
} from "./moderation";
import {enqueueModerationJob} from "./moderationJobs";
import {
  EVALUATE_MESSAGE_MODERATION_JOB,
  messageModerationInputHash,
} from "./messageModeration";
import {
  likedMessagesData,
  parseLikedMessages,
  updatedMessageIds,
} from "./likedMessages";
import {
  assertReportCooldown,
  reportReasonCodeOf,
  requiredReportDocumentId,
  type ReportReasonCode,
} from "./reporting";
import {profileForMember} from "./userProfile";
import {
  assertLiked,
  hasValidMembership,
  isPublishedReadablePlace,
  type LikeMutationResult,
  nextLikeCount,
} from "./likeHelpers";
import {canMaintainNote} from "./noteMaintenance";
import {
  hasUserBlockBetweenInTransaction,
} from "./userBlocks";
import {bindImageUploadsToContent} from "./imageUploads";
import {enqueueStorageObjectDeletion} from "./storageObjectCleanup";

interface SendMessageData {
  messageId?: unknown;
  placeId?: unknown;
  content?: unknown;
  imageStoragePaths?: unknown;
  publishAtMillis?: unknown;
}

interface ReportMessageData {
  placeId?: unknown;
  messageId?: unknown;
  reasonCode?: unknown;
  reason?: unknown;
}

interface SetMessageLikeData {
  placeId?: unknown;
  messageId?: unknown;
  liked?: unknown;
}

interface ValidatedSendMessageInput {
  messageId: string;
  placeId: string;
  trimmedContent: string;
  trimmedImageStoragePaths: string[];
  publishAtMillis?: unknown;
}

interface ValidatedReportMessageInput {
  placeId: string;
  messageId: string;
  reasonCode: ReportReasonCode;
}

interface ValidatedSetMessageLikeInput {
  placeId: string;
  messageId: string;
  liked: boolean;
}

interface SendMessageRefs {
  placeRef: DocumentReference;
  administratorRef: DocumentReference;
  noteStateRef: DocumentReference;
  memberRef: DocumentReference;
  counterRef: DocumentReference;
  messageRef: DocumentReference;
  moderationReviewRef: DocumentReference;
}

interface MessageLikeRefs {
  placeRef: DocumentReference;
  administratorRef: DocumentReference;
  memberRef: DocumentReference;
  messageRef: DocumentReference;
  likedMessagesRef: DocumentReference;
}

interface SendMessageProfile {
  displayName: string | null;
}

interface CreateMessageParams {
  db: Firestore;
  worldId: string;
  refs: SendMessageRefs;
  uid: string;
  input: ValidatedSendMessageInput;
  profile: SendMessageProfile;
  tokenPicture: unknown;
  riskSignals: AppModerationRiskSignal[];
  nowMs: number;
}

interface CreateMessageResult {
  created: boolean;
  publishAtMillis: number;
  isScheduled: boolean;
}

interface DeleteMessageData {
  placeId?: unknown;
  messageId?: unknown;
}

interface CancelScheduledMessageData {
  placeId?: unknown;
  messageId?: unknown;
}

function stringOrNull(value: unknown): string | null {
  return typeof value === "string" && value.trim().length > 0 ?
    value.trim() :
    null;
}

function storedImagePaths(value: unknown): string[] {
  if (!Array.isArray(value)) return [];
  return value
    .map((path) => stringOrNull(path))
    .filter((path): path is string => path !== null);
}

const UUID_V7_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;

function messageIdOf(value: unknown): string {
  if (typeof value !== "string" || !UUID_V7_PATTERN.test(value)) {
    throw new HttpsError("invalid-argument", "Invalid messageId.");
  }
  return value;
}

function validateSendMessageInput(
  data: SendMessageData | undefined,
  uid: string,
): ValidatedSendMessageInput {
  const {
    messageId: rawMessageId,
    placeId,
    content,
    imageStoragePaths,
    publishAtMillis,
  } = data ?? {};
  const messageId = messageIdOf(rawMessageId);
  if (typeof placeId !== "string" || placeId.length === 0) {
    throw new HttpsError("invalid-argument", "placeId is required.");
  }

  const trimmedContent =
    typeof content === "string" ? content.trim() : "";
  if (trimmedContent.length > 2000) {
    throw new HttpsError("invalid-argument", "Message is too long.");
  }

  if (imageStoragePaths != null && !Array.isArray(imageStoragePaths)) {
    throw new HttpsError("invalid-argument", "Invalid image storage paths.");
  }
  const trimmedImageStoragePaths = storedImagePaths(imageStoragePaths);
  if (trimmedImageStoragePaths.length > MAX_MESSAGE_IMAGES) {
    throw new HttpsError("invalid-argument", "Too many images.");
  }
  if (
    Array.isArray(imageStoragePaths) &&
    trimmedImageStoragePaths.length !== imageStoragePaths.length
  ) {
    throw new HttpsError("invalid-argument", "Invalid image storage paths.");
  }
  const seenImagePaths = new Set<string>();
  trimmedImageStoragePaths.forEach((path, index) => {
    const expectedImageStoragePath =
      `images/messages/${placeId}/${uid}/${messageId}/${index}.webp`;
    if (path !== expectedImageStoragePath || seenImagePaths.has(path)) {
      throw new HttpsError("invalid-argument", "Invalid image storage path.");
    }
    seenImagePaths.add(path);
  });
  if (trimmedContent.length === 0 && trimmedImageStoragePaths.length === 0) {
    throw new HttpsError(
      "invalid-argument",
      "Message content or image is required.",
    );
  }

  return {
    messageId,
    placeId,
    trimmedContent,
    trimmedImageStoragePaths,
    publishAtMillis,
  };
}

function validateReportMessageInput(
  data: ReportMessageData | undefined,
): ValidatedReportMessageInput {
  return {
    placeId: requiredReportDocumentId(data?.placeId, "placeId"),
    messageId: requiredReportDocumentId(data?.messageId, "messageId"),
    reasonCode: reportReasonCodeOf(data?.reasonCode ?? data?.reason),
  };
}

function validateSetMessageLikeInput(
  data: SetMessageLikeData | undefined,
): ValidatedSetMessageLikeInput {
  return {
    placeId: requiredReportDocumentId(data?.placeId, "placeId"),
    messageId: requiredReportDocumentId(data?.messageId, "messageId"),
    liked: assertLiked(data?.liked),
  };
}

function sendMessageRefs(
  db: Firestore,
  input: ValidatedSendMessageInput,
  uid: string,
): SendMessageRefs {
  const placeRef = db.collection("places").doc(input.placeId);
  return {
    placeRef,
    administratorRef: placeRef.collection("administrators").doc(uid),
    noteStateRef: db
      .collection("users")
      .doc(uid)
      .collection("noteStates")
      .doc(input.placeId),
    memberRef: placeRef.collection("members").doc(uid),
    counterRef: placeRef.collection("counters").doc("messageSlots"),
    messageRef: placeRef.collection("messages").doc(input.messageId),
    moderationReviewRef: db
      .collection("moderationReviews")
      .doc(`${input.placeId}_${input.messageId}`),
  };
}

function messageLikeRefs(
  db: Firestore,
  input: ValidatedSetMessageLikeInput,
  uid: string,
): MessageLikeRefs {
  const placeRef = db.collection("places").doc(input.placeId);
  const messageRef = placeRef.collection("messages").doc(input.messageId);
  return {
    placeRef,
    administratorRef: placeRef.collection("administrators").doc(uid),
    memberRef: placeRef.collection("members").doc(uid),
    messageRef,
    likedMessagesRef: placeRef.collection("likedMessages").doc(uid),
  };
}

async function existingMessageResult(
  messageRef: DocumentReference,
  uid: string,
  nowMs: number,
): Promise<Record<string, unknown> | null> {
  const existingMessageSnap = await messageRef.get();
  if (!existingMessageSnap.exists) return null;
  if (existingMessageSnap.get("userId") !== uid) {
    throw new HttpsError(
      "already-exists",
      "This message id is already in use.",
    );
  }
  const existingPublishAt =
    existingMessageSnap.get("publishAt") as Timestamp | undefined;
  return {
    messageId: messageRef.id,
    publishAtMillis: existingPublishAt?.toMillis() ?? nowMs,
    isScheduled: isScheduledMessage(existingMessageSnap),
  };
}

/**
 * Reads the required scheduling flag from a message document.
 *
 * @param {DocumentSnapshot} messageSnap Message document to read.
 * @return {boolean} Whether scheduled publication was selected.
 */
function isScheduledMessage(messageSnap: DocumentSnapshot): boolean {
  const storedIsScheduled = messageSnap.get("isScheduled");
  if (typeof storedIsScheduled !== "boolean") {
    throw new HttpsError(
      "failed-precondition",
      "Message scheduling metadata is missing.",
    );
  }
  return storedIsScheduled;
}

function photoUrlFor(tokenPicture: unknown): string | null {
  return stringOrNull(tokenPicture);
}

function messageDocumentData({
  placeId,
  uid,
  profileDisplayName,
  tokenPicture,
  content,
  imageStoragePaths,
  publishAt,
  isScheduled,
  isPubliclyVisible,
  riskSignals,
}: {
  placeId: string;
  uid: string;
  profileDisplayName: string | null;
  tokenPicture: unknown;
  content: string;
  imageStoragePaths: string[];
  publishAt: Timestamp;
  isScheduled: boolean;
  isPubliclyVisible: boolean;
  riskSignals: AppModerationRiskSignal[];
}): Record<string, unknown> {
  return {
    placeId,
    userId: uid,
    userName: profileDisplayName ?? "Unknown user",
    userPhotoUrl: photoUrlFor(tokenPicture),
    content,
    ...(imageStoragePaths.length > 0 ?
      {imageStoragePaths} :
      {}),
    createdAt: FieldValue.serverTimestamp(),
    publishAt,
    isScheduled,
    isDeleted: false,
    deletedAt: null,
    deletedReason: null,
    moderationAction: "pending",
    moderationPurgeStartedAt: null,
    isSensitive: false,
    isVisible: true,
    reviewRequired: false,
    ...(riskSignals.length > 0 ? {moderationRiskSignals: riskSignals} : {}),
    isPubliclyVisible,
    reportCount: 0,
    likeCount: 0,
  };
}

function canAccessNote(
  placeSnap: DocumentSnapshot,
  administratorSnap: DocumentSnapshot,
  memberSnap: DocumentSnapshot | null,
  uid: string,
): boolean {
  if (placeSnap.get("visibility") !== "private") return true;
  if (canMaintainNote(placeSnap, administratorSnap, uid)) return true;
  return hasValidMembership(placeSnap, memberSnap);
}

function canLikeMessage(
  placeSnap: DocumentSnapshot,
  administratorSnap: DocumentSnapshot,
  memberSnap: DocumentSnapshot | null,
  messageSnap: DocumentSnapshot,
  uid: string,
  nowMs: number,
): boolean {
  return isPublishedReadablePlace(placeSnap, nowMs) &&
    canAccessNote(placeSnap, administratorSnap, memberSnap, uid) &&
    messageSnap.get("isVisible") === true &&
    messageSnap.get("isPubliclyVisible") === true &&
    messageSnap.get("isDeleted") !== true;
}

function messageSlotCount(
  counterSnap: DocumentSnapshot,
  initialPublicCount: number,
): number {
  return counterSnap.exists ?
    ((counterSnap.get("count") as number | undefined) ?? 0) :
    initialPublicCount;
}

function validatePlaceCanAccept(placeSnap: DocumentSnapshot, nowMs: number) {
  if (placeSnap.get("isOpen") !== true) {
    throw new HttpsError("failed-precondition", "This note is closed.");
  }
  if (placeSnap.get("isArchived") === true) {
    throw new HttpsError("failed-precondition", "This note is archived.");
  }
  if (placeSnap.get("isModerationHidden") !== false) {
    throw new HttpsError("failed-precondition", "This note is unavailable.");
  }
  const placePublishAt = placeSnap.get("publishAt") as Timestamp | undefined;
  if (placePublishAt && placePublishAt.toMillis() > nowMs) {
    throw new HttpsError(
      "failed-precondition",
      "This note is not published yet.",
    );
  }
  const expiresAt = placeSnap.get("expiresAt") as Timestamp | undefined;
  if (!expiresAt || expiresAt.toMillis() <= nowMs) {
    throw new HttpsError("failed-precondition", "This note has expired.");
  }
}

function validatePublishAt(
  rawPublishAtMillis: unknown,
  nowMs: number,
  placeSnap: DocumentSnapshot,
): Timestamp {
  let publishAtMs = nowMs;
  if (rawPublishAtMillis != null) {
    if (
      typeof rawPublishAtMillis !== "number" ||
      !isFinite(rawPublishAtMillis)
    ) {
      throw new HttpsError("invalid-argument", "Invalid publication time.");
    }
    const maxPublishAtMs =
      nowMs + MAX_MESSAGE_PUBLISH_DELAY_DAYS * 24 * 60 * 60 * 1000;
    if (rawPublishAtMillis > maxPublishAtMs) {
      throw new HttpsError(
        "invalid-argument",
        "Publication time is too far in the future.",
      );
    }
    publishAtMs = Math.max(rawPublishAtMillis, nowMs);
  }

  const expiresAt = placeSnap.get("expiresAt") as Timestamp | undefined;
  if (!expiresAt || publishAtMs >= expiresAt.toMillis()) {
    throw new HttpsError(
      "failed-precondition",
      "Publication time must be before the note expires.",
    );
  }
  return Timestamp.fromMillis(publishAtMs);
}

function messageCreationPlaceUpdate(
  placeSnap: DocumentSnapshot,
  publicCount: number,
  publishAt: Timestamp,
  isImmediate: boolean,
): Record<string, unknown> {
  if (!isImmediate) return {};

  const placeUpdate: Record<string, unknown> = {};
  const nextPublicCount = publicCount + 1;
  placeUpdate.messageCount = nextPublicCount;

  const lastMessageAt =
    placeSnap.get("lastMessageAt") as Timestamp | undefined;
  if (!lastMessageAt || lastMessageAt.toMillis() < publishAt.toMillis()) {
    placeUpdate.lastMessageAt = publishAt;
  }

  if (nextPublicCount >= MAX_MESSAGES_PER_THREAD) {
    placeUpdate.isOpen = false;
    placeUpdate.closedReason = "messageLimit";
    placeUpdate.closedAt = FieldValue.serverTimestamp();
  }
  return placeUpdate;
}

async function createMessageInTransaction({
  db,
  worldId,
  refs,
  uid,
  input,
  profile,
  tokenPicture,
  riskSignals,
  nowMs,
}: CreateMessageParams): Promise<CreateMessageResult> {
  let created = false;
  let publishAtMillis = nowMs;
  let isScheduled = false;

  await db.runTransaction(async (tx) => {
    const [placeSnap, administratorSnap, messageSnap] = await Promise.all([
      tx.get(refs.placeRef),
      tx.get(refs.administratorRef),
      tx.get(refs.messageRef),
    ]);
    if (!placeSnap.exists) {
      throw new HttpsError("not-found", "Note not found.");
    }
    if (messageSnap.exists) {
      if (messageSnap.get("userId") !== uid) {
        throw new HttpsError(
          "already-exists",
          "This message id is already in use.",
        );
      }
      const existingPublishAt =
        messageSnap.get("publishAt") as Timestamp | undefined;
      publishAtMillis = existingPublishAt?.toMillis() ?? nowMs;
      isScheduled = isScheduledMessage(messageSnap);
      return;
    }

    const creatorUid = placeSnap.get("createdByUserId") as string | undefined;
    if (
      creatorUid &&
      await hasUserBlockBetweenInTransaction(tx, db, uid, creatorUid)
    ) {
      throw new HttpsError(
        "permission-denied",
        "You cannot access this note.",
        {reason: "user_blocked"},
      );
    }
    await assertAccountSafetyAllows(
      tx,
      db,
      uid,
      "contentWrite",
      Timestamp.fromMillis(nowMs),
    );
    const memberSnap =
      placeSnap.get("visibility") === "private" &&
        !canMaintainNote(placeSnap, administratorSnap, uid) ?
        await tx.get(refs.memberRef) :
        null;
    if (!canAccessNote(placeSnap, administratorSnap, memberSnap, uid)) {
      throw new HttpsError(
        "permission-denied",
        "You cannot access this note.",
      );
    }
    const counterSnap = await tx.get(refs.counterRef);
    await bindImageUploadsToContent(
      tx,
      db,
      input.trimmedImageStoragePaths,
      refs.messageRef.path,
      Timestamp.fromMillis(nowMs),
    );

    validatePlaceCanAccept(placeSnap, nowMs);
    const publicCount =
      (placeSnap.get("messageCount") as number | undefined) ?? 0;
    const currentSlots = messageSlotCount(counterSnap, publicCount);
    if (currentSlots >= MAX_MESSAGES_PER_THREAD) {
      throw new HttpsError("resource-exhausted", "This note is full.");
    }

    const publishAt = validatePublishAt(
      input.publishAtMillis,
      nowMs,
      placeSnap,
    );
    const isImmediate = publishAt.toMillis() <= nowMs;
    isScheduled = !isImmediate;
    publishAtMillis = publishAt.toMillis();
    created = true;

    const placeUpdate = messageCreationPlaceUpdate(
      placeSnap,
      publicCount,
      publishAt,
      isImmediate,
    );
    tx.set(
      refs.counterRef,
      {
        count: currentSlots + 1,
        updatedAt: FieldValue.serverTimestamp(),
      },
      {merge: true},
    );
    if (Object.keys(placeUpdate).length > 0) {
      tx.update(refs.placeRef, placeUpdate);
    }
    tx.set(
      refs.noteStateRef,
      {
        lastSeenMessageCount: isImmediate ? publicCount + 1 : publicCount,
        lastOpenedAt: FieldValue.serverTimestamp(),
        discoverySeenAt: FieldValue.serverTimestamp(),
        participatedAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      },
      {merge: true},
    );
    tx.set(refs.messageRef, {
      ...messageDocumentData({
        placeId: input.placeId,
        uid,
        profileDisplayName: profile.displayName,
        tokenPicture,
        content: input.trimmedContent,
        imageStoragePaths: input.trimmedImageStoragePaths,
        publishAt,
        isScheduled,
        isPubliclyVisible: isImmediate,
        riskSignals,
      }),
      placeAggregateAppliedAt: isImmediate ?
        FieldValue.serverTimestamp() :
        null,
    });
    enqueueModerationJob(
      tx,
      db,
      {
        jobType: EVALUATE_MESSAGE_MODERATION_JOB,
        targetPath: refs.messageRef.path,
        inputHash: messageModerationInputHash(
          input.trimmedContent,
          input.trimmedImageStoragePaths,
        ),
        world: worldId,
      },
      Timestamp.fromMillis(nowMs),
    );
  });

  return {
    created,
    publishAtMillis,
    isScheduled,
  };
}

/**
 * Authoritative message creation.
 *
 * places.messageCount is public and counts only publicly visible messages.
 * places/{placeId}/counters/messageSlots.count is server-only and includes
 * scheduled messages immediately for cap enforcement.
 */
export const sendMessage = onCall<SendMessageData>(
  {enforceAppCheck: true, region: REGION},
  async (req, world) => {
    const uid = req.auth?.uid;
    if (!uid) throw new HttpsError("unauthenticated", "Sign in required.");

    const input = validateSendMessageInput(req.data, uid);
    const db = world.firestore;
    const refs = sendMessageRefs(db, input, uid);
    const nowMs = Date.now();
    const existingResult = await existingMessageResult(
      refs.messageRef,
      uid,
      nowMs,
    );
    if (existingResult) return existingResult;
    await assertAccountSafetyPreflight(
      db,
      uid,
      "contentWrite",
      Timestamp.fromMillis(nowMs),
    );

    // If acceptance fails, unattached immutable uploads remain inaccessible
    // and the regional orphan sweeper collects them after its grace period.
    const riskSignals = detectAppModerationRiskSignals(input.trimmedContent);
    const profile = await profileForMember(db, uid);
    const result = await createMessageInTransaction({
      db,
      worldId: world.worldId,
      refs,
      uid,
      input,
      profile,
      tokenPicture: req.auth?.token.picture,
      riskSignals,
      nowMs,
    });

    return {
      messageId: refs.messageRef.id,
      publishAtMillis: result.publishAtMillis,
      isScheduled: result.isScheduled,
      moderationAction: "pending",
    };
  },
);

/**
 * Records a user report and queues the message for administrator review.
 */
export const reportMessage = onCall<ReportMessageData>(
  {enforceAppCheck: true, region: REGION},
  async (req, world) => {
    const uid = req.auth?.uid;
    if (!uid) {
      throw new HttpsError("unauthenticated", "Sign in required.");
    }
    const input = validateReportMessageInput(req.data);
    const db = world.firestore;
    const placeRef = db.collection("places").doc(input.placeId);
    const memberRef = placeRef.collection("members").doc(uid);
    const administratorRef = placeRef.collection("administrators").doc(uid);
    const messageRef = placeRef.collection("messages").doc(input.messageId);
    const reportRef = db.collection("reports").doc();
    const moderationReviewRef = db
      .collection("moderationReviews")
      .doc(`${input.placeId}_${input.messageId}`);
    const rateLimitRef = db
      .collection("users")
      .doc(uid)
      .collection("rateLimits")
      .doc("reportContent");
    const reportCreatedAt = Timestamp.now();

    await db.runTransaction(async (tx) => {
      const [
        placeSnap,
        administratorSnap,
        memberSnap,
        messageSnap,
        reviewSnap,
        rateLimitSnap,
      ] =
        await Promise.all([
          tx.get(placeRef),
          tx.get(administratorRef),
          tx.get(memberRef),
          tx.get(messageRef),
          tx.get(moderationReviewRef),
          tx.get(rateLimitRef),
        ]);
      assertReportCooldown(rateLimitSnap, reportCreatedAt);
      if (!placeSnap.exists) {
        throw new HttpsError("not-found", "Note not found.");
      }
      if (!messageSnap.exists) {
        throw new HttpsError("not-found", "Message not found.");
      }
      if (
        !isPublishedReadablePlace(placeSnap, reportCreatedAt.toMillis()) ||
        !canAccessNote(placeSnap, administratorSnap, memberSnap, uid)
      ) {
        throw new HttpsError(
          "permission-denied",
          "You cannot report this message.",
        );
      }
      if (messageSnap.get("userId") === uid) {
        throw new HttpsError(
          "failed-precondition",
          "You cannot report your own message.",
        );
      }
      if (
        messageSnap.get("isVisible") !== true ||
        messageSnap.get("isPubliclyVisible") !== true ||
        messageSnap.get("isDeleted") === true
      ) {
        throw new HttpsError(
          "failed-precondition",
          "This message is not reportable.",
        );
      }

      tx.set(reportRef, {
        worldId: world.worldId,
        targetType: "message",
        targetId: input.messageId,
        targetPath: `places/${input.placeId}/messages/${input.messageId}`,
        placeId: input.placeId,
        reporterId: uid,
        reportedUserId: messageSnap.get("userId") ?? null,
        reasonCode: input.reasonCode,
        status: "open",
        createdAt: reportCreatedAt,
      });
      tx.set(rateLimitRef, {
        lastWorldId: world.worldId,
        lastCreatedAt: reportCreatedAt,
        lastTargetType: "message",
        lastTargetId: input.messageId,
        lastPlaceId: input.placeId,
        lastMessageId: FieldValue.delete(),
      }, {merge: true});
      tx.update(messageRef, {
        reportCount: FieldValue.increment(1),
      });
      tx.set(moderationReviewRef, {
        worldId: world.worldId,
        userId: messageSnap.get("userId") ?? null,
        targetType: "message",
        targetId: input.messageId,
        targetPath: `places/${input.placeId}/messages/${input.messageId}`,
        placeId: input.placeId,
        content: messageSnap.get("content") ?? "",
        imageStoragePaths: storedImagePaths(
          messageSnap.get("imageStoragePaths"),
        ),
        reviewSources: FieldValue.arrayUnion("userReport"),
        reportCount: FieldValue.increment(1),
        reportReasonsSummary: FieldValue.arrayUnion(input.reasonCode),
        lastReportedAt: FieldValue.serverTimestamp(),
        status: "open",
        ...(reviewSnap.exists ? {} : {createdAt: FieldValue.serverTimestamp()}),
      }, {merge: true});
    });

    return {
      ok: true,
      placeId: input.placeId,
      messageId: input.messageId,
    };
  },
);

async function applyMessageLike(
  tx: Transaction,
  db: Firestore,
  refs: MessageLikeRefs,
  input: ValidatedSetMessageLikeInput,
  uid: string,
  nowMs: number,
): Promise<LikeMutationResult> {
  const [placeSnap, administratorSnap, messageSnap] = await Promise.all([
    tx.get(refs.placeRef),
    tx.get(refs.administratorRef),
    tx.get(refs.messageRef),
  ]);
  if (!placeSnap.exists || !messageSnap.exists) {
    throw new HttpsError("not-found", "Message not found.");
  }
  const memberSnap =
    placeSnap.get("visibility") === "private" &&
      !canMaintainNote(placeSnap, administratorSnap, uid) ?
      await tx.get(refs.memberRef) :
      null;
  if (!canLikeMessage(
    placeSnap,
    administratorSnap,
    memberSnap,
    messageSnap,
    uid,
    nowMs,
  )) {
    throw new HttpsError(
      "permission-denied",
      "You cannot like this message.",
    );
  }

  if (input.liked) {
    await assertAccountSafetyAllows(
      tx,
      db,
      uid,
      "participation",
      Timestamp.fromMillis(nowMs),
    );
    const relatedUserIds = new Set<string>([
      placeSnap.get("createdByUserId") as string,
      messageSnap.get("userId") as string,
    ]);
    relatedUserIds.delete(uid);
    for (const relatedUid of relatedUserIds) {
      if (
        relatedUid &&
        await hasUserBlockBetweenInTransaction(tx, db, uid, relatedUid)
      ) {
        throw new HttpsError(
          "permission-denied",
          "You cannot like this message.",
          {reason: "user_blocked"},
        );
      }
    }
  }
  const likedMessagesSnapshot = await tx.get(refs.likedMessagesRef);
  const route = {userId: uid, placeId: input.placeId};
  const currentMessageIds = likedMessagesSnapshot.exists ?
    parseLikedMessages(
      likedMessagesSnapshot.data(),
      route,
    ).messageIds : [];
  const result = nextLikeCount({
    currentCount: (messageSnap.get("likeCount") as number | undefined) ?? 0,
    currentlyLiked: currentMessageIds.includes(input.messageId),
    desiredLiked: input.liked,
  });
  if (!result.changed) {
    return {liked: input.liked, likeCount: result.likeCount};
  }

  const nextMessageIds = updatedMessageIds(
    currentMessageIds,
    input.messageId,
    input.liked,
  );
  const updatedAt = Timestamp.fromMillis(nowMs);
  tx.set(refs.likedMessagesRef, {...likedMessagesData({
    userId: uid,
    placeId: input.placeId,
    messageIds: nextMessageIds,
    updatedAt,
  })});
  tx.update(refs.messageRef, {likeCount: result.likeCount});
  return {liked: input.liked, likeCount: result.likeCount};
}

/**
 * Sets the caller's final desired like state for a published message.
 */
export const setMessageLike = onCall<SetMessageLikeData>(
  {enforceAppCheck: true, region: REGION},
  async (req, world) => {
    const uid = req.auth?.uid;
    if (!uid) throw new HttpsError("unauthenticated", "Sign in required.");

    const input = validateSetMessageLikeInput(req.data);
    const db = world.firestore;
    const refs = messageLikeRefs(db, input, uid);
    const nowMs = Date.now();

    return db.runTransaction((tx) =>
      applyMessageLike(tx, db, refs, input, uid, nowMs),
    );
  },
);

/**
 * Soft-deletes a published message and removes its stored images.
 */
export const deleteMessage = onCall<DeleteMessageData>(
  {enforceAppCheck: true, region: REGION},
  async (req, world) => {
    const uid = req.auth?.uid;
    if (!uid) throw new HttpsError("unauthenticated", "Sign in required.");

    const {placeId, messageId} = req.data ?? {};
    if (typeof placeId !== "string" || placeId.length === 0) {
      throw new HttpsError("invalid-argument", "placeId is required.");
    }
    if (typeof messageId !== "string" || messageId.length === 0) {
      throw new HttpsError("invalid-argument", "messageId is required.");
    }

    const db = world.firestore;
    const messageRef = db
      .collection("places")
      .doc(placeId)
      .collection("messages")
      .doc(messageId);
    const deletedAt = Timestamp.now();

    await db.runTransaction(async (tx) => {
      const messageSnap = await tx.get(messageRef);
      if (!messageSnap.exists) {
        throw new HttpsError("not-found", "Message not found.");
      }
      if (messageSnap.get("userId") !== uid) {
        throw new HttpsError(
          "permission-denied",
          "You can delete only your own message.",
        );
      }
      if (messageSnap.get("isPubliclyVisible") !== true) {
        throw new HttpsError(
          "failed-precondition",
          "Scheduled messages must be canceled.",
        );
      }
      if (messageSnap.get("isDeleted") === true) return;
      for (const storagePath of storedImagePaths(messageSnap.get(
        "imageStoragePaths",
      ))) {
        enqueueStorageObjectDeletion(tx, db, {
          sourceOperationId: `deleteMessage:${messageId}`,
          revision: 1,
          world: world.worldId,
          objectPath: storagePath,
          createdAt: deletedAt,
        });
      }
      tx.update(messageRef, {
        isDeleted: true,
        deletedAt,
        deletedReason: "author",
        imageStoragePaths: FieldValue.delete(),
      });
    });

    return {ok: true};
  },
);

/**
 * Cancels an unpublished scheduled message and frees its reserved slot.
 */
export const cancelScheduledMessage = onCall<CancelScheduledMessageData>(
  {enforceAppCheck: true, region: REGION},
  async (req, world) => {
    const uid = req.auth?.uid;
    if (!uid) throw new HttpsError("unauthenticated", "Sign in required.");

    const {placeId, messageId} = req.data ?? {};
    if (typeof placeId !== "string" || placeId.length === 0) {
      throw new HttpsError("invalid-argument", "placeId is required.");
    }
    if (typeof messageId !== "string" || messageId.length === 0) {
      throw new HttpsError("invalid-argument", "messageId is required.");
    }

    const db = world.firestore;
    const placeRef = db.collection("places").doc(placeId);
    const counterRef = placeRef.collection("counters").doc("messageSlots");
    const messageRef = placeRef.collection("messages").doc(messageId);
    const nowMs = Date.now();
    const canceledAt = Timestamp.fromMillis(nowMs);

    await db.runTransaction(async (tx) => {
      const [placeSnap, messageSnap, counterSnap] = await Promise.all([
        tx.get(placeRef),
        tx.get(messageRef),
        tx.get(counterRef),
      ]);
      if (!placeSnap.exists || !messageSnap.exists) {
        throw new HttpsError("not-found", "Message not found.");
      }
      if (messageSnap.get("userId") !== uid) {
        throw new HttpsError(
          "permission-denied",
          "You can cancel only your own message.",
        );
      }
      if (messageSnap.get("isDeleted") === true) return;
      if (messageSnap.get("isPubliclyVisible") === true) {
        throw new HttpsError(
          "failed-precondition",
          "Published messages cannot be canceled.",
        );
      }

      const publishAt = messageSnap.get("publishAt") as Timestamp | undefined;
      if (!publishAt || publishAt.toMillis() <= nowMs) {
        throw new HttpsError(
          "failed-precondition",
          "This message is already due for publication.",
        );
      }

      const publicCount =
        (placeSnap.get("messageCount") as number | undefined) ?? 0;
      const currentSlots = messageSlotCount(counterSnap, publicCount);
      const nextSlots = Math.max(0, currentSlots - 1);
      tx.set(
        counterRef,
        {
          count: nextSlots,
          updatedAt: FieldValue.serverTimestamp(),
        },
        {merge: true},
      );

      const placeUpdate: Record<string, unknown> = {};
      const expiresAt = placeSnap.get("expiresAt") as Timestamp | undefined;
      if (
        publicCount < MAX_MESSAGES_PER_THREAD &&
        nextSlots < MAX_MESSAGES_PER_THREAD &&
        placeSnap.get("closedReason") === "messageLimit" &&
        placeSnap.get("isArchived") !== true &&
        (!expiresAt || expiresAt.toMillis() > nowMs)
      ) {
        placeUpdate.isOpen = true;
        placeUpdate.closedReason = FieldValue.delete();
        placeUpdate.closedAt = FieldValue.delete();
      }

      if (Object.keys(placeUpdate).length > 0) {
        tx.update(placeRef, placeUpdate);
      }
      for (const storagePath of storedImagePaths(messageSnap.get(
        "imageStoragePaths",
      ))) {
        enqueueStorageObjectDeletion(tx, db, {
          sourceOperationId: `cancelScheduledMessage:${messageId}`,
          revision: 1,
          world: world.worldId,
          objectPath: storagePath,
          createdAt: canceledAt,
        });
      }
      tx.delete(messageRef);
    });

    return {ok: true};
  },
);
