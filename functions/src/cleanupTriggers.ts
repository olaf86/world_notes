/* eslint-disable valid-jsdoc */

import {Timestamp} from "firebase-admin/firestore";
import * as logger from "firebase-functions/logger";
import {onDocumentCreated} from "firebase-functions/v2/firestore";
import {onSchedule} from "firebase-functions/v2/scheduler";

import {
  CLEANUP_JOB_RECONCILE_BATCH_SIZE,
  CleanupJobHandlerRegistry,
  CleanupJobQueue,
  CleanupRuntime,
  cleanupJobPath,
  deriveCleanupJobAttention,
  parseCleanupJob,
  processCleanupJob,
} from "./cleanupJobs";
import {blockRelationshipCleanupHandler} from "./blockCleanup";
import {
  archivedNoteAdministratorInvitationRevocationHandler,
  noteAdministratorInvitationExpirationHandler,
} from "./noteAdministratorInviteCleanup";
import {hiddenMessageRetentionHandler} from "./messageModerationRetention";
import {hiddenNoteRetentionHandler} from "./noteModerationRetention";
import {storageObjectCleanupHandler} from "./storageObjectCleanup";
import {
  accountDeletionFirestoreHandler,
  accountDeletionStorageHandler,
} from "./accountDeletion";
import {WorldBucketProvider} from "./platform/worldBucketProvider";
import {
  WorldDatabaseConfig,
  WorldFirestoreDatabaseId,
  WorldFirestoreProvider,
} from "./platform/worldFirestoreProvider";
import {
  WORLD_CATALOG,
  WorldCatalogEntry,
} from "./platform/worldCatalog";

const CLEANUP_RECONCILE_SCHEDULE = "every 10 minutes";

const worldDatabases = WORLD_CATALOG.worlds.map((world) => ({
  worldId: world.worldId,
  databaseId: world.databaseId as WorldFirestoreDatabaseId,
})) satisfies readonly WorldDatabaseConfig[];

// Queue transport is deployed before product-specific cleanup producers.
const productionRuntime: CleanupRuntime = {
  catalog: WORLD_CATALOG,
  firestore: new WorldFirestoreProvider(worldDatabases),
  buckets: new WorldBucketProvider(),
  handlers: new CleanupJobHandlerRegistry([
    blockRelationshipCleanupHandler,
    archivedNoteAdministratorInvitationRevocationHandler,
    noteAdministratorInvitationExpirationHandler,
    hiddenMessageRetentionHandler,
    hiddenNoteRetentionHandler,
    storageObjectCleanupHandler,
    accountDeletionFirestoreHandler,
    accountDeletionStorageHandler,
  ]),
};

export interface CleanupReconcileResult {
  readonly inspected: number;
  readonly completed: number;
  readonly pending: number;
  readonly failed: number;
}

/** Repairs one bounded set of due or lease-expired jobs. */
export async function reconcileCleanupJobs(
  world: string,
  queue: CleanupJobQueue,
  runtime: CleanupRuntime = productionRuntime,
  now: Timestamp = Timestamp.now(),
): Promise<CleanupReconcileResult> {
  const firestore = runtime.firestore.forWorld(world);
  const jobs = firestore.collection(`cleanupQueues/${queue}/jobs`);
  const [pending, expiredLeases] = await Promise.all([
    jobs
      .where("status", "==", "pending")
      .where("nextAttemptAt", "<=", now)
      .orderBy("nextAttemptAt")
      .limit(CLEANUP_JOB_RECONCILE_BATCH_SIZE)
      .get(),
    jobs
      .where("status", "==", "running")
      .where("leaseUntil", "<=", now)
      .orderBy("leaseUntil")
      .limit(CLEANUP_JOB_RECONCILE_BATCH_SIZE)
      .get(),
  ]);
  const due = new Map(
    [...pending.docs, ...expiredLeases.docs].map((snapshot) => [
      snapshot.id,
      snapshot,
    ]),
  );

  let completed = 0;
  let stillPending = 0;
  let failed = 0;
  for (const snapshot of due.values()) {
    try {
      const job = parseCleanupJob(snapshot.data(), world);
      const attention = deriveCleanupJobAttention(job, now);
      if (attention !== "none") {
        const details = {
          jobId: snapshot.id,
          queue,
          jobType: job.jobType,
          world,
          attemptCount: job.attemptCount,
          createdAt: job.createdAt.toDate().toISOString(),
          attention,
        };
        if (attention === "critical") {
          logger.error("Cleanup job requires critical attention.", details);
        } else {
          logger.warn("Cleanup job is delayed.", details);
        }
      }

      const result = await processCleanupJob(
        world,
        queue,
        snapshot.id,
        runtime,
      );
      if (result.status === "complete") {
        completed += 1;
      } else {
        stillPending += 1;
      }
    } catch (error) {
      failed += 1;
      logger.error("Cleanup job reconciliation failed.", {
        jobId: snapshot.id,
        queue,
        world,
        error,
      });
    }
  }

  return {
    inspected: due.size,
    completed,
    pending: stillPending,
    failed,
  };
}

