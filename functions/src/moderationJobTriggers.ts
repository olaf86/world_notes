/* eslint-disable require-jsdoc, valid-jsdoc */

import {Timestamp} from "firebase-admin/firestore";
import * as logger from "firebase-functions/logger";
import {onDocumentCreated} from "firebase-functions/v2/firestore";
import {onSchedule} from "firebase-functions/v2/scheduler";

import {OPENAI_API_KEY} from "./moderation";
import {
  deriveModerationJobAttention,
  MODERATION_JOB_RECONCILE_BATCH_SIZE,
  ModerationJobHandlerRegistry,
  ModerationJobRuntime,
  parseModerationJob,
  processModerationJob,
} from "./moderationJobs";
import {
  WorldDatabaseConfig,
  WorldFirestoreDatabaseId,
  WorldFirestoreProvider,
} from "./platform/worldFirestoreProvider";
import {
  WORLD_CATALOG,
  WorldCatalogEntry,
} from "./platform/worldCatalog";

const MODERATION_JOB_PATH = "moderationJobs/{jobId}";
const MODERATION_RECONCILE_SCHEDULE = "every 1 minutes";

const worldDatabases = WORLD_CATALOG.worlds.map((world) => ({
  worldId: world.worldId,
  databaseId: world.databaseId as WorldFirestoreDatabaseId,
})) satisfies readonly WorldDatabaseConfig[];

// The durable transport is deployed before message, note, and pin-image
// producers are switched to optimistic moderation. Handlers are registered as
// those independently reviewable flows are connected.
const productionRuntime: ModerationJobRuntime = {
  catalog: WORLD_CATALOG,
  firestore: new WorldFirestoreProvider(worldDatabases),
  handlers: new ModerationJobHandlerRegistry([]),
};

export interface ModerationJobReconcileResult {
  readonly inspected: number;
  readonly completed: number;
  readonly pending: number;
  readonly failed: number;
}

/** Repairs one bounded set of due or lease-expired moderation jobs. */
export async function reconcileModerationJobs(
  world: string,
  runtime: ModerationJobRuntime = productionRuntime,
  now: Timestamp = Timestamp.now(),
): Promise<ModerationJobReconcileResult> {
  const firestore = runtime.firestore.forWorld(world);
  const jobs = firestore.collection("moderationJobs");
  const [pending, expiredLeases] = await Promise.all([
    jobs
      .where("status", "==", "pending")
      .where("nextAttemptAt", "<=", now)
      .orderBy("nextAttemptAt")
      .limit(MODERATION_JOB_RECONCILE_BATCH_SIZE)
      .get(),
    jobs
      .where("status", "==", "running")
      .where("leaseUntil", "<=", now)
      .orderBy("leaseUntil")
      .limit(MODERATION_JOB_RECONCILE_BATCH_SIZE)
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
      const job = parseModerationJob(snapshot.data(), snapshot.id, world);
      const attention = deriveModerationJobAttention(job, now);
      if (attention !== "none") {
        const details = {
          jobId: snapshot.id,
          jobType: job.jobType,
          targetPath: job.targetPath,
          world,
          attemptCount: job.attemptCount,
          createdAt: job.createdAt.toDate().toISOString(),
          attention,
        };
        if (attention === "critical") {
          logger.error("Moderation job requires critical attention.", details);
        } else {
          logger.warn("Moderation job is delayed.", details);
        }
      }

      const result = await processModerationJob(
        world,
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
      logger.error("Moderation job reconciliation failed.", {
        jobId: snapshot.id,
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

function requireWorld(worldId: string): WorldCatalogEntry {
  const world = WORLD_CATALOG.worlds.find(
    (candidate) => candidate.worldId === worldId,
  );
  if (world === undefined) throw new Error(`Unknown world: ${worldId}.`);
  return world;
}

/** Creates one database-bound low-latency moderation trigger. */
function moderationJobTrigger(worldId: string) {
  const world = requireWorld(worldId);
  return onDocumentCreated(
    {
      database: world.databaseId,
      document: MODERATION_JOB_PATH,
      region: world.functionsRegion,
      retry: true,
      secrets: [OPENAI_API_KEY],
    },
    async (event) => {
      const result = await processModerationJob(
        worldId,
        event.params.jobId,
        productionRuntime,
      );
      logger.info("Moderation job event processed.", {
        world: worldId,
        ...result,
      });
    },
  );
}

/** Creates one regional one-minute moderation repair schedule. */
function moderationJobReconcileSchedule(worldId: string) {
  const world = requireWorld(worldId);
  return onSchedule(
    {
      schedule: MODERATION_RECONCILE_SCHEDULE,
      timeZone: "Etc/UTC",
      region: world.functionsRegion,
      retryCount: 3,
      maxInstances: 1,
      secrets: [OPENAI_API_KEY],
    },
    async () => {
      const result = await reconcileModerationJobs(worldId);
      logger.info("Moderation job reconciliation finished.", {
        world: worldId,
        ...result,
      });
    },
  );
}

export const processAsiaModerationJob = moderationJobTrigger("asia");
export const processNorthAmericaModerationJob =
  moderationJobTrigger("northAmerica");
export const processEuropeModerationJob = moderationJobTrigger("europe");

export const reconcileAsiaModerationJobs =
  moderationJobReconcileSchedule("asia");
export const reconcileNorthAmericaModerationJobs =
  moderationJobReconcileSchedule("northAmerica");
export const reconcileEuropeModerationJobs =
  moderationJobReconcileSchedule("europe");
