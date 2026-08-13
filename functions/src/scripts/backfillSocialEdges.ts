/* eslint-disable require-jsdoc, no-console */

import {randomUUID} from "node:crypto";
import {readFile, rename, writeFile} from "node:fs/promises";

import {deleteApp, initializeApp} from "firebase-admin/app";
import {
  type DocumentSnapshot,
  FieldPath,
  type Firestore,
  type QueryDocumentSnapshot,
} from "firebase-admin/firestore";

import {
  createAdminWorldFirestoreClient,
  DEFAULT_FIRESTORE_DATABASE_ID,
  type WorldFirestoreDatabaseId,
} from "../platform/worldFirestoreProvider";
import {WORLD_CATALOG} from "../platform/worldCatalog";
import {safeAccountBackfillError} from "./backfillAccounts";
import {
  shouldWriteSocialEdge,
  socialEdgeBackfillOperationId,
} from "../socialEdgeBackfill";
import {
  executeSocialEdgeCommand,
  parseSocialEdgeProjection,
  type SocialEdgeProjection,
} from "../socialEdgeReplication";

const CHECKPOINT_VERSION = 1;
const DEFAULT_PAGE_SIZE = 100;
const MAX_PAGE_SIZE = 200;
const PROJECT_PATTERN = /^[a-z][a-z0-9-]{4,28}[a-z0-9]$/;

type BackfillMode = "dry-run" | "apply";
type BackfillPhase = "scan" | "reconcile" | "complete";

interface ParsedArgs {
  readonly sourceProject: string;
  readonly targetProject: string;
  readonly checkpointPath: string;
  readonly reportPath: string;
  readonly pageSize: number;
  readonly maxPages: number | null;
  readonly mode: BackfillMode;
}

interface SocialBackfillCounts {
  readonly listed: number;
  readonly destinationWrites: number;
  readonly operationCommands: number;
  readonly operationReplays: number;
}

interface SocialBackfillCheckpoint {
  readonly version: typeof CHECKPOINT_VERSION;
  readonly sourceProject: string;
  readonly targetProject: string;
  readonly mode: BackfillMode;
  readonly highWaterEdgeId: string | null;
  readonly phase: BackfillPhase;
  readonly cursor: string | null;
  readonly completedPages: number;
  readonly totals: SocialBackfillCounts;
}

interface DestinationPlan {
  readonly writes: number;
}

export function parseSocialEdgeBackfillArgs(
  argv: readonly string[],
): ParsedArgs {
  let sourceProject: string | null = null;
  let targetProject: string | null = null;
  let checkpointPath: string | null = null;
  let reportPath: string | null = null;
  let pageSize = DEFAULT_PAGE_SIZE;
  let maxPages: number | null = null;
  let apply = false;
  let confirmProject: string | null = null;
  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (argument === "--source-project") {
      sourceProject = argv[++index] ?? null;
    } else if (argument === "--target-project") {
      targetProject = argv[++index] ?? null;
    } else if (argument === "--checkpoint") {
      checkpointPath = argv[++index] ?? null;
    } else if (argument === "--report") {
      reportPath = argv[++index] ?? null;
    } else if (argument === "--page-size") {
      pageSize = Number(argv[++index]);
    } else if (argument === "--max-pages") {
      maxPages = Number(argv[++index]);
    } else if (argument === "--apply") {
      apply = true;
    } else if (argument === "--confirm-project") {
      confirmProject = argv[++index] ?? null;
    } else {
      throw new Error(`Unknown argument: ${String(argument)}`);
    }
  }
  if (sourceProject === null || !PROJECT_PATTERN.test(sourceProject) ||
      targetProject === null || !PROJECT_PATTERN.test(targetProject)) {
    throw new Error("Explicit source and target projects are required.");
  }
  if (sourceProject !== targetProject) {
    throw new Error("Cross-project social migration is not supported.");
  }
  if (checkpointPath === null || checkpointPath.length === 0 ||
      reportPath === null || reportPath.length === 0) {
    throw new Error("Explicit checkpoint and report paths are required.");
  }
  requireBoundedInteger(pageSize, "page-size", 1, MAX_PAGE_SIZE);
  if (maxPages !== null) {
    requireBoundedInteger(maxPages, "max-pages", 1, Number.MAX_SAFE_INTEGER);
  }
  if (apply && confirmProject !== targetProject) {
    throw new Error("Apply requires an exact target project confirmation.");
  }
  if (!apply && confirmProject !== null) {
    throw new Error("Project confirmation is accepted only with apply.");
  }
  return Object.freeze({
    sourceProject,
    targetProject,
    checkpointPath,
    reportPath,
    pageSize,
    maxPages,
    mode: apply ? "apply" : "dry-run",
  });
}

function requireBoundedInteger(
  value: number,
  field: string,
  minimum: number,
  maximum: number,
): void {
  if (!Number.isSafeInteger(value) || value < minimum || value > maximum) {
    throw new Error(`--${field} is outside its supported range.`);
  }
}

