import {setGlobalOptions} from "firebase-functions/v2";
import {onCall, HttpsError} from "firebase-functions/v2/https";
import {onSchedule} from "firebase-functions/v2/scheduler";
import * as logger from "firebase-functions/logger";
import {initializeApp} from "firebase-admin/app";
import {getFirestore, FieldValue, Timestamp} from "firebase-admin/firestore";

import {encodeGeohash} from "./geohash";
import {
  FREE_NOTE_LIMIT,
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

// Firestore trigger that maintains place.messageCount / lastMessageAt and
// performs the message-limit auto-close. Sets region in its own options.
export {onMessageCreated} from "./messageTriggers";

// Invite-link functions (share-link access to private notes). Region set in
// their own options.
export {
  createInviteLink,
  claimInvite,
  revokeInvite,
  revokeNoteAccess,
} from "./invites";

// User profile updates. Nickname changes keep future posts using the new name
// and refresh note access-list member labels.
export {updateDisplayName} from "./userProfile";

// Short-lived write sessions required by Firestore Rules before direct
// message creation. Region set in its own options.
export {createWriteSession} from "./writeSessions";

interface CreateNoteData {
  latitude?: unknown;
  longitude?: unknown;
  title?: unknown;
  subtitle?: unknown;
  colorHex?: unknown;
  icon?: unknown;
  expiryDays?: unknown;
  visibility?: unknown;
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
    const {latitude, longitude, title, subtitle, colorHex, icon, expiryDays} =
      req.data ?? {};

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
    const geohash = encodeGeohash(latitude, longitude, 6);
    const expiresAt = Timestamp.fromMillis(
      Date.now() + expiryDays * 24 * 60 * 60 * 1000,
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
        title: (title as string).trim(),
        subtitle: trimmedSubtitle,
        colorHex: typeof colorHex === "string" ? colorHex : "#4CAF50",
        icon: typeof icon === "string" ? icon : "place",
        createdByUserId: uid,
        createdAt: FieldValue.serverTimestamp(),
        messageCount: 0,
        lastMessageAt: FieldValue.serverTimestamp(),
        visibility,
        passwordVersion: 0,
        isOpen: true,
        isArchived: false,
        expiresAt,
      });

      // Counter is the source of truth for the cap. set(merge) handles users
      // whose doc predates this field (treated as 0 above).
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
