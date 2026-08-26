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
import {enqueueModerationJob} from "./moderationJobs";
import {
  EVALUATE_NOTE_MODERATION_JOB,
  noteModerationInputHash,
} from "./noteModeration";
import {
  newPinImageCandidate,
  parsePinImageCandidate,
  pinImageCandidateStoragePath,
} from "./pinImageCandidate";
import {EVALUATE_PIN_IMAGE_MODERATION_JOB} from "./pinImageModeration";
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
import {
  bindImageUploadsToContent,
  imageUploadId,
} from "./imageUploads";
import {enqueueStorageObjectDeletion} from "./storageObjectCleanup";
import {
  enqueueArchivedNoteAdministratorInvitationRevocation,
} from "./noteAdministratorInviteCleanup";

interface CreateNoteData {
  placeId?: unknown;
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
    auditAction: "note.create",
    enforceAppCheck: true,
    region: REGION,
    secrets: [NOTE_PW_PEPPER],
  },
  async (req, world) => {
    const uid = req.auth?.uid;
    if (!uid) {
      throw new HttpsError("unauthenticated", "You must be signed in.");
    }

    const {
      placeId,
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

    if (typeof placeId !== "string" ||
        !new RegExp(`^${UUID_V7_PATTERN}$`).test(placeId)) {
      throw new HttpsError("invalid-argument", "Invalid placeId.");
    }
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
    const placeRef = db.collection("places").doc(placeId);
    const noteStateRef = userRef.collection("noteStates").doc(placeRef.id);
    const moderationInputHash = noteModerationInputHash(
      trimmedTitle,
      trimmedSubtitle,
    );

    const creationResult = await db.runTransaction(async (tx) => {
      const [placeSnap, publicProfileSnap, entitlementSnap, usageSnap] =
        await Promise.all([
          tx.get(placeRef),
          tx.get(publicProfileRef),
          tx.get(entitlementRef),
          tx.get(usageRef),
        ]);
      if (placeSnap.exists) {
        if (placeSnap.get("createdByUserId") !== uid ||
            placeSnap.get("moderationInputHash") !== moderationInputHash) {
          throw new HttpsError(
            "already-exists",
            "This note identifier is already in use.",
          );
        }
        return {
          created: false,
          moderationAction: String(placeSnap.get("moderationAction")),
        };
      }
      await assertAccountSafetyAllows(
        tx,
        db,
        uid,
        "contentWrite",
        Timestamp.fromMillis(nowMillis),
      );
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
        administratorCount: 0,
        pendingAdministratorInviteCount: 0,
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
        moderationAction: "pending",
        moderationInputHash,
        moderationProvider: null,
        moderationPolicyVersion: null,
        moderationCheckedAt: null,
        isModerationHidden: false,
        isSensitive: false,
        reviewRequired: false,
        activeNoteSlotReleasedAt: null,
        moderationRetentionStartedAt: null,
        moderationRetentionPurgeStartedAt: null,
        moderationHiddenJobId: null,
        moderationSafetyAppliedAt: null,
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
      enqueueModerationJob(
        tx,
        db,
        {
          jobType: EVALUATE_NOTE_MODERATION_JOB,
          targetPath: placeRef.path,
          inputHash: moderationInputHash,
          world: world.worldId,
        },
        Timestamp.fromMillis(nowMillis),
      );
      return {created: true, moderationAction: "pending"};
    });

    return {
      placeId: placeRef.id,
      ...creationResult,
    };
  },
);

