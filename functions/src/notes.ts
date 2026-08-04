import {onCall, HttpsError} from "./platform/worldCallable";
import {onSchedule} from "firebase-functions/v2/scheduler";
import * as logger from "firebase-functions/logger";
import {
  DocumentReference,
  DocumentSnapshot,
  FieldValue,
  Timestamp,
} from "firebase-admin/firestore";

import {encodeGeohash} from "./geohash";
import {
  assertAccountSafetyAllows,
  assertAccountSafetyPreflight,
} from "./accountSafety";
import {
  DISCOVERY_GEOHASH_PRECISION,
  FREE_NOTE_LIMIT,
  MAP_PIN_MID_GEOHASH_PRECISION,
  MAX_PUBLISH_DELAY_DAYS,
  PREMIUM_NOTE_LIMIT,
  NOTE_EXPIRY_PRESET_DAYS,
  MAX_TITLE_LENGTH,
  MAX_SUBTITLE_LENGTH,
  REGION,
} from "./constants";
import {worldContext} from "./platform/worldContext";
import {WORLD_REGISTRY} from "./platform/worldRegistry";
import {
  hashLockSecret,
  MAX_LOCK_HINT_LENGTH,
  NOTE_PW_PEPPER,
  parseLockType,
  validateLockSecret,
} from "./noteLock";
import {
  type InternalModerationResult,
  OPENAI_API_KEY,
  assertUserCanCreateContent,
  moderateContent,
  moderateTextContent,
  recordRejectedModeration,
} from "./moderation";
import {canMaintainNote} from "./noteMaintenance";
import {
  hasValidMembership,
  isPublishedReadablePlace,
} from "./likeHelpers";
import {
  assertReportCooldown,
  reportReasonCodeOf,
  requiredReportDocumentId,
  type ReportReasonCode,
} from "./reporting";
import {hasUserBlockBetweenInTransaction} from "./userBlocks";

interface CreateNoteData {
  latitude?: unknown;
  longitude?: unknown;
  title?: unknown;
  subtitle?: unknown;
  colorHex?: unknown;
  themeId?: unknown;
  icon?: unknown;
  expiryDays?: unknown;
  visibility?: unknown;
  publishAtMillis?: unknown;
  lock?: unknown;
}

interface CreateNoteLock {
  lockType: "password" | "pattern";
  lockHint: string | null;
  hash: string;
}

interface ArchiveNoteData {
  placeId?: unknown;
}

interface SetNotePinImageData {
  placeId?: unknown;
  pinImageStoragePath?: unknown;
}

interface SetNoteThemeData {
  placeId?: unknown;
  themeId?: unknown;
}

interface ReportNoteData {
  placeId?: unknown;
  reasonCode?: unknown;
  reason?: unknown;
}

interface ValidatedReportNoteInput {
  placeId: string;
  reasonCode: ReportReasonCode;
}

const NOTE_THEME_IDS = new Set([
  "standard",
  "aurora",
  "citrus",
  "botanical",
  "neon",
  "editorial",
]);

/**
 * Returns whether [value] is one of the supported built-in note themes.
 *
 * @param {unknown} value Candidate stored theme value.
 * @return {boolean} Whether the value is supported.
 */
function isNoteThemeId(value: unknown): value is string {
  return typeof value === "string" && NOTE_THEME_IDS.has(value);
}

const UUID_V7_PATTERN =
  "[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-" +
  "[0-9a-f]{12}";

/**
 * Authoritative note creation.
 *
 * This is the ONLY way a `places` document may be created — Firestore rules
 * deny direct client creation. Enforcing the per-user note cap requires
 * counting the user's notes, which security rules cannot do; doing it here in
 * a transaction (reading + writing the same userUsage/{uid} doc) makes the
 * check race-free: two concurrent creates serialize on that document.
 *
 * The world-local userUsage/{uid}.activeNoteCount is the source of truth for
 * that world's cap. Entitlement is read from the local userEntitlements
 * mirror, so neither read needs to leave the selected world.
 */
