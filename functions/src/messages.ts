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
import * as logger from "firebase-functions/logger";

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
import {asiaWorldContext} from "./platform/worldContext";
import {ASIA_WORLD_ID} from "./platform/worldRegistry";
import {
  type AppModerationRiskSignal,
  type InternalModerationResult,
  type ModerationImageInput,
  OPENAI_API_KEY,
  applyModerationToUser,
  assertUserCanCreateContent,
  createModerationNoticeIfNeeded,
  detectAppModerationRiskSignals,
  hasReviewRecommendedRiskSignal,
  moderationAuditFields,
  moderateContent,
  moderationFields,
  recordRejectedModeration,
} from "./moderation";
import {
  assertReportCooldown,
  reportReasonCodeOf,
  requiredReportDocumentId,
  type ReportReasonCode,
} from "./reporting";
import {profileForMember} from "./userProfile";
import {
  sendMyNotesMessageNotifications,
} from "./notifications";
import {
  assertLiked,
  hasValidMembership,
  isPublishedReadablePlace,
  type LikeMutationResult,
  likeEdgeData,
  likedStateOf,
  nextLikeCount,
} from "./likeHelpers";
import {canMaintainNote} from "./noteMaintenance";
import {
  hasUserBlockBetween,
  hasUserBlockBetweenInTransaction,
} from "./userBlocks";

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
  userRef: DocumentReference;
  noteStateRef: DocumentReference;
  memberRef: DocumentReference;
  counterRef: DocumentReference;
  messageRef: DocumentReference;
  moderationReviewRef: DocumentReference;
}

interface MessageLikeRefs {
  placeRef: DocumentReference;
  memberRef: DocumentReference;
  messageRef: DocumentReference;
  likeRef: DocumentReference;
}

interface SendMessageProfile {
  displayName: string | null;
}

type ModerationReviewSource = "provider" | "riskSignal" | "userReport";

interface CreateMessageParams {
  db: Firestore;
  refs: SendMessageRefs;
  uid: string;
  input: ValidatedSendMessageInput;
  profile: SendMessageProfile;
  tokenPicture: unknown;
  moderationResult: InternalModerationResult;
  riskSignals: AppModerationRiskSignal[];
  nowMs: number;
}

interface CreateMessageResult {
  created: boolean;
  notifyImmediately: boolean;
  publishAtMillis: number;
  isScheduled: boolean;
  moderationNoticePoints: number;
  imageStoragePathsToDelete: string[];
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
    userRef: db.collection("users").doc(uid),
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
    memberRef: placeRef.collection("members").doc(uid),
    messageRef,
    likeRef: messageRef.collection("messageLikes").doc(uid),
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

function isModerationRemoval(
  moderationResult: InternalModerationResult,
): boolean {
  return moderationResult.action === "hidden";
}

async function deleteStoredImages(storagePaths: string[]): Promise<void> {
  if (storagePaths.length === 0) return;
  const bucket = asiaWorldContext().bucket;
  for (const storagePath of storagePaths) {
    try {
      await bucket.file(storagePath).delete({ignoreNotFound: true});
    } catch (error) {
      logger.warn(`Could not delete message image ${storagePath}.`, error);
    }
  }
}

async function moderationImagesFor(
  storagePaths: string[],
): Promise<ModerationImageInput[]> {
  if (storagePaths.length === 0) return [];
  const bucket = asiaWorldContext().bucket;
  return Promise.all(storagePaths.map(async (storagePath) => {
    const file = bucket.file(storagePath);
    try {
      const [[metadata], [bytes]] = await Promise.all([
        file.getMetadata(),
        file.download(),
      ]);
      if (
        metadata.contentType !== "image/webp" ||
        Number(metadata.size ?? bytes.length) > 2 * 1024 * 1024
      ) {
        throw new HttpsError(
          "invalid-argument",
          "Invalid message image metadata.",
          {reason: "invalid_image"},
        );
      }
      return {
        bytes,
        contentType: "image/webp" as const,
      };
    } catch (error) {
      if (error instanceof HttpsError) throw error;
      throw new HttpsError(
        "failed-precondition",
        "Message image upload was not found.",
        {reason: "image_upload_missing"},
      );
    }
  }));
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
  moderationResult,
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
  moderationResult: InternalModerationResult;
  riskSignals: AppModerationRiskSignal[];
}): Record<string, unknown> {
  const removedByModeration = isModerationRemoval(moderationResult);
  return {
    placeId,
    userId: uid,
    userName: profileDisplayName ?? "Unknown user",
    userPhotoUrl: photoUrlFor(tokenPicture),
    content: removedByModeration ? "" : content,
    ...(!removedByModeration && imageStoragePaths.length > 0 ?
      {imageStoragePaths} :
      {}),
    createdAt: FieldValue.serverTimestamp(),
    publishAt,
    isScheduled,
    isDeleted: removedByModeration,
    deletedAt: removedByModeration ?
      FieldValue.serverTimestamp() :
      null,
    deletedReason: removedByModeration ? "moderation" : null,
    ...moderationFields(moderationResult),
    ...(riskSignals.length > 0 ? {moderationRiskSignals: riskSignals} : {}),
    isPubliclyVisible,
    reportCount: 0,
    likeCount: 0,
  };
}