/** Attaches a public-pending pin candidate and queues regional evaluation. */
export const setNotePinImage = onCall<SetNotePinImageData>(
  {auditAction: "note.pinImage.set", enforceAppCheck: true, region: REGION},
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
    if (typeof pinImageStoragePath !== "string" ||
        !expectedPathPattern.test(pinImageStoragePath)) {
      throw new HttpsError(
        "invalid-argument",
        "Invalid pin image storage path.",
      );
    }

    const db = world.firestore;
    const placeRef = db.collection("places").doc(placeId);
    const administratorRef = placeRef.collection("administrators").doc(uid);
    const changedAt = Timestamp.now();
    const nextCandidate = newPinImageCandidate({
      storagePath: pinImageStoragePath,
      placeId,
      requestedByUid: uid,
    }, changedAt);
    await assertAccountSafetyPreflight(
      db,
      uid,
      "contentWrite",
      changedAt,
    );
    try {
      const [metadata] = await world.bucket
        .file(pinImageStoragePath)
        .getMetadata();
      if (metadata.contentType !== "image/webp" ||
          Number(metadata.size ?? 0) > 256 * 1024) {
        throw new HttpsError(
          "invalid-argument",
          "Invalid pin image metadata.",
        );
      }
    } catch (error) {
      if (error instanceof HttpsError) throw error;
      throw new HttpsError(
        "failed-precondition",
        "Pin image upload was not found.",
      );
    }
    const accepted = await db.runTransaction(async (tx) => {
      const [place, administrator] = await Promise.all([
        tx.get(placeRef),
        tx.get(administratorRef),
      ]);
      await assertAccountSafetyAllows(
        tx,
        db,
        uid,
        "contentWrite",
        changedAt,
      );
      if (!place.exists) {
        throw new HttpsError("not-found", "Note not found.");
      }
      const creatorUid = place.get("createdByUserId");
      if (typeof creatorUid === "string" &&
          await hasUserBlockBetweenInTransaction(
            tx,
            db,
            uid,
            creatorUid,
          )) {
        throw new HttpsError(
          "permission-denied",
          "You cannot change this note.",
          {reason: "user_blocked"},
        );
      }
      if (!canMaintainNote(place, administrator, uid)) {
        throw new HttpsError(
          "permission-denied",
          "You cannot change this note.",
        );
      }
      if (place.get("isArchived") === true ||
          place.get("isModerationHidden") !== false) {
        throw new HttpsError(
          "failed-precondition",
          "This note cannot change its pin image.",
        );
      }
      await bindImageUploadsToContent(
        tx,
        db,
        [pinImageStoragePath],
        placeRef.path,
        changedAt,
      );

      const currentValue = place.get("pinImageCandidate");
      let currentCandidate = null;
      if (currentValue !== undefined && currentValue !== null) {
        currentCandidate = parsePinImageCandidate(currentValue, placeId);
      }
      if (currentCandidate?.inputHash === nextCandidate.inputHash ||
          (currentCandidate === null &&
           place.get("pinImageStoragePath") === pinImageStoragePath)) {
        return false;
      }
      if (currentCandidate !== null) {
        enqueueStorageObjectDeletion(tx, db, {
          sourceOperationId:
            `replacedPendingPin:${imageUploadId(
              currentCandidate.storagePath,
            )}`,
          revision: 1,
          world: world.worldId,
          objectPath: currentCandidate.storagePath,
          createdAt: changedAt,
        });
      }
      tx.update(placeRef, {
        pinImageCandidate: {...nextCandidate},
      });
      enqueueModerationJob(
        tx,
        db,
        {
          jobType: EVALUATE_PIN_IMAGE_MODERATION_JOB,
          targetPath: placeRef.path,
          inputHash: nextCandidate.inputHash,
          world: world.worldId,
        },
        changedAt,
      );
      return true;
    });
    return {
      accepted,
      moderationAction: "pending",
    };
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
 * @param {DocumentSnapshot} administratorSnap Caller administrator document.
 * @param {DocumentSnapshot} memberSnap Caller membership document.
 * @param {string} uid Caller user id.
 * @param {number} nowMs Current time in milliseconds.
 * @return {boolean} Whether the note can be reported.
 */
function canReportNote(
  placeSnap: DocumentSnapshot,
  administratorSnap: DocumentSnapshot,
  memberSnap: DocumentSnapshot,
  uid: string,
  nowMs: number,
): boolean {
  if (!isPublishedReadablePlace(placeSnap, nowMs)) return false;
  if (canMaintainNote(placeSnap, administratorSnap, uid)) return false;
  if (placeSnap.get("visibility") !== "private") return true;
  return hasValidMembership(placeSnap, memberSnap);
}

/** Records a user report and queues the note for administrator review. */
export const reportNote = onCall<ReportNoteData>(
  {auditAction: "note.report", enforceAppCheck: true, region: REGION},
  async (req, world) => {
    const uid = req.auth?.uid;
    if (!uid) {
      throw new HttpsError("unauthenticated", "Sign in required.");
    }
    const input = validateReportNoteInput(req.data);
    const db = world.firestore;
    const placeRef = db.collection("places").doc(input.placeId);
    const memberRef = placeRef.collection("members").doc(uid);
    const administratorRef = placeRef.collection("administrators").doc(uid);
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
      const [
        placeSnap,
        administratorSnap,
        memberSnap,
        reviewSnap,
        rateLimitSnap,
      ] =
        await Promise.all([
          tx.get(placeRef),
          tx.get(administratorRef),
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
        canMaintainNote(placeSnap, administratorSnap, uid)
      ) {
        throw new HttpsError(
          "failed-precondition",
          "You cannot report a note you maintain.",
          {reason: "self_report"},
        );
      }
      if (
        !canReportNote(
          placeSnap,
          administratorSnap,
          memberSnap,
          uid,
          reportCreatedAt.toMillis(),
        )
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
      const acceptedPinImageStoragePath =
        typeof placeSnap.get("pinImageStoragePath") === "string" ?
          placeSnap.get("pinImageStoragePath") as string :
          null;
      const pinImageStoragePath = pinImageCandidateStoragePath(
        placeSnap.get("pinImageCandidate"),
      ) ?? acceptedPinImageStoragePath;
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
  {auditAction: "note.theme.set", enforceAppCheck: true, region: REGION},
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
    const administratorRef = placeRef.collection("administrators").doc(uid);
    await db.runTransaction(async (tx) => {
      const [placeSnap, administratorSnap] = await Promise.all([
        tx.get(placeRef),
        tx.get(administratorRef),
      ]);
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
      if (!canMaintainNote(placeSnap, administratorSnap, uid)) {
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
  {auditAction: "note.archive", enforceAppCheck: true, region: REGION},
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
    const cleanupCreatedAt = Timestamp.now();
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
      const activeNoteSlotAlreadyReleased =
        placeSnap.get("activeNoteSlotReleasedAt") instanceof Timestamp;

      tx.update(placeRef, {
        isArchived: true,
        archivedAt: FieldValue.serverTimestamp(),
        isOpen: false,
      });
      tx.set(
        usageRef,
        {
          activeNoteCount: Math.max(
            0,
            activeCount - (activeNoteSlotAlreadyReleased ? 0 : 1),
          ),
          updatedAt: FieldValue.serverTimestamp(),
        },
        {merge: true},
      );
      enqueueArchivedNoteAdministratorInvitationRevocation(
        tx,
        db,
        world.worldId,
        placeId,
        cleanupCreatedAt,
      );
      return true;
    });

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
          const activeSlotHoldingPlaceCount = expiredPlacesToArchive.filter(
            (placeSnap) =>
              !(placeSnap.get("activeNoteSlotReleasedAt") instanceof
                Timestamp),
          ).length;

          for (const placeSnap of expiredPlacesToArchive) {
            tx.update(placeSnap.ref, {
              isArchived: true,
              archivedAt: FieldValue.serverTimestamp(),
              isOpen: false,
            });
            enqueueArchivedNoteAdministratorInvitationRevocation(
              tx,
              db,
              worldId,
              placeSnap.id,
              now,
            );
          }
          const activeCount =
              (usageSnap.get("activeNoteCount") as number | undefined) ?? 0;
          tx.set(
            usageRef,
            {
              activeNoteCount: Math.max(
                0,
                activeCount - activeSlotHoldingPlaceCount,
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