export const createNote = onCall<CreateNoteData>(
  {
    enforceAppCheck: true,
    region: REGION,
    secrets: [NOTE_PW_PEPPER, OPENAI_API_KEY],
  },
  async (req, world) => {
    const uid = req.auth?.uid;
    if (!uid) {
      throw new HttpsError("unauthenticated", "You must be signed in.");
    }

    const {
      latitude,
      longitude,
      title,
      subtitle,
      colorHex,
      themeId,
      icon,
      expiryDays,
      publishAtMillis,
    } = req.data ?? {};

    if (
      typeof latitude !== "number" ||
      typeof longitude !== "number" ||
      latitude < -90 ||
      latitude > 90 ||
      longitude < -180 ||
      longitude > 180
    ) {
      throw new HttpsError("invalid-argument", "Invalid coordinates.");
    }
    if (!isNoteThemeId(themeId)) {
      throw new HttpsError("invalid-argument", "Invalid note theme.");
    }
    if (
      typeof title !== "string" ||
      title.trim().length === 0 ||
      title.length > MAX_TITLE_LENGTH
    ) {
      throw new HttpsError(
        "invalid-argument",
        `Title is required (max ${MAX_TITLE_LENGTH} chars).`,
      );
    }
    if (
      subtitle != null &&
      (typeof subtitle !== "string" || subtitle.length > MAX_SUBTITLE_LENGTH)
    ) {
      throw new HttpsError("invalid-argument", "Invalid subtitle.");
    }
    if (
      typeof expiryDays !== "number" ||
      !NOTE_EXPIRY_PRESET_DAYS.includes(expiryDays)
    ) {
      throw new HttpsError("invalid-argument", "Invalid expiry selection.");
    }

    const requestedVisibility =
      req.data?.visibility === "private" ? "private" : "public";
    const rawLock = req.data?.lock;
    let lock: CreateNoteLock | null = null;
    if (rawLock != null) {
      if (
        typeof rawLock !== "object" ||
        Array.isArray(rawLock) ||
        rawLock == null
      ) {
        throw new HttpsError("invalid-argument", "Invalid lock.");
      }
      const lockData = rawLock as {
        lockType?: unknown;
        password?: unknown;
        lockHint?: unknown;
      };
      const lockType = parseLockType(lockData.lockType);
      if (lockType == null) {
        throw new HttpsError("invalid-argument", "Invalid lock type.");
      }
      if (typeof lockData.password !== "string") {
        throw new HttpsError("invalid-argument", "password is required.");
      }
      const weakness = validateLockSecret(lockData.password, lockType);
      if (weakness) throw new HttpsError("invalid-argument", weakness);
      if (
        lockData.lockHint != null &&
        (
          typeof lockData.lockHint !== "string" ||
          lockData.lockHint.length > MAX_LOCK_HINT_LENGTH
        )
      ) {
        throw new HttpsError("invalid-argument", "Invalid hint.");
      }
      const trimmedHint =
        typeof lockData.lockHint === "string" &&
          lockData.lockHint.trim().length > 0 ?
          lockData.lockHint.trim() :
          null;
      lock = {
        lockType,
        lockHint: trimmedHint,
        hash: await hashLockSecret(lockData.password),
      };
    }
    if (requestedVisibility === "private" && lock == null) {
      throw new HttpsError(
        "invalid-argument",
        "Private notes require a lock.",
      );
    }
    const visibility = lock == null ? "public" : "private";
    const trimmedSubtitle =
      typeof subtitle === "string" && subtitle.trim().length > 0 ?
        subtitle.trim() :
        null;
    const trimmedTitle = (title as string).trim();
    const db = world.firestore;
    const userRef = db.collection("users").doc(uid);
    await assertAccountSafetyPreflight(
      db,
      uid,
      "contentWrite",
      Timestamp.now(),
    );
    const moderationResult = await moderateTextContent([
      `Title: ${trimmedTitle}`,
      ...(trimmedSubtitle == null ?
        [] :
        [`Description: ${trimmedSubtitle}`]),
    ].join("\n"));
    if (moderationResult.action === "pending") {
      throw new HttpsError(
        "unavailable",
        "Could not check note safety. Please try again.",
        {reason: "moderation_unavailable"},
      );
    }
    if (moderationResult.action !== "allow") {
      await recordRejectedModeration({
        db,
        userRef,
        uid,
        result: moderationResult,
        sourceType: "noteDraft",
      });
      throw new HttpsError(
        "failed-precondition",
        "This note could not be published because of its content.",
        {reason: "content_not_allowed"},
      );
    }
    const nowMillis = Date.now();
    let publishAtMs = nowMillis;
    if (publishAtMillis != null) {
      if (typeof publishAtMillis !== "number" || !isFinite(publishAtMillis)) {
        throw new HttpsError("invalid-argument", "Invalid publication time.");
      }
      const maxPublishAtMs =
        nowMillis + MAX_PUBLISH_DELAY_DAYS * 24 * 60 * 60 * 1000;
      if (publishAtMillis > maxPublishAtMs) {
        throw new HttpsError(
          "invalid-argument",
          "Publication time is too far in the future.",
        );
      }
      publishAtMs = Math.max(publishAtMillis, nowMillis);
    }

    const geohash = encodeGeohash(latitude, longitude, 6);
    const mapGeohashMid = encodeGeohash(
      latitude,
      longitude,
      MAP_PIN_MID_GEOHASH_PRECISION,
    );
    const discoveryGeohash = encodeGeohash(
      latitude,
      longitude,
      DISCOVERY_GEOHASH_PRECISION,
    );
    const publishAt = Timestamp.fromMillis(publishAtMs);
    const expiresAt = Timestamp.fromMillis(
      publishAtMs + expiryDays * 24 * 60 * 60 * 1000,
    );

    const publicProfileRef = db.collection("publicProfiles").doc(uid);
    const entitlementRef = db.collection("userEntitlements").doc(uid);
    const usageRef = db.collection("userUsage").doc(uid);
    const placeRef = db.collection("places").doc();
    const noteStateRef = userRef.collection("noteStates").doc(placeRef.id);

    await db.runTransaction(async (tx) => {
      const [publicProfileSnap, entitlementSnap, usageSnap] =
        await Promise.all([
          tx.get(publicProfileRef),
          tx.get(entitlementRef),
          tx.get(usageRef),
        ]);
      await assertAccountSafetyAllows(
        tx,
        db,
        uid,
        "contentWrite",
        Timestamp.fromMillis(nowMillis),
      );
      await assertUserCanCreateContent(tx, userRef, nowMillis);
      const isPremium = entitlementSnap.get("isPremium") === true;
      const limit = isPremium ? PREMIUM_NOTE_LIMIT : FREE_NOTE_LIMIT;
      const activeCount = (usageSnap.get("activeNoteCount") as number) ?? 0;
      if (!publicProfileSnap.exists) {
        throw new HttpsError(
          "failed-precondition",
          "Public profile missing.",
        );
      }
      const creatorName = publicProfileSnap.get("displayName") as string;
      const creatorPhotoUrl =
        publicProfileSnap.get("photoUrl") as string | null;
      const creatorPhotoVersion =
        publicProfileSnap.get("photoVersion") as number;
      const creatorProfileRevision =
        publicProfileSnap.get("revision") as number;

      if (activeCount >= limit) {
        throw new HttpsError(
          "resource-exhausted",
          isPremium ?
            `You've reached the maximum of ${limit} active notes.` :
            `Free accounts can keep ${limit} active notes. ` +
              "Upgrade to PRO for more.",
          {limit, isPremium},
        );
      }

      const placeData: Record<string, unknown> = {
        latitude,
        longitude,
        geohash,
        mapGeohashMid,
        discoveryGeohash,
        title: trimmedTitle,
        subtitle: trimmedSubtitle,
        colorHex: typeof colorHex === "string" ? colorHex : "#4CAF50",
        themeId,
        icon: typeof icon === "string" ? icon : "place",
        createdByUserId: uid,
        creatorName,
        creatorPhotoUrl,
        creatorPhotoVersion,
        creatorProfileRevision,
        maintainerIds: [uid],
        createdAt: FieldValue.serverTimestamp(),
        publishAt,
        messageCount: 0,
        likeCount: 0,
        visitorCount: 0,
        lastMessageAt: publishAt,
        visibility,
        passwordVersion: 0,
        isOpen: true,
        isArchived: false,
        expiresAt,
        footprintEnabled: true,
        moderationAction: "allow",
        moderationProvider: moderationResult.provider,
        moderationPolicyVersion: moderationResult.policyVersion,
        isModerationHidden: false,
        reviewRequired: false,
      };
      if (lock != null) {
        placeData.lockType = lock.lockType;
        if (lock.lockHint != null) {
          placeData.lockHint = lock.lockHint;
        }
      }

      tx.set(placeRef, placeData);
      tx.set(noteStateRef, {
        lastSeenMessageCount: 0,
        lastOpenedAt: FieldValue.serverTimestamp(),
        discoverySeenAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      });
      if (lock != null) {
        tx.set(placeRef.collection("secret").doc("auth"), {
          hash: lock.hash,
          passwordVersion: 0,
        });
      }

      tx.set(
        usageRef,
        {
          activeNoteCount: FieldValue.increment(1),
          updatedAt: FieldValue.serverTimestamp(),
        },
        {merge: true},
      );
    });

    return {placeId: placeRef.id};
  },
);

