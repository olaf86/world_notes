/* eslint-disable require-jsdoc, no-console */

import {writeFile} from "node:fs/promises";

import {deleteApp, initializeApp} from "firebase-admin/app";
import {
  type Firestore,
  Timestamp,
} from "firebase-admin/firestore";

import {evaluateActivationDataInventory} from "../activationDataInventory";
import {collectWorldActivationData} from "../activationDataInventoryFirestore";
import {
  type WorldCatalogEntry,
  WORLD_CATALOG,
} from "../platform/worldCatalog";
import {
  createAdminWorldFirestoreClient,
  DEFAULT_FIRESTORE_DATABASE_ID,
  type WorldFirestoreDatabaseId,
} from "../platform/worldFirestoreProvider";
import {safeAccountBackfillError} from "./backfillAccounts";

const PROJECT_PATTERN = /^[a-z][a-z0-9-]{4,28}[a-z0-9]$/;
const WORLD_PATTERN = /^[a-z][A-Za-z0-9]{1,31}$/;
const SMOKE_SCHEMA_VERSION = 1;

interface ParsedArgs {
  readonly projectId: string;
  readonly worldId: string;
  readonly reportPath: string;
}

interface SmokeCheck {
  readonly code: string;
  readonly pass: true;
}

export function parseMirrorOnlySmokeArgs(
  argv: readonly string[],
): ParsedArgs {
  let projectId: string | null = null;
  let worldId: string | null = null;
  let reportPath: string | null = null;
  let confirmProject: string | null = null;
  let confirmWorld: string | null = null;
  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (argument === "--project") {
      projectId = argv[++index] ?? null;
    } else if (argument === "--world") {
      worldId = argv[++index] ?? null;
    } else if (argument === "--report") {
      reportPath = argv[++index] ?? null;
    } else if (argument === "--confirm-project") {
      confirmProject = argv[++index] ?? null;
    } else if (argument === "--confirm-world") {
      confirmWorld = argv[++index] ?? null;
    } else {
      throw new Error(`Unknown argument: ${String(argument)}`);
    }
  }
  if (projectId === null || !PROJECT_PATTERN.test(projectId)) {
    throw new Error("--project is required and invalid.");
  }
  if (worldId === null || !WORLD_PATTERN.test(worldId)) {
    throw new Error("--world is required and invalid.");
  }
  if (reportPath === null || reportPath.length === 0) {
    throw new Error("--report is required.");
  }
  if (confirmProject !== projectId || confirmWorld !== worldId) {
    throw new Error("Smoke requires exact project and world confirmation.");
  }
  requireMirrorOnlyTarget(worldId);
  return Object.freeze({projectId, worldId, reportPath});
}

export function requireMirrorOnlyTarget(worldId: string): WorldCatalogEntry {
  const world = WORLD_CATALOG.worlds.find(
    (candidate) => candidate.worldId === worldId,
  );
  if (world === undefined || world.worldId === "asia") {
    throw new Error("Smoke target must be one catalogued non-Asia world.");
  }
  if (world.catalogState !== "mirrorOnly" ||
      world.contentAccessEnabled || world.homeAssignmentEnabled) {
    throw new Error("Smoke target is not closed in mirror-only state.");
  }
  return world;
}

async function assertProductionCompositeIndex(
  firestore: Firestore,
): Promise<void> {
  await firestore.collection("globalOperations")
    .where("status", "==", "pending")
    .orderBy("acceptedAt")
    .limit(1)
    .get();
}

async function runTransientDatabaseSmoke(
  firestore: Firestore,
  world: WorldCatalogEntry,
): Promise<void> {
  const reference = firestore
    .collection("activationSmokeRuns")
    .doc(world.worldId);
  let operationError: unknown;
  try {
    const createdAt = Timestamp.now();
    await reference.set({
      schemaVersion: SMOKE_SCHEMA_VERSION,
      worldId: world.worldId,
      databaseId: world.databaseId,
      state: "prepared",
      createdAt,
      updatedAt: createdAt,
    });
    await firestore.runTransaction(async (transaction) => {
      const snapshot = await transaction.get(reference);
      if (!snapshot.exists ||
          snapshot.get("schemaVersion") !== SMOKE_SCHEMA_VERSION ||
          snapshot.get("worldId") !== world.worldId ||
          snapshot.get("databaseId") !== world.databaseId ||
          snapshot.get("state") !== "prepared") {
        throw new Error("Activation smoke document is invalid.");
      }
      transaction.update(reference, {
        state: "verified",
        updatedAt: Timestamp.now(),
      });
    });
    const verified = await reference.get();
    if (!verified.exists || verified.get("state") !== "verified") {
      throw new Error("Activation smoke transaction did not persist.");
    }
  } catch (error) {
    operationError = error;
  }
  let cleanupError: unknown;
  try {
    await reference.delete();
    if ((await reference.get()).exists) {
      throw new Error("Activation smoke cleanup did not remove its document.");
    }
  } catch (error) {
    cleanupError = error;
  }
  if (operationError !== undefined && cleanupError !== undefined) {
    throw new Error("Activation smoke and cleanup both failed.");
  }
  if (operationError !== undefined) throw operationError;
  if (cleanupError !== undefined) throw cleanupError;
}

function smokeCheck(code: string): SmokeCheck {
  return Object.freeze({code, pass: true});
}

async function main(): Promise<void> {
  const args = parseMirrorOnlySmokeArgs(process.argv.slice(2));
  const world = requireMirrorOnlyTarget(args.worldId);
  const app = initializeApp({projectId: args.projectId});
  try {
    const asia = createAdminWorldFirestoreClient(
      app,
      DEFAULT_FIRESTORE_DATABASE_ID,
    );
    const target = createAdminWorldFirestoreClient(
      app,
      world.databaseId as WorldFirestoreDatabaseId,
    );
    if (target.databaseId !== world.databaseId) {
      throw new Error("Activation smoke database route is invalid.");
    }
    const [asiaCounts, targetCounts] = await Promise.all([
      collectWorldActivationData("asia", asia),
      collectWorldActivationData(world.worldId, target),
    ]);
    const inventory = evaluateActivationDataInventory([
      asiaCounts,
      targetCounts,
    ]);
    if (!inventory.pass) {
      throw new Error("Mirror-only activation data gate failed.");
    }
    await assertProductionCompositeIndex(target);
    await runTransientDatabaseSmoke(target, world);
    const checks: readonly SmokeCheck[] = Object.freeze([
      smokeCheck("catalog.mirrorOnly.closed"),
      smokeCheck("database.route.matchesCatalog"),
      ...inventory.checks.map((check) => smokeCheck(check.code)),
      smokeCheck("database.productionCompositeIndex.available"),
      smokeCheck("database.adminTransaction.roundTrip"),
      smokeCheck("database.transientDocument.cleaned"),
    ]);
    const report = Object.freeze({
      projectId: args.projectId,
      worldId: world.worldId,
      databaseId: world.databaseId,
      collectedAt: new Date().toISOString(),
      pass: true,
      checks,
    });
    await writeFile(
      args.reportPath,
      `${JSON.stringify(report, null, 2)}\n`,
      {flag: "wx"},
    );
    console.log(JSON.stringify(report));
  } finally {
    await deleteApp(app);
  }
}

if (require.main === module) {
  main().catch((error) => {
    console.error(JSON.stringify({
      status: "failed",
      ...safeAccountBackfillError(error),
    }));
    process.exitCode = 1;
  });
}
