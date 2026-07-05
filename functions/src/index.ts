import {setGlobalOptions} from "firebase-functions/v2";
import {onCall, HttpsError} from "firebase-functions/v2/https";
import {onSchedule} from "firebase-functions/v2/scheduler";
import * as logger from "firebase-functions/logger";
import {initializeApp} from "firebase-admin/app";
import {
  DocumentReference,
  getFirestore,
  FieldValue,
  Timestamp,
} from "firebase-admin/firestore";
import {getStorage} from "firebase-admin/storage";

import {encodeGeohash} from "./geohash";
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
import {
  hashLockSecret,
  MAX_LOCK_HINT_LENGTH,
  NOTE_PW_PEPPER,
  parseLockType,
  validateLockSecret,
} from "./noteLock";
import {assertUserCanCreateContent} from "./moderation";
import {canMaintainNote} from "./noteMaintenance";

initializeApp();
setGlobalOptions({maxInstances: 10, region: REGION});

// Password set/verify functions. They set region explicitly in their own
// options because, being defined during module import (before this file's
// setGlobalOptions runs), the global region would not otherwise apply.
export {setNotePassword, unlockNote} from "./notePassword";

// Authoritative message writes plus the schedule that makes delayed messages
// public at publishAt. Region set in their own options.
export {sendMessage, deleteMessage, cancelScheduledMessage} from "./messages";
export {aggregatePublishedMessages} from "./messageTriggers";

// Invite-link functions (share-link access to private notes). Region set in
// their own options.
export {
  getInviteLink,
  createInviteLink,
  claimInvite,
  revokeInvite,
  revokeNoteAccess,
  grantNoteMaintainer,
  revokeNoteMaintainer,
} from "./invites";

// Push notification preferences and FCM token registration.
export {
  registerFcmToken,
  deleteFcmToken,
  setMyNotesNotificationEnabled,
  setMyNotesNotificationPreviewEnabled,
  setNearbyNotification,
  markNearbyNotificationRead,
  markNearbyNotificationInRange,
  checkNearbyUnread,
} from "./notifications";

// User profile updates. Nickname changes keep future posts using the new name
// and refresh note access-list member labels.
export {updateDisplayName} from "./userProfile";

// Map exploration pin summaries and detail-entry proximity checks.
export {listMapPins, validateNoteAccess} from "./mapPins";