export const setNotePinImage = onCall<SetNotePinImageData>(
  {
    enforceAppCheck: true,
    region: REGION,
    secrets: [OPENAI_API_KEY],
  },
  async (req, world) => {
    const uid = req.auth?.uid;
    if (!uid) {
      throw new HttpsError("unauthenticated", "You must be signed in.");
    }
    const {placeId, pinImageStoragePath} = req.data ?? {};
    if (typeof placeId !== "string" || placeId.length === 0) {
      throw new HttpsError("invalid-argument", "placeId is required.");
    }
    const expectedPathPattern = new RegExp(
      `^images/pins/${placeId}/${uid}/${UUID_V7_PATTERN}[.]webp$`,
    );
    if (
      typeof pinImageStoragePath !== "string" ||
      !expectedPathPattern.test(pinImageStoragePath)
    ) {
      throw new HttpsError(
        "invalid-argument",
        "Invalid pin image storage path.",
      );
    }

    const db = world.firestore;
    await assertAccountSafetyPreflight(
      db,
      uid,
      "contentWrite",
      Timestamp.now(),
    );
    const bucket = world.bucket;
    let imageBytes: Uint8Array;
    try {
      const file = bucket.file(pinImageStoragePath);
      const [[metadata], [bytes]] = await Promise.all([
        file.getMetadata(),
        file.download(),
      ]);
      if (
        metadata.contentType !== "image/webp" ||
        Number(metadata.size ?? bytes.length) > 256 * 1024
      ) {
        throw new HttpsError(
          "invalid-argument",
          "Invalid pin image metadata.",
        );
      }
      imageBytes = bytes;
    } catch (error) {
      if (error instanceof HttpsError) throw error;
      throw new HttpsError(
        "failed-precondition",
        "Pin image upload was not found.",
      );
    }

    let moderationResult: InternalModerationResult;
    try {
      moderationResult = await moderateContent("", [{
        bytes: imageBytes,
        contentType: "image/webp",
      }]);
    } catch (error) {
      try {
        await bucket.file(pinImageStoragePath).delete({ignoreNotFound: true});
      } catch (cleanupError) {
        logger.warn(
          `Could not clean up unchecked pin image ${pinImageStoragePath}.`,
          cleanupError,
        );
      }
      throw error;
    }
    if (moderationResult.action !== "allow") {
      try {
        await bucket.file(pinImageStoragePath).delete({ignoreNotFound: true});
      } catch (error) {
        logger.warn(
          `Could not delete rejected pin image ${pinImageStoragePath}.`,
          error,
        );
      }
      if (moderationResult.action !== "pending") {
        await recordRejectedModeration({
          db,
          userRef: db.collection("users").doc(uid),
          uid,
          result: moderationResult,
          sourceType: "pinImage",
        });
      }
      throw new HttpsError(
        moderationResult.action === "pending" ?
          "unavailable" :
          "failed-precondition",
        moderationResult.action === "pending" ?
          "Could not check image safety. Please try again." :
          "This image could not be used because of its content.",
        {
          reason: moderationResult.action === "pending" ?
            "moderation_unavailable" :
            "image_not_allowed",
        },
      );
    }
    const placeRef = db.collection("places").doc(placeId);
    let previousPath: string | null;
    try {
      previousPath = await db.runTransaction(async (tx) => {
        const placeSnap = await tx.get(placeRef);
        await assertAccountSafetyAllows(
          tx,
          db,
          uid,
          "contentWrite",
          Timestamp.now(),
        );
        if (!placeSnap.exists) {
          throw new HttpsError("not-found", "Note not found.");
        }
        const creatorUid =
          placeSnap.get("createdByUserId") as string | undefined;
        if (
          creatorUid &&
          await hasUserBlockBetweenInTransaction(tx, db, uid, creatorUid)
        ) {
          throw new HttpsError(
            "permission-denied",
            "You cannot change this note.",
            {reason: "user_blocked"},
          );
        }
        if (!canMaintainNote(placeSnap, uid)) {
          throw new HttpsError(
            "permission-denied",
            "You cannot change this note.",
          );
        }
        if (
          placeSnap.get("isArchived") === true ||
          placeSnap.get("isModerationHidden") !== false
        ) {
          throw new HttpsError(
            "failed-precondition",
            "This note cannot change its pin image.",
          );
        }
        const previous = placeSnap.get("pinImageStoragePath");
        tx.update(placeRef, {pinImageStoragePath});
        return typeof previous === "string" ? previous : null;
      });
    } catch (error) {
      try {
        await bucket.file(pinImageStoragePath).delete({ignoreNotFound: true});
      } catch (cleanupError) {
        logger.warn(
          `Could not clean up unattached pin image ${pinImageStoragePath}.`,
          cleanupError,
        );
      }
      throw error;
    }

    if (previousPath != null && previousPath !== pinImageStoragePath) {
      try {
        await bucket.file(previousPath).delete({
          ignoreNotFound: true,
        });
      } catch (error) {
        logger.warn(`Could not delete old pin image ${previousPath}.`, error);
      }
    }
  },
);

