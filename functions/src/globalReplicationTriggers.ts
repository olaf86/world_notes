/* eslint-disable valid-jsdoc */

import {Timestamp} from "firebase-admin/firestore";
import * as logger from "firebase-functions/logger";
import {onDocumentCreated} from "firebase-functions/v2/firestore";
import {onSchedule} from "firebase-functions/v2/scheduler";

import {
  deriveGlobalOperationAttention,
  GLOBAL_OPERATION_RECONCILE_AFTER_MILLIS,
  GLOBAL_OPERATION_RECONCILE_BATCH_SIZE,
  GlobalReplicationHandlerRegistry,
  GlobalReplicationRuntime,
  missingDestinationWorlds,
  processGlobalOperation,
} from "./globalReplication";
import {parseGlobalOperation} from "./globalOperations";
import {
  publicProfileReplicationHandler,
  reconcilePublicProfileAuthCache,
  userEntitlementReplicationHandler,
} from "./profileEntitlementReplication";
import {socialEdgeReplicationHandler} from "./socialEdgeReplication";
import {userBlockReplicationHandler} from "./userBlockReplication";
import {
  WorldDatabaseConfig,
  WorldFirestoreDatabaseId,
  WorldFirestoreProvider,
} from "./platform/worldFirestoreProvider";
import {
  WORLD_CATALOG,
  WorldCatalogEntry,
} from "./platform/worldCatalog";

const GLOBAL_OPERATION_PATH = "globalOperations/{operationId}";
const RECONCILE_SCHEDULE = "every 15 minutes";

const worldDatabases = WORLD_CATALOG.worlds.map((world) => ({
  worldId: world.worldId,
  databaseId: world.databaseId as WorldFirestoreDatabaseId,
})) satisfies readonly WorldDatabaseConfig[];

const productionRuntime: GlobalReplicationRuntime = {
  catalog: WORLD_CATALOG,
  firestore: new WorldFirestoreProvider(worldDatabases),
  handlers: new GlobalReplicationHandlerRegistry([
    publicProfileReplicationHandler,
    userEntitlementReplicationHandler,
    socialEdgeReplicationHandler,
    userBlockReplicationHandler,
  ]),
};

export interface GlobalReconcileResult {
  readonly inspected: number;
  readonly completed: number;
  readonly failed: number;
}

/**
 * Repairs one bounded page of old pending operations in an authority world.
 *
 * @param {string} authorityWorld Database that owns the operations.
 * @param {GlobalReplicationRuntime} runtime Injectable routing and handlers.
 * @param {Timestamp} now Stable clock value for the whole reconciliation run.
 * @return {Promise<GlobalReconcileResult>} Bounded processing totals.
 */
export async function reconcileGlobalOperations(
  authorityWorld: string,
  runtime: GlobalReplicationRuntime = productionRuntime,
  now: Timestamp = Timestamp.now(),
): Promise<GlobalReconcileResult> {
  const authorityFirestore = runtime.firestore.forWorld(authorityWorld);
  const cutoff = Timestamp.fromMillis(
    now.toMillis() - GLOBAL_OPERATION_RECONCILE_AFTER_MILLIS,
  );
  const pending = await authorityFirestore
    .collection("globalOperations")
    .where("status", "==", "pending")
    .where("acceptedAt", "<=", cutoff)
    .orderBy("acceptedAt")
    .limit(GLOBAL_OPERATION_RECONCILE_BATCH_SIZE)
    .get();

  let completed = 0;
  let failed = 0;
  for (const snapshot of pending.docs) {
    let operation;
    try {
      operation = parseGlobalOperation(snapshot.data(), snapshot.id);
      const attention = deriveGlobalOperationAttention(operation, now);
      if (attention !== "none") {
        const details = {
          operationId: operation.operationId,
          operationType: operation.operationType,
          authorityWorld,
          missingWorlds: missingDestinationWorlds(operation),
          acceptedAt: operation.acceptedAt.toDate().toISOString(),
          attention,
        };
        if (attention === "critical") {
          logger.error(
            "Global operation requires critical attention.",
            details,
          );
        } else {
          logger.warn("Global operation propagation is delayed.", details);
        }
      }

      const result = await processGlobalOperation(
        authorityWorld,
        operation.operationId,
        runtime,
      );
      await reconcilePublicProfileAuthCache(
        authorityFirestore,
        authorityWorld,
        operation,
      );
      if (result?.status === "complete") completed += 1;
    } catch (error) {
      failed += 1;
      logger.error("Global operation reconciliation failed.", {
        operationId: snapshot.id,
        authorityWorld,
        error,
      });
    }
  }

  return {inspected: pending.size, completed, failed};
}

/** Resolves trigger deployment metadata from the trusted catalog. */
function requireWorld(worldId: string): WorldCatalogEntry {
  const world = WORLD_CATALOG.worlds.find(
    (candidate) => candidate.worldId === worldId,
  );
  if (world === undefined) throw new Error(`Unknown world: ${worldId}`);
  return world;
}

/** Creates one database-bound low-latency replication trigger. */
function replicationTrigger(worldId: string) {
  const world = requireWorld(worldId);
  return onDocumentCreated(
    {
      database: world.databaseId,
      document: GLOBAL_OPERATION_PATH,
      region: world.functionsRegion,
      retry: true,
    },
    async (event) => {
      if (event.data === undefined) {
        throw new Error("Global operation create event is missing data.");
      }
      const operation = parseGlobalOperation(
        event.data.data(),
        event.params.operationId,
      );
      await processGlobalOperation(
        worldId,
        event.params.operationId,
        productionRuntime,
      );
      await reconcilePublicProfileAuthCache(
        productionRuntime.firestore.forWorld(worldId),
        worldId,
        operation,
      );
    },
  );
}

/** Creates one database-bound durable repair schedule. */
function reconcileSchedule(worldId: string) {
  const world = requireWorld(worldId);
  return onSchedule(
    {
      schedule: RECONCILE_SCHEDULE,
      timeZone: "Etc/UTC",
      region: world.functionsRegion,
      retryCount: 3,
      maxInstances: 1,
    },
    async () => {
      const result = await reconcileGlobalOperations(worldId);
      logger.info("Global operation reconciliation finished.", {
        authorityWorld: worldId,
        ...result,
      });
    },
  );
}

export const replicateAsiaGlobalOperation = replicationTrigger("asia");
export const replicateNorthAmericaGlobalOperation =
  replicationTrigger("northAmerica");
export const replicateEuropeGlobalOperation = replicationTrigger("europe");

export const reconcileAsiaGlobalOperations = reconcileSchedule("asia");
export const reconcileNorthAmericaGlobalOperations =
  reconcileSchedule("northAmerica");
export const reconcileEuropeGlobalOperations = reconcileSchedule("europe");
