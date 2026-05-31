import {setGlobalOptions} from "firebase-functions/v2";
import {onCall, HttpsError} from "firebase-functions/v2/https";
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
              "Upgrade to Premium for more.",
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