/**
 * Validates the payload accepted by reportNote.
 *
 * @param {ReportNoteData|undefined} data Raw callable data.
 * @return {ValidatedReportNoteInput} Validated report input.
 */
function validateReportNoteInput(
  data: ReportNoteData | undefined,
): ValidatedReportNoteInput {
  return {
    placeId: requiredReportDocumentId(data?.placeId, "placeId"),
    reasonCode: reportReasonCodeOf(data?.reasonCode ?? data?.reason),
  };
}

/**
 * Returns whether the caller can report the current note snapshot.
 *
 * @param {DocumentSnapshot} placeSnap Note document.
 * @param {DocumentSnapshot} memberSnap Caller membership document.
 * @param {string} uid Caller user id.
 * @param {number} nowMs Current time in milliseconds.
 * @return {boolean} Whether the note can be reported.
 */
function canReportNote(
  placeSnap: DocumentSnapshot,
  memberSnap: DocumentSnapshot,
  uid: string,
  nowMs: number,
): boolean {
  if (!isPublishedReadablePlace(placeSnap, nowMs)) return false;
  if (canMaintainNote(placeSnap, uid)) return false;
  if (placeSnap.get("visibility") !== "private") return true;
  return hasValidMembership(placeSnap, memberSnap);
}

/** Records a user report and queues the note for administrator review. */
export const reportNote = onCall<ReportNoteData>(
  {enforceAppCheck: true, region: REGION},
  async (req, world) => {
    const uid = req.auth?.uid;
    if (!uid) {
      throw new HttpsError("unauthenticated", "Sign in required.");
    }
    const input = validateReportNoteInput(req.data);
    const db = world.firestore;
    const placeRef = db.collection("places").doc(input.placeId);
    const memberRef = placeRef.collection("members").doc(uid);
    const reportRef = db.collection("reports").doc();
    const reviewRef = db
      .collection("moderationReviews")
      .doc(`note_${input.placeId}`);
    const rateLimitRef = db
      .collection("users")
      .doc(uid)
      .collection("rateLimits")
      .doc("reportContent");
    const reportCreatedAt = Timestamp.now();

    await db.runTransaction(async (tx) => {
      const [placeSnap, memberSnap, reviewSnap, rateLimitSnap] =
        await Promise.all([
          tx.get(placeRef),
          tx.get(memberRef),
          tx.get(reviewRef),
          tx.get(rateLimitRef),
        ]);
      assertReportCooldown(rateLimitSnap, reportCreatedAt);
      if (!placeSnap.exists) {
        throw new HttpsError("not-found", "Note not found.");
      }
      if (
        placeSnap.get("createdByUserId") === uid ||
        canMaintainNote(placeSnap, uid)
      ) {
        throw new HttpsError(
          "failed-precondition",
          "You cannot report a note you maintain.",
          {reason: "self_report"},
        );
      }
      if (
        !canReportNote(placeSnap, memberSnap, uid, reportCreatedAt.toMillis())
      ) {
        throw new HttpsError(
          "permission-denied",
          "You cannot report this note.",
        );
      }

      const title =
        typeof placeSnap.get("title") === "string" ?
          placeSnap.get("title") as string :
          "";
      const subtitle =
        typeof placeSnap.get("subtitle") === "string" ?
          placeSnap.get("subtitle") as string :
          null;
      const pinImageStoragePath =
        typeof placeSnap.get("pinImageStoragePath") === "string" ?
          placeSnap.get("pinImageStoragePath") as string :
          null;
      const targetPath = `places/${input.placeId}`;

      tx.set(reportRef, {
        worldId: world.worldId,
        targetType: "note",
        targetId: input.placeId,
        targetPath,
        placeId: input.placeId,
        reporterId: uid,
        reportedUserId: placeSnap.get("createdByUserId") ?? null,
        reasonCode: input.reasonCode,
        status: "open",
        createdAt: reportCreatedAt,
      });
      tx.set(rateLimitRef, {
        lastWorldId: world.worldId,
        lastCreatedAt: reportCreatedAt,
        lastTargetType: "note",
        lastTargetId: input.placeId,
        lastPlaceId: input.placeId,
        lastMessageId: FieldValue.delete(),
      }, {merge: true});
      tx.set(reviewRef, {
        worldId: world.worldId,
        userId: placeSnap.get("createdByUserId") ?? null,
        targetType: "note",
        targetId: input.placeId,
        targetPath,
        placeId: input.placeId,
        content: [title, subtitle]
          .filter((value): value is string => value != null)
          .join("\n"),
        contentFields: {title, subtitle},
        imageStoragePaths:
          pinImageStoragePath == null ? [] : [pinImageStoragePath],
        reviewSources: FieldValue.arrayUnion("userReport"),
        reportCount: FieldValue.increment(1),
        reportReasonsSummary: FieldValue.arrayUnion(input.reasonCode),
        lastReportedAt: FieldValue.serverTimestamp(),
        status: "open",
        ...(reviewSnap.exists ? {} : {createdAt: FieldValue.serverTimestamp()}),
      }, {merge: true});
    });

    return {ok: true, placeId: input.placeId};
  },
);