interface CreateNoteData {
  latitude?: unknown;
  longitude?: unknown;
  title?: unknown;
  subtitle?: unknown;
  colorHex?: unknown;
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

const UUID_V7_PATTERN =
  "[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-" +
  "[0-9a-f]{12}";

/**
 * Authoritative note creation.
 *
 * This is the ONLY way a `places` document may be created — Firestore rules
 * deny direct client creation. Enforcing the per-user note cap requires
 * counting the user's notes, which security rules cannot do; doing it here in
 * a transaction (reading + writing the same users/{uid} doc) makes the check
 * race-free: two concurrent creates serialize on that document.
 *
 * The active-note counter (users/{uid}.activeNoteCount) is the source of
 * truth for the cap. It is incremented here and decremented by the
 * auto-archive function (Phase 3 #2).
 */
export const createNote = onCall<CreateNoteData>(
  {enforceAppCheck: true, secrets: [NOTE_PW_PEPPER]},
  async (req) => {
    const uid = req.auth?.uid;
    if (!uid) {
      throw new HttpsError("unauthenticated", "You must be signed in.");
    }

    // ── Validate input ──────────────────────────────────────────────────
    const {
      latitude,
      longitude,
      title,
      subtitle,
      colorHex,
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
      // Small grace window for clock skew and tap-to-create latency.
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

    const db = getFirestore();
    const userRef = db.collection("users").doc(uid);
    const placeRef = db.collection("places").doc();

    await db.runTransaction(async (tx) => {
      const userSnap = await tx.get(userRef);
      await assertUserCanCreateContent(tx, userRef, nowMillis);
      const isPremium = userSnap.get("isPremium") === true;
      const limit = isPremium ? PREMIUM_NOTE_LIMIT : FREE_NOTE_LIMIT;
      const activeCount = (userSnap.get("activeNoteCount") as number) ?? 0;
      const storedDisplayName = userSnap.get("displayName");
      const creatorName =
        typeof storedDisplayName === "string" &&
          storedDisplayName.trim().length > 0 ?
          storedDisplayName.trim() :
          "Unknown user";

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
        title: (title as string).trim(),
        subtitle: trimmedSubtitle,
        colorHex: typeof colorHex === "string" ? colorHex : "#4CAF50",
        icon: typeof icon === "string" ? icon : "place",
        createdByUserId: uid,
        creatorName,
        maintainerIds: [uid],
        createdAt: FieldValue.serverTimestamp(),
        publishAt,
        messageCount: 0,
        lastMessageAt: publishAt,
        visibility,
        passwordVersion: 0,
        isOpen: true,
        isArchived: false,
        expiresAt,
      };
      if (lock != null) {
        placeData.lockType = lock.lockType;
        if (lock.lockHint != null) {
          placeData.lockHint = lock.lockHint;
        }
      }

      tx.set(placeRef, placeData);
      if (lock != null) {
        tx.set(placeRef.collection("secret").doc("auth"), {
          hash: lock.hash,
          passwordVersion: 0,
        });
      }

      // Counter is the source of truth for the cap. New user docs do not need
      // to store activeNoteCount until their first note is created.
      tx.set(
        userRef,
        {activeNoteCount: FieldValue.increment(1)},
        {merge: true},
      );
    });

    return {placeId: placeRef.id};
  },
);

export const setNotePinImage = onCall<SetNotePinImageData>(
  {enforceAppCheck: true},
  async (req) => {
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

    const bucket = getStorage().bucket();
    try {
      const [metadata] = await bucket.file(pinImageStoragePath).getMetadata();
      if (
        metadata.contentType !== "image/webp" ||
        Number(metadata.size ?? 0) > 256 * 1024
      ) {
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

    const db = getFirestore();
    const placeRef = db.collection("places").doc(placeId);
    const previousPath = await db.runTransaction(async (tx) => {
      const placeSnap = await tx.get(placeRef);
      if (!placeSnap.exists) {
        throw new HttpsError("not-found", "Note not found.");
      }
      if (!canMaintainNote(placeSnap, uid)) {
        throw new HttpsError(
          "permission-denied",
          "You cannot change this note.",
        );
      }
      const previous = placeSnap.get("pinImageStoragePath");
      tx.update(placeRef, {pinImageStoragePath});
      return typeof previous === "string" ? previous : null;
    });

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
 * Creator-only terminal archive. The place update and active-note counter
 * decrement share a transaction so retries cannot free the slot twice.
 */
export const archiveNote = onCall<ArchiveNoteData>(
  {enforceAppCheck: true},
  async (req) => {
    const uid = req.auth?.uid;
    if (!uid) {
      throw new HttpsError("unauthenticated", "You must be signed in.");
    }
    const {placeId} = req.data ?? {};
    if (typeof placeId !== "string" || placeId.length === 0) {
      throw new HttpsError("invalid-argument", "placeId is required.");
    }

    const db = getFirestore();
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

      const userRef = db.collection("users").doc(uid);
      const userSnap = await tx.get(userRef);
      const activeCount =
        (userSnap.get("activeNoteCount") as number | undefined) ?? 0;

      tx.update(placeRef, {
        isArchived: true,
        archivedAt: FieldValue.serverTimestamp(),
        isOpen: false,
      });
      tx.set(
        userRef,
        {activeNoteCount: Math.max(0, activeCount - 1)},
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
 *   • decrements the creator's activeNoteCount so the slot frees up against the
 *     creation cap (the counter is the source of truth used by createNote).
 *
 * Archival is terminal — there is no return to active. Notes are processed in
 * batches; because each batch flips isArchived to true, the same query no
 * longer returns them, so re-querying until empty drains the backlog.
 *
 * Requires composite index (isArchived ASC, expiresAt ASC).
 */
export const archiveExpiredNotes = onSchedule(
  {schedule: "every 24 hours", timeZone: "Asia/Tokyo"},
  async () => {
    const db = getFirestore();
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
            const userRef = db.collection("users").doc(creatorId);
            const [userSnap, ...placeSnaps] = await Promise.all([
              tx.get(userRef),
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
              (userSnap.get("activeNoteCount") as number | undefined) ?? 0;
            tx.set(
              userRef,
              {
                activeNoteCount: Math.max(
                  0,
                  activeCount - expiredPlacesToArchive.length,
                ),
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

    logger.info(`archiveExpiredNotes: archived ${totalArchived} notes.`);
  },
);