function moderationReviewDocumentData({
  uid,
  placeId,
  messageId,
  moderationResult,
  riskSignals,
  submittedContent,
  submittedImageStoragePaths,
}: {
  uid: string;
  placeId: string;
  messageId: string;
  moderationResult: InternalModerationResult;
  riskSignals: AppModerationRiskSignal[];
  submittedContent: string;
  submittedImageStoragePaths: string[];
}): Record<string, unknown> {
  const reviewSources: ModerationReviewSource[] = [
    ...(moderationResult.action !== "allow" &&
      moderationResult.action !== "pending" ?
      ["provider" as const] :
      []),
    ...(hasReviewRecommendedRiskSignal(riskSignals) ?
      ["riskSignal" as const] :
      []),
  ];
  return {
    worldId: ASIA_WORLD_ID,
    userId: uid,
    targetType: "message",
    targetId: messageId,
    targetPath: `places/${placeId}/messages/${messageId}`,
    placeId,
    content: submittedContent,
    imageStoragePaths: submittedImageStoragePaths,
    reviewSources,
    ...(riskSignals.length > 0 ? {riskSignals} : {}),
    status: "open",
    createdAt: FieldValue.serverTimestamp(),
    ...moderationAuditFields(moderationResult),
  };
}

function shouldCreateModerationReview(
  moderationResult: InternalModerationResult,
  riskSignals: AppModerationRiskSignal[],
): boolean {
  return (
    moderationResult.action !== "allow" &&
      moderationResult.action !== "pending"
  ) || hasReviewRecommendedRiskSignal(riskSignals);
}

function canAccessNote(
  placeSnap: DocumentSnapshot,
  memberSnap: DocumentSnapshot | null,
  uid: string,
): boolean {
  if (placeSnap.get("visibility") !== "private") return true;
  if (canMaintainNote(placeSnap, uid)) return true;
  return hasValidMembership(placeSnap, memberSnap);
}