/** Resolves trusted deployment metadata for one world. */
function requireWorld(worldId: string): WorldCatalogEntry {
  const world = WORLD_CATALOG.worlds.find(
    (candidate) => candidate.worldId === worldId,
  );
  if (world === undefined) throw new Error(`Unknown world: ${worldId}.`);
  return world;
}

/** Creates one database-bound low-latency cleanup trigger. */
function cleanupTrigger(worldId: string, queue: CleanupJobQueue) {
  const world = requireWorld(worldId);
  return onDocumentCreated(
    {
      database: world.databaseId,
      document: cleanupJobPath(queue, "{jobId}"),
      region: world.functionsRegion,
      retry: true,
    },
    async (event) => {
      const result = await processCleanupJob(
        worldId,
        queue,
        event.params.jobId,
        productionRuntime,
      );
      logger.info("Cleanup job event processed.", {
        world: worldId,
        queue,
        ...result,
      });
    },
  );
}

/** Creates one database-bound durable cleanup repair schedule. */
function cleanupReconcileSchedule(
  worldId: string,
  queue: CleanupJobQueue,
) {
  const world = requireWorld(worldId);
  return onSchedule(
    {
      schedule: CLEANUP_RECONCILE_SCHEDULE,
      timeZone: "Etc/UTC",
      region: world.functionsRegion,
      retryCount: 3,
      maxInstances: 1,
    },
    async () => {
      const result = await reconcileCleanupJobs(worldId, queue);
      logger.info("Cleanup reconciliation finished.", {
        world: worldId,
        queue,
        ...result,
      });
    },
  );
}

export const processAsiaFirestoreCleanupJob =
  cleanupTrigger("asia", "firestore");
export const processNorthAmericaFirestoreCleanupJob =
  cleanupTrigger("northAmerica", "firestore");
export const processEuropeFirestoreCleanupJob =
  cleanupTrigger("europe", "firestore");
export const processAsiaStorageCleanupJob =
  cleanupTrigger("asia", "storage");
export const processNorthAmericaStorageCleanupJob =
  cleanupTrigger("northAmerica", "storage");
export const processEuropeStorageCleanupJob =
  cleanupTrigger("europe", "storage");

export const reconcileAsiaFirestoreCleanupJobs =
  cleanupReconcileSchedule("asia", "firestore");
export const reconcileNorthAmericaFirestoreCleanupJobs =
  cleanupReconcileSchedule("northAmerica", "firestore");
export const reconcileEuropeFirestoreCleanupJobs =
  cleanupReconcileSchedule("europe", "firestore");
export const reconcileAsiaStorageCleanupJobs =
  cleanupReconcileSchedule("asia", "storage");
export const reconcileNorthAmericaStorageCleanupJobs =
  cleanupReconcileSchedule("northAmerica", "storage");
export const reconcileEuropeStorageCleanupJobs =
  cleanupReconcileSchedule("europe", "storage");
