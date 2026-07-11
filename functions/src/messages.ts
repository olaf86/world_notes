/* eslint-disable require-jsdoc */
import {onCall, HttpsError} from "firebase-functions/v2/https";
import {
  DocumentReference,
  DocumentSnapshot,
  FieldValue,
  Firestore,
  Timestamp,
  getFirestore,
} from "firebase-admin/firestore";
import {getStorage} from "firebase-admin/storage";
import * as logger from "firebase-functions/logger";

import {
  MAX_MESSAGE_IMAGES,
  MAX_MESSAGE_PUBLISH_DELAY_DAYS,
  MAX_MESSAGES_PER_THREAD,
  REGION,
} from "./constants";
import {
  type AppModerationRiskSignal,
  type InternalModerationResult,
  OPENAI_API_KEY,
  applyModerationToUser,
  assertUserCanCreateContent,
  createModerationNoticeIfNeeded,
  detectAppModerationRiskSignals,
  hasReviewRecommendedRiskSignal,
  moderationAuditFields,
  moderateTextContent,
  moderationFields,
} from "./moderation";
import {profileForMember} from "./userProfile";
import {
  sendMyNotesMessageNotifications,
  sendNearbyInRangeMessageNotifications,
} from "./notifications";
import {canMaintainNote} from "./noteMaintenance";

interface SendMessageData {
  messageId?: unknown;
  placeId?: unknown;
  content?: unknown;
  imageStoragePaths?: unknown;
  publishAtMillis?: unknown;
}

interface ValidatedSendMessageInput {
  messageId: string;
  placeId: string;
  trimmedContent: string;
  trimmedImageStoragePaths: string[];
  publishAtMillis?: unknown;
}

interface SendMessageRefs {
  placeRef: DocumentReference;
  userRef: DocumentReference;
  memberRef: DocumentReference;
  counterRef: DocumentReference;
  messageRef: DocumentReference;
  moderationReviewRef: DocumentReference;
}

interface SendMessageProfile {
  displayName: string | null;
}

type ModerationReviewSource = "provider" | "riskSignal";

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

function sendMessageRefs(
  db: Firestore,
  input: ValidatedSendMessageInput,
  uid: string,
): SendMessageRefs {
  const placeRef = db.collection("places").doc(input.placeId);
  return {
    placeRef,
    userRef: db.collection("users").doc(uid),
    memberRef: placeRef.collection("members").doc(uid),
    counterRef: placeRef.collection("counters").doc("messageSlots"),
    messageRef: placeRef.collection("messages").doc(input.messageId),
    moderationReviewRef: db
      .collection("moderationReviews")
      .doc(`${input.placeId}_${input.messageId}`),
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
  };
}

function isModerationRemoval(
  moderationResult: InternalModerationResult,
): boolean {
  return moderationResult.action === "hidden";
}

async function deleteStoredImages(storagePaths: string[]): Promise<void> {
  if (storagePaths.length === 0) return;
  const bucket = getStorage().bucket();
  for (const storagePath of storagePaths) {
    try {
      await bucket.file(storagePath).delete({ignoreNotFound: true});
    } catch (error) {
      logger.warn(`Could not delete message image ${storagePath}.`, error);
    }
  }
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
    isDeleted: removedByModeration,
    deletedAt: removedByModeration ?
      FieldValue.serverTimestamp() :
      null,
    deletedReason: removedByModeration ? "moderation" : null,
    ...moderationFields(moderationResult),
    ...(riskSignals.length > 0 ? {moderationRiskSignals: riskSignals} : {}),
    isPubliclyVisible,
    reportCount: 0,
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
  const reviewSource: ModerationReviewSource =
    moderationResult.action !== "allow" &&
      moderationResult.action !== "pending" ?
      "provider" :
      "riskSignal";
  return {
    userId: uid,
    placeId,
    messageId,
    messagePath: `places/${placeId}/messages/${messageId}`,
    content: submittedContent,
    imageStoragePaths: submittedImageStoragePaths,
    reviewSource,
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

function hasValidMembership(
  placeSnap: DocumentSnapshot,
  memberSnap: DocumentSnapshot | null,
): boolean {
  if (!memberSnap?.exists) return false;
  return memberSnap.get("invited") === true ||
    memberSnap.get("viaPasswordVersion") === placeSnap.get("passwordVersion");
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
      return;
    }

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
    tx.set(refs.messageRef, {
      ...messageDocumentData({
        placeId: input.placeId,
        uid,
        profileDisplayName: profile.displayName,
        tokenPicture,
        content: input.trimmedContent,
        imageStoragePaths: input.trimmedImageStoragePaths,
        publishAt,
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
  try {
    await sendNearbyInRangeMessageNotifications(db, placeId, messageId, uid);
  } catch (error) {
    logger.error(
      "sendMessage: failed to send nearby notification for " +
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
    const db = getFirestore();
    const refs = sendMessageRefs(db, input, uid);
    const nowMs = Date.now();
    const existingResult = await existingMessageResult(
      refs.messageRef,
      uid,
      nowMs,
    );
    if (existingResult) return existingResult;

    const moderationResult = await moderateTextContent(input.trimmedContent);
    const riskSignals = detectAppModerationRiskSignals(input.trimmedContent);
    const profile = await profileForMember(
      uid,
      req.auth?.token.name,
    );
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
    };
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

    const messageRef = getFirestore()
      .collection("places")
      .doc(placeId)
      .collection("messages")
      .doc(messageId);
    let imageStoragePaths: string[] = [];

    await getFirestore().runTransaction(async (tx) => {
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

    const db = getFirestore();
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