function canLikeMessage(
  placeSnap: DocumentSnapshot,
  memberSnap: DocumentSnapshot | null,
  messageSnap: DocumentSnapshot,
  uid: string,
  nowMs: number,
): boolean {
  return isPublishedReadablePlace(placeSnap, nowMs) &&
    canAccessNote(placeSnap, memberSnap, uid) &&
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
  refs,
  uid,
  input,
  profile,
  tokenPicture,
  moderationResult,
  riskSignals,
  nowMs,
}: CreateMessageParams): Promise<CreateMessageResult> {
  let notifyImmediately = false;
  let created = false;
  let publishAtMillis = nowMs;
  let isScheduled = false;
  let moderationNoticePoints = 0;
  let imageStoragePathsToDelete: string[] = [];

  await db.runTransaction(async (tx) => {
    const [placeSnap, messageSnap] = await Promise.all([
      tx.get(refs.placeRef),
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
    await assertUserCanCreateContent(tx, refs.userRef, nowMs);
    const memberSnap =
      placeSnap.get("visibility") === "private" &&
        !canMaintainNote(placeSnap, uid) ?
        await tx.get(refs.memberRef) :
        null;
    if (!canAccessNote(placeSnap, memberSnap, uid)) {
      throw new HttpsError(
        "permission-denied",
        "You cannot access this note.",
      );
    }
    const counterSnap = await tx.get(refs.counterRef);

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
    const removedByModeration = isModerationRemoval(moderationResult);
    notifyImmediately = isImmediate && !removedByModeration;
    publishAtMillis = publishAt.toMillis();
    created = true;
    moderationNoticePoints = await applyModerationToUser(
      tx,
      refs.userRef,
      moderationResult,
    );

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
        moderationResult,
        riskSignals,
      }),
      placeAggregateAppliedAt: isImmediate ?
        FieldValue.serverTimestamp() :
        null,
    });
    if (shouldCreateModerationReview(moderationResult, riskSignals)) {
      tx.set(refs.moderationReviewRef, moderationReviewDocumentData({
        uid,
        placeId: input.placeId,
        messageId: input.messageId,
        moderationResult,
        riskSignals,
        submittedContent: input.trimmedContent,
        submittedImageStoragePaths: input.trimmedImageStoragePaths,
      }));
    }
    if (removedByModeration) {
      imageStoragePathsToDelete = input.trimmedImageStoragePaths;
    }
  });

  return {
    created,
    notifyImmediately,
    publishAtMillis,
    isScheduled,
    moderationNoticePoints,
    imageStoragePathsToDelete,
  };
}

async function createModerationNoticeSafely({
  uid,
  placeId,
  messageId,
  moderationResult,
  moderationNoticePoints,
}: {
  uid: string;
  placeId: string;
  messageId: string;
  moderationResult: InternalModerationResult;
  moderationNoticePoints: number;
}): Promise<void> {
  if (moderationNoticePoints <= 0) return;
  try {
    await createModerationNoticeIfNeeded(
      uid,
      moderationResult,
      moderationNoticePoints,
    );
  } catch (error) {
    logger.error(
      "sendMessage: failed to create moderation notice for " +
        `places/${placeId}/messages/${messageId}.`,
      error,
    );
  }
}

async function sendMessageNotificationsSafely({
  db,
  placeId,
  messageId,
  uid,
}: {
  db: Firestore;
  placeId: string;
  messageId: string;
  uid: string;
}): Promise<void> {
  try {
    await sendMyNotesMessageNotifications(db, placeId, messageId, uid);
  } catch (error) {
    logger.error(
      "sendMessage: failed to send My Notes notification for " +
        `places/${placeId}/messages/${messageId}.`,
      error,
    );
  }
}

async function runSendMessageSideEffects({
  db,
  uid,
  input,
  messageId,
  moderationResult,
  result,
}: {
  db: Firestore;
  uid: string;
  input: ValidatedSendMessageInput;
  messageId: string;
  moderationResult: InternalModerationResult;
  result: CreateMessageResult;
}): Promise<void> {
  if (!result.created) return;

  if (result.imageStoragePathsToDelete.length > 0) {
    await deleteStoredImages(result.imageStoragePathsToDelete);
  }
  await createModerationNoticeSafely({
    uid,
    placeId: input.placeId,
    messageId,
    moderationResult,
    moderationNoticePoints: result.moderationNoticePoints,
  });
  if (result.notifyImmediately) {
    await sendMessageNotificationsSafely({
      db,
      placeId: input.placeId,
      messageId,
      uid,
    });
  }
}

/**
 * Authoritative message creation.
 *
 * places.messageCount is public and counts only publicly visible messages.
 * places/{placeId}/counters/messageSlots.count is server-only and includes
 * scheduled messages immediately for cap enforcement.
 */
