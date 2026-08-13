/* eslint-disable require-jsdoc, no-console */

import {writeFile} from "node:fs/promises";

import {deleteApp, initializeApp} from "firebase-admin/app";
import {
  type Firestore,
  type Query,
} from "firebase-admin/firestore";

import {
  evaluateActivationDataInventory,
  type WorldActivationDataCounts,
} from "../activationDataInventory";
import {
  createAdminWorldFirestoreClient,
  type WorldFirestoreDatabaseId,
} from "../platform/worldFirestoreProvider";
import {WORLD_CATALOG} from "../platform/worldCatalog";
import {safeAccountBackfillError} from "./backfillAccounts";

const PROJECT_PATTERN = /^[a-z][a-z0-9-]{4,28}[a-z0-9]$/;

interface ParsedArgs {
  readonly projectId: string;
  readonly reportPath: string | null;
}

export function parseActivationInventoryArgs(
  argv: readonly string[],
): ParsedArgs {
  let projectId: string | null = null;
  let reportPath: string | null = null;
  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (argument === "--project") {
      projectId = argv[++index] ?? null;
    } else if (argument === "--report") {
      reportPath = argv[++index] ?? null;
    } else {
      throw new Error(`Unknown argument: ${String(argument)}`);
    }
  }
  if (projectId === null || !PROJECT_PATTERN.test(projectId)) {
    throw new Error("--project is required and invalid.");
  }
  if (reportPath === "") throw new Error("--report requires a path.");
  return Object.freeze({projectId, reportPath});
}

async function count(query: Query): Promise<number> {
  return (await query.count().get()).data().count;
}

async function collectWorld(
  worldId: string,
  firestore: Firestore,
): Promise<WorldActivationDataCounts> {
  const [
    userHomes,
    privateUsers,
    publicProfiles,
    userEntitlements,
    userUsage,
    accountSafety,
    socialEdges,
    blockedUsers,
    places,
    pendingGlobalOperations,
    failedGlobalOperations,
  ] = await Promise.all([
    count(firestore.collection("userHomes")),
    count(firestore.collection("users")),
    count(firestore.collection("publicProfiles")),
    count(firestore.collection("userEntitlements")),
    count(firestore.collection("userUsage")),
    count(firestore.collection("accountSafety")),
    count(firestore.collection("socialEdges")),
    count(firestore.collectionGroup("blockedUsers")),
    count(firestore.collection("places")),
    count(firestore.collection("globalOperations")
      .where("status", "==", "pending")),
    count(firestore.collection("globalOperations")
      .where("status", "==", "failed")),
  ]);
  return Object.freeze({
    worldId,
    userHomes,
    privateUsers,
    publicProfiles,
    userEntitlements,
    userUsage,
    accountSafety,
    socialEdges,
    blockedUsers,
    places,
    pendingGlobalOperations,
    failedGlobalOperations,
  });
}

async function main(): Promise<void> {
  const args = parseActivationInventoryArgs(process.argv.slice(2));
  const app = initializeApp({projectId: args.projectId});
  try {
    const worlds = await Promise.all(WORLD_CATALOG.worlds.map((world) =>
      collectWorld(
        world.worldId,
        createAdminWorldFirestoreClient(
          app,
          world.databaseId as WorldFirestoreDatabaseId,
        ),
      )));
    const evaluation = evaluateActivationDataInventory(worlds);
    const report = Object.freeze({
      projectId: args.projectId,
      collectedAt: new Date().toISOString(),
      pass: evaluation.pass,
      worlds,
      checks: evaluation.checks,
    });
    if (args.reportPath !== null) {
      await writeFile(
        args.reportPath,
        `${JSON.stringify(report, null, 2)}\n`,
        {flag: "wx"},
      );
    }
    console.log(JSON.stringify(report));
    if (!evaluation.pass) process.exitCode = 2;
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
