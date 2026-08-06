/* eslint-disable require-jsdoc, valid-jsdoc */

import {Timestamp} from "firebase-admin/firestore";
import * as logger from "firebase-functions/logger";
import {onSchedule} from "firebase-functions/v2/scheduler";
import {onObjectFinalized} from "firebase-functions/v2/storage";

import {
  recordFinalizedImageUpload,
  sweepOrphanImageUploads,
} from "./imageUploads";
import {
  WorldDatabaseConfig,
  WorldFirestoreDatabaseId,
  WorldFirestoreProvider,
} from "./platform/worldFirestoreProvider";
import {WORLD_CATALOG, WorldCatalogEntry} from "./platform/worldCatalog";

const worldDatabases = WORLD_CATALOG.worlds.map((world) => ({
  worldId: world.worldId,
  databaseId: world.databaseId as WorldFirestoreDatabaseId,
})) satisfies readonly WorldDatabaseConfig[];
const firestore = new WorldFirestoreProvider(worldDatabases);

function requireWorld(worldId: string): WorldCatalogEntry {
  const world = WORLD_CATALOG.worlds.find(
    (candidate) => candidate.worldId === worldId,
  );
  if (world === undefined) throw new Error(`Unknown world: ${worldId}.`);
  return world;
}

function imageFinalizeTrigger(worldId: string) {
  const world = requireWorld(worldId);
  return onObjectFinalized(
    {
      bucket: world.bucketName,
      region: world.functionsRegion,
      retry: true,
    },
    async (event) => {
      const object = event.data;
      if (!object.name.startsWith("images/")) return;
      await recordFinalizedImageUpload(firestore.forWorld(worldId), {
        objectPath: object.name,
        generation: String(object.generation),
        uploadedAt: Timestamp.fromDate(
          object.timeCreated === undefined ?
            new Date(event.time) : new Date(object.timeCreated),
        ),
      });
    },
  );
}

function orphanSweepSchedule(worldId: string) {
  const world = requireWorld(worldId);
  return onSchedule(
    {
      schedule: "every 1 hours",
      timeZone: "Etc/UTC",
      region: world.functionsRegion,
      retryCount: 3,
      maxInstances: 1,
    },
    async () => {
      const result = await sweepOrphanImageUploads(
        firestore.forWorld(worldId),
        worldId,
      );
      logger.info("Orphan image upload sweep finished.", {
        world: worldId,
        ...result,
      });
    },
  );
}

export const trackAsiaImageUpload = imageFinalizeTrigger("asia");
export const trackNorthAmericaImageUpload =
  imageFinalizeTrigger("northAmerica");
export const trackEuropeImageUpload = imageFinalizeTrigger("europe");

export const sweepAsiaOrphanImageUploads = orphanSweepSchedule("asia");
export const sweepNorthAmericaOrphanImageUploads =
  orphanSweepSchedule("northAmerica");
export const sweepEuropeOrphanImageUploads = orphanSweepSchedule("europe");