export const sendMessage = onCall<SendMessageData>(
  {enforceAppCheck: true, region: REGION, secrets: [OPENAI_API_KEY]},
  async (req) => {
    const uid = req.auth?.uid;
    if (!uid) throw new HttpsError("unauthenticated", "Sign in required.");

    const input = validateSendMessageInput(req.data, uid);
    const db = asiaWorldContext().firestore;
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

    try {
      const placeSnap = await refs.placeRef.get();
      if (!placeSnap.exists) {
        throw new HttpsError("not-found", "Note not found.");
      }
      const creatorUid =
        placeSnap.get("createdByUserId") as string | undefined;
      if (
        creatorUid &&
        await hasUserBlockBetween(db, uid, creatorUid)
      ) {
        throw new HttpsError(
          "permission-denied",
          "You cannot access this note.",
          {reason: "user_blocked"},
        );
      }
      const moderationImages = await moderationImagesFor(
        input.trimmedImageStoragePaths,
      );
      const moderationResult = await moderateContent(
        input.trimmedContent,
        moderationImages,
      );
      if (
        moderationImages.length > 0 &&
        moderationResult.action === "pending"
      ) {
        throw new HttpsError(
          "unavailable",
          "Could not check image safety. Please try again.",
          {reason: "moderation_unavailable"},
        );
      }
      if (
        moderationImages.length > 0 &&
        moderationResult.action !== "allow"
      ) {
        await recordRejectedModeration({
          db,
          userRef: refs.userRef,
          uid,
          result: moderationResult,
          sourceType: "messageImage",
        });
        throw new HttpsError(
          "failed-precondition",
          "This image could not be published because of its content.",
          {reason: "image_not_allowed"},
        );
      }
      const riskSignals = detectAppModerationRiskSignals(input.trimmedContent);
      const profile = await profileForMember(uid);
      const result = await createMessageInTransaction({
        db,
        refs,
        uid,
        input,
        profile,
        tokenPicture: req.auth?.token.picture,
        moderationResult,
        riskSignals,
        nowMs,
      });
      await runSendMessageSideEffects({
        db,
        uid,
        input,
        messageId: refs.messageRef.id,
        moderationResult,
        result,
      });

      return {
        messageId: refs.messageRef.id,
        publishAtMillis: result.publishAtMillis,
        isScheduled: result.isScheduled,
      };
    } catch (error) {
      await deleteStoredImages(input.trimmedImageStoragePaths);
      throw error;
    }
  },
);

/**
 * Records a user report and queues the message for administrator review.
 */
