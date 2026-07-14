/* eslint-disable require-jsdoc, no-console */
import {initializeApp} from "firebase-admin/app";
import {
  DocumentSnapshot,
  FieldPath,
  getFirestore,
  QueryDocumentSnapshot,
} from "firebase-admin/firestore";

const BATCH_SIZE = 200;
const projectId = process.env.GCLOUD_PROJECT;

if (!projectId) {
  throw new Error("GCLOUD_PROJECT must identify the project to backfill.");
}

const db = getFirestore(initializeApp({projectId}));

function nonEmptyString(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : null;
}

function hasValidPhotoVersion(value: unknown): value is number {
  return typeof value === "number" && Number.isInteger(value) && value > 0;
}

async function backfillPublicProfileVersions(): Promise<number> {
  let cursor: QueryDocumentSnapshot | undefined;
  let updated = 0;
  let hasNextPage = true;

  while (hasNextPage) {
    let query = db
      .collection("publicProfiles")
      .orderBy(FieldPath.documentId())
      .limit(BATCH_SIZE);
    if (cursor != null) query = query.startAfter(cursor);

    const profiles = await query.get();
    if (profiles.empty) {
      hasNextPage = false;
      continue;
    }

    const batch = db.batch();
    let writes = 0;
    for (const profile of profiles.docs) {
      if (hasValidPhotoVersion(profile.get("photoVersion"))) continue;
      batch.update(profile.ref, {photoVersion: 1});
      writes += 1;
    }
    if (writes > 0) await batch.commit();
    updated += writes;
    cursor = profiles.docs[profiles.docs.length - 1];
  }

  return updated;
}

async function backfillActivePlaceSnapshots(): Promise<{
  scanned: number;
  updated: number;
}> {
  let cursor: QueryDocumentSnapshot | undefined;
  let scanned = 0;
  let updated = 0;
  let hasNextPage = true;

  while (hasNextPage) {
    let query = db
      .collection("places")
      .where("isArchived", "==", false)
      .orderBy(FieldPath.documentId())
      .limit(BATCH_SIZE);
    if (cursor != null) query = query.startAfter(cursor);

    const places = await query.get();
    if (places.empty) {
      hasNextPage = false;
      continue;
    }
    scanned += places.size;

    const creatorIds = [
      ...new Set(
        places.docs
          .map((place) => nonEmptyString(place.get("createdByUserId")))
          .filter((creatorId): creatorId is string => creatorId !== null),
      ),
    ];
    const profiles = await Promise.all(
      creatorIds.map((creatorId) =>
        db.collection("publicProfiles").doc(creatorId).get(),
      ),
    );
    const profileById = new Map<string, DocumentSnapshot>(
      profiles.map((profile) => [profile.id, profile]),
    );

    const batch = db.batch();
    let writes = 0;
    for (const place of places.docs) {
      const creatorId = nonEmptyString(place.get("createdByUserId"));
      const profile = creatorId == null ? null : profileById.get(creatorId);
      const creatorName = profile?.exists ?
        nonEmptyString(profile.get("displayName")) :
        null;
      const creatorPhotoUrl = profile?.exists ?
        nonEmptyString(profile.get("photoUrl")) :
        null;
      const creatorPhotoVersion = hasValidPhotoVersion(
        profile?.get("photoVersion"),
      ) ? profile.get("photoVersion") : 1;
      const update: Record<string, string | number | null> = {};
      if (creatorName != null && place.get("creatorName") !== creatorName) {
        update.creatorName = creatorName;
      }
      if (place.get("creatorPhotoUrl") !== creatorPhotoUrl) {
        update.creatorPhotoUrl = creatorPhotoUrl;
      }
      if (place.get("creatorPhotoVersion") !== creatorPhotoVersion) {
        update.creatorPhotoVersion = creatorPhotoVersion;
      }
      if (Object.keys(update).length === 0) continue;
      batch.update(place.ref, update);
      writes += 1;
    }
    if (writes > 0) await batch.commit();
    updated += writes;
    cursor = places.docs[places.docs.length - 1];
  }

  return {scanned, updated};
}

async function main(): Promise<void> {
  const updatedProfiles = await backfillPublicProfileVersions();
  const places = await backfillActivePlaceSnapshots();
  console.log(
    `Backfilled ${updatedProfiles} public profiles and ` +
      `${places.updated} of ${places.scanned} active place snapshots.`,
  );
}

void main().catch((error: unknown) => {
  console.error("Creator profile snapshot backfill failed.", error);
  process.exitCode = 1;
});