function emptyCounts(): SocialBackfillCounts {
  return Object.freeze({
    listed: 0,
    destinationWrites: 0,
    operationCommands: 0,
    operationReplays: 0,
  });
}

function addCounts(
  left: SocialBackfillCounts,
  right: SocialBackfillCounts,
): SocialBackfillCounts {
  return Object.freeze({
    listed: left.listed + right.listed,
    destinationWrites: left.destinationWrites + right.destinationWrites,
    operationCommands: left.operationCommands + right.operationCommands,
    operationReplays: left.operationReplays + right.operationReplays,
  });
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function isCounts(value: unknown): value is SocialBackfillCounts {
  if (!isRecord(value)) return false;
  return Object.keys(emptyCounts()).every((field) => {
    const count = value[field];
    return typeof count === "number" && Number.isSafeInteger(count) &&
      count >= 0;
  });
}

function isPhase(value: unknown): value is BackfillPhase {
  return value === "scan" || value === "reconcile" || value === "complete";
}

function isCheckpointEdgeId(value: unknown): value is string | null {
  return value === null || (typeof value === "string" &&
    value.length > 0 && value.length <= 1_500 && !value.includes("/"));
}

async function readCheckpoint(
  args: ParsedArgs,
  initialHighWaterEdgeId: string | null,
): Promise<SocialBackfillCheckpoint> {
  let value: unknown;
  try {
    value = JSON.parse(await readFile(args.checkpointPath, "utf8"));
  } catch (error) {
    if (isRecord(error) && error.code === "ENOENT") {
      return Object.freeze({
        version: CHECKPOINT_VERSION,
        sourceProject: args.sourceProject,
        targetProject: args.targetProject,
        mode: args.mode,
        highWaterEdgeId: initialHighWaterEdgeId,
        phase: "scan",
        cursor: null,
        completedPages: 0,
        totals: emptyCounts(),
      });
    }
    throw error;
  }
  if (!isRecord(value) || value.version !== CHECKPOINT_VERSION ||
      value.sourceProject !== args.sourceProject ||
      value.targetProject !== args.targetProject ||
      value.mode !== args.mode ||
      !isCheckpointEdgeId(value.highWaterEdgeId) ||
      !isPhase(value.phase) ||
      !isCheckpointEdgeId(value.cursor) ||
      (value.cursor !== null && value.highWaterEdgeId === null) ||
      !Number.isSafeInteger(value.completedPages) ||
      !isCounts(value.totals)) {
    throw new Error("Social edge backfill checkpoint is incompatible.");
  }
  return value as unknown as SocialBackfillCheckpoint;
}

async function writeJsonAtomic(path: string, value: unknown): Promise<void> {
  const temporaryPath = `${path}.${randomUUID()}.tmp`;
  await writeFile(temporaryPath, `${JSON.stringify(value, null, 2)}\n`, {
    flag: "wx",
  });
  await rename(temporaryPath, path);
}

function destinationProjection(
  snapshot: DocumentSnapshot,
): SocialEdgeProjection | null {
  return snapshot.exists ?
    parseSocialEdgeProjection(snapshot, snapshot.id) : null;
}

async function destinationPlan(
  firestores: readonly Firestore[],
  edgeId: string,
  source: SocialEdgeProjection,
): Promise<DestinationPlan> {
  const snapshots = await Promise.all(firestores.map((firestore) =>
    firestore.collection("socialEdges").doc(edgeId).get()));
  return Object.freeze({
    writes: snapshots.filter((snapshot) => shouldWriteSocialEdge(
      source,
      destinationProjection(snapshot),
    )).length,
  });
}

async function requireProfileCounters(
  firestores: readonly Firestore[],
  edge: SocialEdgeProjection,
): Promise<void> {
  for (const firestore of firestores) {
    const profiles = await firestore.getAll(
      firestore.collection("publicProfiles").doc(edge.followerUid),
      firestore.collection("publicProfiles").doc(edge.followeeUid),
    );
    for (const profile of profiles) {
      for (const field of ["followerCount", "followingCount"] as const) {
        const value = profile.get(field);
        if (!profile.exists || typeof value !== "number" ||
            !Number.isSafeInteger(value) || value < 0) {
          throw new Error("Social edge destination counter is invalid.");
        }
      }
    }
  }
}

async function processEdge(
  authorityFirestore: Firestore,
  mirrorFirestores: readonly Firestore[],
  snapshot: DocumentSnapshot,
  mode: BackfillMode,
): Promise<SocialBackfillCounts> {
  const source = parseSocialEdgeProjection(snapshot, snapshot.id);
  await requireProfileCounters(mirrorFirestores, source);
  const plan = await destinationPlan(
    mirrorFirestores,
    snapshot.id,
    source,
  );
  if (mode === "dry-run") {
    return Object.freeze({
      ...emptyCounts(),
      listed: 1,
      destinationWrites: plan.writes === 0 ? 0 : mirrorFirestores.length,
    });
  }
  if (plan.writes === 0) {
    return Object.freeze({...emptyCounts(), listed: 1});
  }
  const result = await executeSocialEdgeCommand({
    firestore: authorityFirestore,
    authorityWorld: "asia",
    followerUid: source.followerUid,
    followeeUid: source.followeeUid,
    following: source.following,
    operationId: socialEdgeBackfillOperationId(snapshot.id),
    sourceEventId: "p21SocialEdgeBackfill",
  });
  if (!result.accepted) {
    throw new Error("Social edge backfill operation failed.");
  }
  return Object.freeze({
    ...emptyCounts(),
    listed: 1,
    destinationWrites: result.replayed ?
      plan.writes : mirrorFirestores.length,
    operationCommands: Number(!result.replayed),
    operationReplays: Number(result.replayed),
  });
}

function nextCheckpoint(
  current: SocialBackfillCheckpoint,
  lastId: string | null,
  hasNextPage: boolean,
  pageCounts: SocialBackfillCounts,
): SocialBackfillCheckpoint {
  const totals = addCounts(current.totals, pageCounts);
  if (hasNextPage) {
    return Object.freeze({
      ...current,
      cursor: lastId,
      completedPages: current.completedPages + 1,
      totals,
    });
  }
  if (current.phase === "scan") {
    return Object.freeze({
      ...current,
      phase: "reconcile",
      cursor: null,
      completedPages: current.completedPages + 1,
      totals,
    });
  }
  return Object.freeze({
    ...current,
    phase: "complete",
    cursor: null,
    completedPages: current.completedPages + 1,
    totals,
  });
}

async function writeProgress(
  args: ParsedArgs,
  checkpoint: SocialBackfillCheckpoint,
): Promise<void> {
  await writeJsonAtomic(args.checkpointPath, checkpoint);
  await writeJsonAtomic(args.reportPath, {
    version: CHECKPOINT_VERSION,
    sourceProject: checkpoint.sourceProject,
    targetProject: checkpoint.targetProject,
    mode: checkpoint.mode,
    highWaterCaptured: checkpoint.highWaterEdgeId !== null,
    phase: checkpoint.phase,
    completedPages: checkpoint.completedPages,
    complete: checkpoint.phase === "complete",
    totals: checkpoint.totals,
  });
}

async function main(): Promise<void> {
  const args = parseSocialEdgeBackfillArgs(process.argv.slice(2));
  const app = initializeApp({projectId: args.sourceProject});
  const authorityFirestore = createAdminWorldFirestoreClient(
    app,
    DEFAULT_FIRESTORE_DATABASE_ID,
  );
  const mirrorFirestores = WORLD_CATALOG.worlds
    .filter((world) => world.worldId !== "asia")
    .map((world) => createAdminWorldFirestoreClient(
      app,
      world.databaseId as WorldFirestoreDatabaseId,
    ));
  let pagesThisRun = 0;
  let checkpoint: SocialBackfillCheckpoint | null = null;
  try {
    const highWater = await authorityFirestore.collection("socialEdges")
      .orderBy(FieldPath.documentId(), "desc")
      .limit(1)
      .get();
    checkpoint = await readCheckpoint(
      args,
      highWater.docs[0]?.id ?? null,
    );
    if (checkpoint.phase === "complete") {
      await writeProgress(args, checkpoint);
      console.log("Social edge backfill checkpoint is already complete.");
      return;
    }
    while (checkpoint.phase !== "complete" &&
        (args.maxPages === null || pagesThisRun < args.maxPages)) {
      let documents: QueryDocumentSnapshot[] = [];
      if (checkpoint.highWaterEdgeId !== null) {
        let query = authorityFirestore.collection("socialEdges")
          .orderBy(FieldPath.documentId())
          .endAt(checkpoint.highWaterEdgeId)
          .limit(args.pageSize);
        if (checkpoint.cursor !== null) {
          query = query.startAfter(checkpoint.cursor);
        }
        documents = (await query.get()).docs;
      }
      let pageCounts = emptyCounts();
      for (const edge of documents) {
        pageCounts = addCounts(pageCounts, await processEdge(
          authorityFirestore,
          mirrorFirestores,
          edge,
          args.mode,
        ));
      }
      checkpoint = nextCheckpoint(
        checkpoint,
        documents[documents.length - 1]?.id ?? null,
        documents.length === args.pageSize,
        pageCounts,
      );
      await writeProgress(args, checkpoint);
      pagesThisRun += 1;
      console.log(JSON.stringify({
        mode: args.mode,
        phase: checkpoint.phase,
        completedPages: checkpoint.completedPages,
        page: pageCounts,
      }));
    }
  } finally {
    await deleteApp(app);
  }
  if (checkpoint === null) {
    throw new Error("Social edge backfill checkpoint was not initialized.");
  }
  console.log(JSON.stringify({
    complete: checkpoint.phase === "complete",
    mode: checkpoint.mode,
    phase: checkpoint.phase,
    completedPages: checkpoint.completedPages,
    totals: checkpoint.totals,
  }));
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
