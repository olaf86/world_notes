/* eslint-disable valid-jsdoc */

import {Timestamp} from "firebase-admin/firestore";
import * as logger from "firebase-functions/logger";
import {onDocumentCreated} from "firebase-functions/v2/firestore";
import {onSchedule} from "firebase-functions/v2/scheduler";

import {
  NOTIFICATION_RECONCILE_BATCH_SIZE,
  NotificationDeliveryHandlerRegistry,
  NotificationOutboxRuntime,
  parseNotificationOutbox,
  processNotificationOutboxEvent,
} from "./notificationOutbox";
import {myNotesMessageNotificationHandler} from "./notifications";
import {userNoticeNotificationHandler} from "./notices";
import {
  WorldDatabaseConfig,
  WorldFirestoreDatabaseId,
  WorldFirestoreProvider,
} from "./platform/worldFirestoreProvider";
import {
  WORLD_CATALOG,
  WorldCatalogEntry,
} from "./platform/worldCatalog";

const NOTIFICATION_PATH = "notificationOutbox/{eventId}";
const NOTIFICATION_RECONCILE_SCHEDULE = "every 1 minutes";

const worldDatabases = WORLD_CATALOG.worlds.map((world) => ({
  worldId: world.worldId,
  databaseId: world.databaseId as WorldFirestoreDatabaseId,
})) satisfies readonly WorldDatabaseConfig[];

const productionRuntime: NotificationOutboxRuntime = {
  catalog: WORLD_CATALOG,
  firestore: new WorldFirestoreProvider(worldDatabases),
  handlers: new NotificationDeliveryHandlerRegistry([
    myNotesMessageNotificationHandler,
    userNoticeNotificationHandler,
  ]),
};

export interface NotificationReconcileResult {
  readonly inspected: number;
  readonly complete: number;
  readonly pending: number;
  readonly terminalWithoutDelivery: number;
  readonly failed: number;
}

/** Repairs one bounded set of due or lease-expired notification events. */
export async function reconcileNotificationOutbox(
  world: string,
  runtime: NotificationOutboxRuntime = productionRuntime,
  now: Timestamp = Timestamp.now(),
): Promise<NotificationReconcileResult> {
  const firestore = runtime.firestore.forWorld(world);
  const events = firestore.collection("notificationOutbox");
  const [pending, expiredLeases] = await Promise.all([
    events
      .where("status", "==", "pending")
      .where("nextAttemptAt", "<=", now)
      .orderBy("nextAttemptAt")
      .limit(NOTIFICATION_RECONCILE_BATCH_SIZE)
      .get(),
    events
      .where("status", "==", "running")
      .where("leaseUntil", "<=", now)
      .orderBy("leaseUntil")
      .limit(NOTIFICATION_RECONCILE_BATCH_SIZE)
      .get(),
  ]);
  const due = new Map(
    [...pending.docs, ...expiredLeases.docs].map((snapshot) => [
      snapshot.id,
      snapshot,
    ]),
  );

  let complete = 0;
  let stillPending = 0;
  let terminalWithoutDelivery = 0;
  let failed = 0;
  for (const snapshot of due.values()) {
    try {
      const event = parseNotificationOutbox(
        snapshot.data(),
        snapshot.id,
        world,
      );
      const result = await processNotificationOutboxEvent(
        world,
        event.eventId,
        runtime,
      );
      if (result.status === "complete") {
        complete += 1;
      } else if (result.status === "pending" || result.status === "running") {
        stillPending += 1;
      } else {
        terminalWithoutDelivery += 1;
      }
    } catch (error) {
      failed += 1;
      logger.error("Notification outbox reconciliation failed.", {
        eventId: snapshot.id,
        world,
        error,
      });
    }
  }

  return {
    inspected: due.size,
    complete,
    pending: stillPending,
    terminalWithoutDelivery,
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

/** Creates one database-bound low-latency notification trigger. */
function notificationTrigger(worldId: string) {
  const world = requireWorld(worldId);
  return onDocumentCreated(
    {
      database: world.databaseId,
      document: NOTIFICATION_PATH,
      region: world.functionsRegion,
      retry: true,
    },
    async (event) => {
      const result = await processNotificationOutboxEvent(
        worldId,
        event.params.eventId,
        productionRuntime,
      );
      logger.info("Notification outbox event processed.", {
        world: worldId,
        ...result,
      });
    },
  );
}

/** Creates one regional one-minute notification repair schedule. */
function notificationReconcileSchedule(worldId: string) {
  const world = requireWorld(worldId);
  return onSchedule(
    {
      schedule: NOTIFICATION_RECONCILE_SCHEDULE,
      timeZone: "Etc/UTC",
      region: world.functionsRegion,
      retryCount: 3,
      maxInstances: 1,
    },
    async () => {
      const result = await reconcileNotificationOutbox(worldId);
      logger.info("Notification outbox reconciliation finished.", {
        world: worldId,
        ...result,
      });
    },
  );
}

export const processAsiaNotificationOutbox = notificationTrigger("asia");
export const processNorthAmericaNotificationOutbox =
  notificationTrigger("northAmerica");
export const processEuropeNotificationOutbox = notificationTrigger("europe");

export const reconcileAsiaNotificationOutbox =
  notificationReconcileSchedule("asia");
export const reconcileNorthAmericaNotificationOutbox =
  notificationReconcileSchedule("northAmerica");
export const reconcileEuropeNotificationOutbox =
  notificationReconcileSchedule("europe");
