import {setGlobalOptions} from "firebase-functions/v2";
import {onCall, HttpsError} from "firebase-functions/v2/https";
import {onSchedule} from "firebase-functions/v2/scheduler";
import * as logger from "firebase-functions/logger";
import {initializeApp} from "firebase-admin/app";
import {getFirestore, FieldValue, Timestamp} from "firebase-admin/firestore";

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

initializeApp();
setGlobalOptions({maxInstances: 10, region: REGION});

// Password set/verify functions. They set region explicitly in their own
// options because, being defined during module import (before this file's
// setGlobalOptions runs), the global region would not otherwise apply.
export {setNotePassword, unlockNote} from "./notePassword";

// Authoritative message writes plus the schedule that makes delayed messages
// public at publishAt. Region set in their own options.
export {sendMessage, cancelScheduledMessage} from "./messages";
export {aggregatePublishedMessages} from "./messageTriggers";

// Invite-link functions (share-link access to private notes). Region set in
// their own options.
export {
  getInviteLink,
  createInviteLink,
  claimInvite,
  revokeInvite,
  revokeNoteAccess,
} from "./invites";

// Push notification preferences and FCM token registration.
export {
  registerFcmToken,
  deleteFcmToken,
  setMyNotesNotificationEnabled,
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
}

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
  {enforceAppCheck: true},
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

    const visibility =
      req.data?.visibility === "private" ? "private" : "public";
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
      const isPremium = userSnap.get("isPremium") === true;
      const limit = isPremium ? PREMIUM_NOTE_LIMIT : FREE_NOTE_LIMIT;
      const activeCount = (userSnap.get("activeNoteCount") as number) ?? 0;

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

      tx.set(placeRef, {
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
        ownerIds: [uid],
        createdAt: FieldValue.serverTimestamp(),
        publishAt,
        messageCount: 0,
        lastMessageAt: publishAt,
        visibility,
        passwordVersion: 0,
        isOpen: true,
        isArchived: false,
        expiresAt,
      });

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

/**
 * Scheduled auto-archive.
 *
 * Once per day, moves every note past its expiry into the archived state:
 *   • isArchived = true (so it drops out of proximity search and can no longer
 *     accept messages — both already enforced client-side / by rules),
 *   • archivedAt timestamp,
 *   • decrements the owner's activeNoteCount so the slot frees up against the
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

      const batch = db.batch();
      const decrements = new Map<string, number>();

      for (const doc of snap.docs) {
        batch.update(doc.ref, {
          isArchived: true,
          archivedAt: FieldValue.serverTimestamp(),
        });
        const ownerId = doc.get("createdByUserId") as string;
        decrements.set(ownerId, (decrements.get(ownerId) ?? 0) + 1);
      }
      for (const [ownerId, count] of decrements) {
        batch.set(
          db.collection("users").doc(ownerId),
          {activeNoteCount: FieldValue.increment(-count)},
          {merge: true},
        );
      }

      await batch.commit();
      totalArchived += snap.size;
      if (snap.size < batchSize) break;
    }

    logger.info(`archiveExpiredNotes: archived ${totalArchived} notes.`);
  },
);
