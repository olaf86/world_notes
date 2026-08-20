/* eslint-disable valid-jsdoc */

import {
  DocumentSnapshot,
  FieldPath,
  Firestore,
  Query,
} from "firebase-admin/firestore";
import * as logger from "firebase-functions/logger";
import {onDocumentWritten} from "firebase-functions/v2/firestore";

import {
  parsePublicProfileProjection,
  PublicProfileProjection,
} from "./profileEntitlementReplication";
import {
  WorldDatabaseConfig,
  WorldFirestoreDatabaseId,
  WorldFirestoreProvider,
} from "./platform/worldFirestoreProvider";
import {
  WORLD_CATALOG,
  WorldCatalogEntry,
} from "./platform/worldCatalog";

const PROFILE_PATH = "publicProfiles/{userId}";
const PROJECTION_PAGE_SIZE = 200;

const worldDatabases = WORLD_CATALOG.worlds.map((world) => ({
  worldId: world.worldId,
  databaseId: world.databaseId as WorldFirestoreDatabaseId,
})) satisfies readonly WorldDatabaseConfig[];
const productionFirestore = new WorldFirestoreProvider(worldDatabases);

export interface ProfileSnapshotSyncResult {
  readonly updatedPlaces: number;
  readonly updatedMembers: number;
}

/**
 * Converges creator and member snapshots to one public-profile revision.
 *
 * Each page is transactional. Older or duplicated profile events cannot roll
 * a snapshot back because the local snapshot revision is checked before every
 * update. Trigger retries restart safely from the first page.
 */
export async function syncProfileSnapshots(
  firestore: Firestore,
  userId: string,
  profile: PublicProfileProjection,
): Promise<ProfileSnapshotSyncResult> {
  const [updatedPlaces, updatedMembers] = await Promise.all([
    syncQueryPages(
      firestore,
      firestore.collection("places")
        .where("createdByUserId", "==", userId)
        .where("isArchived", "==", false)
        .orderBy(FieldPath.documentId()),
      "creatorProfileRevision",
      profile.revision,
      {
        creatorName: profile.displayName,
        creatorPhotoUrl: profile.photoUrl,
        creatorPhotoVersion: profile.photoVersion,
        creatorProfileRevision: profile.revision,
      },
    ),
    syncQueryPages(
      firestore,
      firestore.collectionGroup("members")
        .where("userId", "==", userId)
        .orderBy(FieldPath.documentId()),
      "profileRevision",
      profile.revision,
      {
        displayName: profile.displayName,
        profileRevision: profile.revision,
      },
    ),
  ]);
  return {updatedPlaces, updatedMembers};
}

/** Processes one stable query in bounded, restart-safe transaction pages. */
async function syncQueryPages(
  firestore: Firestore,
  baseQuery: Query,
  revisionField: string,
  revision: number,
  update: Readonly<Record<string, unknown>>,
): Promise<number> {
  let cursor: DocumentSnapshot | undefined;
  let updated = 0;
  let hasMore = true;
  while (hasMore) {
    let query = baseQuery.limit(PROJECTION_PAGE_SIZE);
    if (cursor !== undefined) query = query.startAfter(cursor);
    const page = await query.get();
    if (page.empty) return updated;

    updated += await firestore.runTransaction(async (transaction) => {
      const current = await transaction.getAll(
        ...page.docs.map((snapshot) => snapshot.ref),
      );
      let pageUpdates = 0;
      for (const snapshot of current) {
        if (!snapshot.exists) continue;
        if (snapshotRevision(snapshot, revisionField) >= revision) continue;
        transaction.update(snapshot.ref, update);
        pageUpdates += 1;
      }
      return pageUpdates;
    });

    cursor = page.docs.at(-1);
    hasMore = page.size === PROJECTION_PAGE_SIZE;
  }
  return updated;
}

/** Reads the required positive profile revision from an existing snapshot. */
function snapshotRevision(
  snapshot: DocumentSnapshot,
  field: string,
): number {
  const value = snapshot.get(field);
  if (typeof value !== "number" || !Number.isSafeInteger(value) || value <= 0) {
    throw new Error(`Profile snapshot ${field} is invalid.`);
  }
  return value;
}

/** Resolves one trusted world entry for trigger deployment metadata. */
function requireWorld(worldId: string): WorldCatalogEntry {
  const world = WORLD_CATALOG.worlds.find(
    (candidate) => candidate.worldId === worldId,
  );
  if (world === undefined) throw new Error(`Unknown world: ${worldId}.`);
  return world;
}

/** Creates one world-bound profile projection trigger. */
function profileProjectionTrigger(worldId: string) {
  const world = requireWorld(worldId);
  return onDocumentWritten(
    {
      database: world.databaseId,
      document: PROFILE_PATH,
      region: world.functionsRegion,
      retry: true,
    },
    async (event) => {
      const before = event.data?.before;
      const after = event.data?.after;
      if (!after?.exists) return;
      const profile = parsePublicProfileProjection(after);
      const previousRevision = before?.exists ?
        snapshotRevision(before, "revision") :
        0;
      if (previousRevision >= profile.revision) return;

      const firestore = productionFirestore.forWorld(worldId);
      const result = await syncProfileSnapshots(
        firestore,
        event.params.userId,
        profile,
      );

      logger.info("Synchronized revisioned profile snapshots.", {
        world: worldId,
        userId: event.params.userId,
        revision: profile.revision,
        ...result,
      });
    },
  );
}

export const syncAsiaProfileSnapshots = profileProjectionTrigger("asia");
export const syncNorthAmericaProfileSnapshots =
  profileProjectionTrigger("northAmerica");
export const syncEuropeProfileSnapshots = profileProjectionTrigger("europe");