/** Updates the built-in appearance theme of an active note. */
export const setNoteTheme = onCall<SetNoteThemeData>(
  {enforceAppCheck: true, region: REGION},
  async (req, world) => {
    const uid = req.auth?.uid;
    if (!uid) {
      throw new HttpsError("unauthenticated", "You must be signed in.");
    }
    const {placeId, themeId} = req.data ?? {};
    if (typeof placeId !== "string" || placeId.length === 0) {
      throw new HttpsError("invalid-argument", "placeId is required.");
    }
    if (!isNoteThemeId(themeId)) {
      throw new HttpsError("invalid-argument", "Invalid note theme.");
    }

    const db = world.firestore;
    const placeRef = db.collection("places").doc(placeId);
    await db.runTransaction(async (tx) => {
      const placeSnap = await tx.get(placeRef);
      await assertAccountSafetyAllows(
        tx,
        db,
        uid,
        "contentWrite",
        Timestamp.now(),
      );
      if (!placeSnap.exists) {
        throw new HttpsError("not-found", "Note not found.");
      }
      const creatorUid =
        placeSnap.get("createdByUserId") as string | undefined;
      if (
        creatorUid &&
        await hasUserBlockBetweenInTransaction(tx, db, uid, creatorUid)
      ) {
        throw new HttpsError(
          "permission-denied",
          "You cannot change this note's theme.",
          {reason: "user_blocked"},
        );
      }
      if (!canMaintainNote(placeSnap, uid)) {
        throw new HttpsError(
          "permission-denied",
          "You cannot change this note's theme.",
        );
      }
      if (placeSnap.get("isArchived") === true) {
        throw new HttpsError(
          "failed-precondition",
          "Archived notes cannot change theme.",
        );
      }
      if (placeSnap.get("themeId") !== themeId) {
        tx.update(placeRef, {themeId});
      }
    });
  },
);