export const reportMessage = onCall<ReportMessageData>(
  {enforceAppCheck: true, region: REGION},
  async (req) => {
    const uid = req.auth?.uid;
    if (!uid) {
      throw new HttpsError("unauthenticated", "Sign in required.");
    }
    const input = validateReportMessageInput(req.data);
    const db = asiaWorldContext().firestore;
    const placeRef = db.collection("places").doc(input.placeId);
    const memberRef = placeRef.collection("members").doc(uid);
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
      const [placeSnap, memberSnap, messageSnap, reviewSnap, rateLimitSnap] =
        await Promise.all([
          tx.get(placeRef),
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
        !canAccessNote(placeSnap, memberSnap, uid)
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
        worldId: ASIA_WORLD_ID,
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
        lastWorldId: ASIA_WORLD_ID,
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
        worldId: ASIA_WORLD_ID,
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

async function applyMessageLikeState(
  tx: Transaction,
  db: Firestore,
  refs: MessageLikeRefs,
  input: ValidatedSetMessageLikeInput,
  uid: string,
  nowMs: number,
): Promise<LikeMutationResult> {
  const [placeSnap, messageSnap] = await Promise.all([
    tx.get(refs.placeRef),
    tx.get(refs.messageRef),
  ]);
  if (!placeSnap.exists || !messageSnap.exists) {
    throw new HttpsError("not-found", "Message not found.");
  }
  const memberSnap =
    placeSnap.get("visibility") === "private" &&
      !canMaintainNote(placeSnap, uid) ?
      await tx.get(refs.memberRef) :
      null;
  if (!canLikeMessage(placeSnap, memberSnap, messageSnap, uid, nowMs)) {
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
  const likeSnap = await tx.get(refs.likeRef);
  const result = nextLikeCount({
    currentCount: (messageSnap.get("likeCount") as number | undefined) ?? 0,
    currentlyLiked: likedStateOf(likeSnap),
    desiredLiked: input.liked,
  });
  if (!result.changed) {
    return {liked: input.liked, likeCount: result.likeCount};
  }

  tx.set(
    refs.likeRef,
    likeEdgeData({
      uid,
      liked: input.liked,
      extra: {
        placeId: input.placeId,
        messageId: input.messageId,
      },
    }),
    {merge: true},
  );
  tx.update(refs.messageRef, {likeCount: result.likeCount});
  return {liked: input.liked, likeCount: result.likeCount};
}

/**
 * Sets the caller's final desired like state for a published message.
 */
export const setMessageLike = onCall<SetMessageLikeData>(
  {enforceAppCheck: true, region: REGION},
  async (req) => {
    const uid = req.auth?.uid;
    if (!uid) throw new HttpsError("unauthenticated", "Sign in required.");

    const input = validateSetMessageLikeInput(req.data);
    const db = asiaWorldContext().firestore;
    const refs = messageLikeRefs(db, input, uid);
    const nowMs = Date.now();

    return db.runTransaction((tx) =>
      applyMessageLikeState(tx, db, refs, input, uid, nowMs),
    );
  },
);

/**
 * Soft-deletes a published message and removes its stored images.
 */
export const deleteMessage = onCall<DeleteMessageData>(
  {enforceAppCheck: true, region: REGION},
  async (req) => {
    const uid = req.auth?.uid;
    if (!uid) throw new HttpsError("unauthenticated", "Sign in required.");

    const {placeId, messageId} = req.data ?? {};
    if (typeof placeId !== "string" || placeId.length === 0) {
      throw new HttpsError("invalid-argument", "placeId is required.");
    }
    if (typeof messageId !== "string" || messageId.length === 0) {
      throw new HttpsError("invalid-argument", "messageId is required.");
    }

    const messageRef = asiaWorldContext().firestore
      .collection("places")
      .doc(placeId)
      .collection("messages")
      .doc(messageId);
    let imageStoragePaths: string[] = [];

    await asiaWorldContext().firestore.runTransaction(async (tx) => {
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
      imageStoragePaths = storedImagePaths(messageSnap.get(
        "imageStoragePaths",
      ));
      if (messageSnap.get("isDeleted") === true) return;
      tx.update(messageRef, {
        isDeleted: true,
        deletedAt: FieldValue.serverTimestamp(),
        deletedReason: "author",
        imageStoragePaths: FieldValue.delete(),
      });
    });

    await deleteStoredImages(imageStoragePaths);
    return {ok: true};
  },
);

/**
 * Cancels an unpublished scheduled message and frees its reserved slot.
 */
export const cancelScheduledMessage = onCall<CancelScheduledMessageData>(
  {enforceAppCheck: true, region: REGION},
  async (req) => {
    const uid = req.auth?.uid;
    if (!uid) throw new HttpsError("unauthenticated", "Sign in required.");

    const {placeId, messageId} = req.data ?? {};
    if (typeof placeId !== "string" || placeId.length === 0) {
      throw new HttpsError("invalid-argument", "placeId is required.");
    }
    if (typeof messageId !== "string" || messageId.length === 0) {
      throw new HttpsError("invalid-argument", "messageId is required.");
    }

    const db = asiaWorldContext().firestore;
    const placeRef = db.collection("places").doc(placeId);
    const counterRef = placeRef.collection("counters").doc("messageSlots");
    const messageRef = placeRef.collection("messages").doc(messageId);
    const nowMs = Date.now();
    let imageStoragePaths: string[] = [];

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
      imageStoragePaths = storedImagePaths(messageSnap.get(
        "imageStoragePaths",
      ));
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
      tx.delete(messageRef);
    });

    await deleteStoredImages(imageStoragePaths);
    return {ok: true};
  },
);