/**
 * Creator-only terminal archive. The place update and active-note counter
 * decrement share a transaction so retries cannot free the slot twice.
 */
export const archiveNote = onCall<ArchiveNoteData>(
  {enforceAppCheck: true, region: REGION},
  async (req, world) => {
    const uid = req.auth?.uid;
    if (!uid) {
      throw new HttpsError("unauthenticated", "You must be signed in.");
    }
    const {placeId} = req.data ?? {};
    if (typeof placeId !== "string" || placeId.length === 0) {
      throw new HttpsError("invalid-argument", "placeId is required.");
    }

    const db = world.firestore;
    const placeRef = db.collection("places").doc(placeId);
    const archived = await db.runTransaction(async (tx) => {
      const placeSnap = await tx.get(placeRef);
      if (!placeSnap.exists) {
        throw new HttpsError("not-found", "Note not found.");
      }
      if (placeSnap.get("createdByUserId") !== uid) {
        throw new HttpsError(
          "permission-denied",
          "Only the note creator can archive it.",
        );
      }
      if (placeSnap.get("isArchived") === true) return false;

      const usageRef = db.collection("userUsage").doc(uid);
      const usageSnap = await tx.get(usageRef);
      const activeCount =
        (usageSnap.get("activeNoteCount") as number | undefined) ?? 0;

      tx.update(placeRef, {
        isArchived: true,
        archivedAt: FieldValue.serverTimestamp(),
        isOpen: false,
      });
      tx.set(
        usageRef,
        {
          activeNoteCount: Math.max(0, activeCount - 1),
          updatedAt: FieldValue.serverTimestamp(),
        },
        {merge: true},
      );
      return true;
    });

    if (archived) {
      try {
        const invites = await db
          .collection("invites")
          .where("placeId", "==", placeId)
          .get();
        const batch = db.batch();
        let revoked = 0;
        for (const invite of invites.docs) {
          if (invite.get("revoked") !== true) {
            batch.update(invite.ref, {revoked: true});
            revoked++;
          }
        }
        if (revoked > 0) await batch.commit();
      } catch (error) {
        logger.warn(
          `archiveNote: could not revoke invites for ${placeId}.`,
          error,
        );
      }
    }

    return {archived};
  },
);

/**
 * Scheduled auto-archive.
 *
 * Once per day, moves every note past its expiry into the archived state:
 *   • isArchived = true (so it drops out of proximity search and can no longer
 *     accept messages — both already enforced client-side / by rules),
 *   • archivedAt timestamp,
 *   • decrements the creator's world-local activeNoteCount so the slot frees
 *     up against that world's creation cap.
 *
 * Archival is terminal — there is no return to active. Notes are processed in
 * batches; because each batch flips isArchived to true, the same query no
 * longer returns them, so re-querying until empty drains the backlog.
 *
 * Requires composite index (isArchived ASC, expiresAt ASC).
 *
 * @param {string} worldId Trusted catalog world to archive.
 * @return {Promise<number>} Number of notes archived during this run.
 */
export async function archiveExpiredNotesForWorld(
  worldId: string,
): Promise<number> {
  const db = worldContext(worldId).firestore;
  const now = Timestamp.now();
  const batchSize = 200;
  let totalArchived = 0;

  for (;;) {
    const snap = await db
      .collection("places")
      .where("isArchived", "==", false)
      .where("expiresAt", "<=", now)
      .limit(batchSize)
      .get();

    if (snap.empty) break;

    const placesByCreator = new Map<string, DocumentReference[]>();
    for (const doc of snap.docs) {
      const creatorId = doc.get("createdByUserId") as string;
      const refs = placesByCreator.get(creatorId) ?? [];
      refs.push(doc.ref);
      placesByCreator.set(creatorId, refs);
    }

    const archivedCounts = await Promise.all(
      [...placesByCreator.entries()].map(async ([creatorId, placeRefs]) => {
        return db.runTransaction(async (tx) => {
          const usageRef = db.collection("userUsage").doc(creatorId);
          const [usageSnap, ...placeSnaps] = await Promise.all([
            tx.get(usageRef),
            ...placeRefs.map((ref) => tx.get(ref)),
          ]);
          const expiredPlacesToArchive = placeSnaps.filter((placeSnap) => {
            const expiresAt =
                placeSnap.get("expiresAt") as Timestamp | undefined;
            return placeSnap.exists &&
                placeSnap.get("isArchived") !== true &&
                placeSnap.get("createdByUserId") === creatorId &&
                expiresAt != null &&
                expiresAt.toMillis() <= now.toMillis();
          });
          if (expiredPlacesToArchive.length === 0) return 0;

          for (const placeSnap of expiredPlacesToArchive) {
            tx.update(placeSnap.ref, {
              isArchived: true,
              archivedAt: FieldValue.serverTimestamp(),
              isOpen: false,
            });
          }
          const activeCount =
              (usageSnap.get("activeNoteCount") as number | undefined) ?? 0;
          tx.set(
            usageRef,
            {
              activeNoteCount: Math.max(
                0,
                activeCount - expiredPlacesToArchive.length,
              ),
              updatedAt: FieldValue.serverTimestamp(),
            },
            {merge: true},
          );
          return expiredPlacesToArchive.length;
        });
      }),
    );
    totalArchived += archivedCounts.reduce((sum, count) => sum + count, 0);
    if (snap.size < batchSize) break;
  }

  logger.info("Expired notes archived.", {worldId, totalArchived});
  return totalArchived;
}

/**
 * Creates one regional expired-note schedule.
 *
 * @param {string} worldId Trusted catalog world to archive.
 * @return {ScheduleFunction} Regional scheduled function.
 */
function archiveExpiredNotesSchedule(worldId: string) {
  const world = WORLD_REGISTRY.requireWorld(worldId);
  return onSchedule(
    {
      schedule: "every 24 hours",
      timeZone: "Etc/UTC",
      region: world.functionsRegion,
      retryCount: 3,
      maxInstances: 1,
    },
    async () => {
      await archiveExpiredNotesForWorld(worldId);
    },
  );
}

export const archiveAsiaExpiredNotes = archiveExpiredNotesSchedule("asia");
export const archiveNorthAmericaExpiredNotes =
  archiveExpiredNotesSchedule("northAmerica");
export const archiveEuropeExpiredNotes =
  archiveExpiredNotesSchedule("europe");
