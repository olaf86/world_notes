/* eslint-disable require-jsdoc, no-console */

import {randomUUID} from "node:crypto";
import {readFile, rename, writeFile} from "node:fs/promises";

import {deleteApp, initializeApp} from "firebase-admin/app";
import {getAuth, type Auth, type UserRecord} from "firebase-admin/auth";
import {
  type DocumentSnapshot,
  type Firestore,
  type Query,
  type QuerySnapshot,
  Timestamp,
} from "firebase-admin/firestore";

import {
  ACCOUNT_HOME_EPOCH,
  accountAuthorityData,
  publicProfileMirrorData,
  shouldWriteCanonicalFields,
  shouldWriteHomeMarker,
  shouldWriteProjection,
  shouldWritePublicProfile,
  type AccountAuthorityData,
} from "../accountBackfill";
import {
  createAdminWorldFirestoreClient,
  DEFAULT_FIRESTORE_DATABASE_ID,
  type WorldFirestoreDatabaseId,
} from "../platform/worldFirestoreProvider";
import {WORLD_CATALOG} from "../platform/worldCatalog";

const CHECKPOINT_VERSION = 1;
const DEFAULT_PAGE_SIZE = 100;
const MAX_PAGE_SIZE = 200;
const MAX_UNARCHIVED_NOTES_PER_ACCOUNT = 1_000;
const PROJECT_PATTERN = /^[a-z][a-z0-9-]{4,28}[a-z0-9]$/;

type BackfillMode = "dry-run" | "apply";
type BackfillPhase = "scan" | "reconcile" | "complete";

interface ParsedArgs {
  readonly sourceProject: string;
  readonly targetProject: string;
  readonly pageSize: number;
  readonly maxPages: number | null;
  readonly checkpointPath: string;
  readonly reportPath: string;
  readonly mode: BackfillMode;
}

interface BackfillCheckpoint {
  readonly version: typeof CHECKPOINT_VERSION;
  readonly sourceProject: string;
  readonly targetProject: string;
  readonly mode: BackfillMode;
  readonly highWaterAt: string;
  readonly phase: BackfillPhase;
  readonly pageToken: string | null;
  readonly completedPages: number;
  readonly totals: BackfillCounts;
}

interface BackfillCounts {
  readonly listed: number;
  readonly eligible: number;
  readonly skippedAfterHighWater: number;
  readonly authorityWrites: number;
  readonly homeMirrorWrites: number;
  readonly profileMirrorWrites: number;
  readonly entitlementMirrorWrites: number;
  readonly safetyMirrorWrites: number;
  readonly authClaimWrites: number;
}

interface MirrorPlan {
  readonly home: boolean;
  readonly profile: boolean;
  readonly entitlement: boolean;
  readonly safety: boolean;
}

interface AccountSource {
  readonly authority: AccountAuthorityData;
  readonly authorityWrites: readonly boolean[];
}

function usage(): string {
  return [
    "Usage:",
    "  npm run backfill:accounts -- --source-project <id> \\",
    "    --target-project <id> --checkpoint <path> --report <path>",
    "  npm run backfill:accounts -- --source-project <id> \\",
    "    --target-project <id> --checkpoint <path> --report <path> \\",
    "    --apply --confirm-project <id>",
    "",
    "Optional: --page-size 1..200 --max-pages <positive integer>",
    "Default mode is read-only dry-run.",
    "Source and target must currently match.",
  ].join("\n");
}

export function parseAccountBackfillArgs(
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
      throw new Error(`Unknown argument: ${String(argument)}\n\n${usage()}`);
    }
  }
  for (const [field, project] of [
    ["source", sourceProject],
    ["target", targetProject],
  ] as const) {
    if (project === null || !PROJECT_PATTERN.test(project)) {
      throw new Error(`--${field}-project is required and invalid.`);
    }
  }
  if (sourceProject !== targetProject) {
    throw new Error(
      "Cross-project account migration is not supported by this command.",
    );
  }
  if (checkpointPath === null || checkpointPath.length === 0 ||
      reportPath === null || reportPath.length === 0) {
    throw new Error(`--checkpoint and --report are required.\n\n${usage()}`);
  }
  requireBoundedInteger(pageSize, "page-size", 1, MAX_PAGE_SIZE);
  if (maxPages !== null) {
    requireBoundedInteger(maxPages, "max-pages", 1, Number.MAX_SAFE_INTEGER);
  }
  if (apply && confirmProject !== targetProject) {
    throw new Error(
      "Apply requires --confirm-project to exactly match the target project.",
    );
  }
  if (!apply && confirmProject !== null) {
    throw new Error("--confirm-project is accepted only with --apply.");
  }
  return Object.freeze({
    sourceProject: sourceProject as string,
    targetProject: targetProject as string,
    pageSize,
    maxPages,
    checkpointPath,
    reportPath,
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

function emptyCounts(): BackfillCounts {
  return Object.freeze({
    listed: 0,
    eligible: 0,
    skippedAfterHighWater: 0,
    authorityWrites: 0,
    homeMirrorWrites: 0,
    profileMirrorWrites: 0,
    entitlementMirrorWrites: 0,
    safetyMirrorWrites: 0,
    authClaimWrites: 0,
  });
}

function addCounts(
  left: BackfillCounts,
  right: BackfillCounts,
): BackfillCounts {
  return Object.freeze(Object.fromEntries(
    Object.keys(left).map((key) => [
      key,
      left[key as keyof BackfillCounts] +
        right[key as keyof BackfillCounts],
    ]),
  ) as unknown as BackfillCounts);
}

async function readCheckpoint(
  args: ParsedArgs,
): Promise<BackfillCheckpoint> {
  let parsed: unknown;
  try {
    parsed = JSON.parse(await readFile(args.checkpointPath, "utf8"));
  } catch (error) {
    if (isNodeError(error, "ENOENT")) {
      return Object.freeze({
        version: CHECKPOINT_VERSION,
        sourceProject: args.sourceProject,
        targetProject: args.targetProject,
        mode: args.mode,
        highWaterAt: new Date().toISOString(),
        phase: "scan",
        pageToken: null,
        completedPages: 0,
        totals: emptyCounts(),
      });
    }
    throw error;
  }
  if (!isRecord(parsed) || parsed.version !== CHECKPOINT_VERSION ||
      parsed.sourceProject !== args.sourceProject ||
      parsed.targetProject !== args.targetProject ||
      parsed.mode !== args.mode || typeof parsed.highWaterAt !== "string" ||
      !isPhase(parsed.phase) ||
      (parsed.pageToken !== null && typeof parsed.pageToken !== "string") ||
      !Number.isSafeInteger(parsed.completedPages) ||
      !isCounts(parsed.totals)) {
    throw new Error("Account backfill checkpoint is incompatible.");
  }
  requireIsoTimestamp(parsed.highWaterAt, "checkpoint high-water time");
  return parsed as unknown as BackfillCheckpoint;
}

async function writeJsonAtomic(path: string, value: unknown): Promise<void> {
  const temporaryPath = `${path}.${randomUUID()}.tmp`;
  await writeFile(temporaryPath, `${JSON.stringify(value, null, 2)}\n`, {
    flag: "wx",
  });
  await rename(temporaryPath, path);
}

function isNodeError(error: unknown, code: string): boolean {
  return isRecord(error) && error.code === code;
}

function isPhase(value: unknown): value is BackfillPhase {
  return value === "scan" || value === "reconcile" || value === "complete";
}

function isCounts(value: unknown): value is BackfillCounts {
  if (!isRecord(value)) return false;
  return Object.keys(emptyCounts()).every((key) => {
    const count = value[key];
    return typeof count === "number" && Number.isSafeInteger(count) &&
      count >= 0;
  });
}

function requireIsoTimestamp(value: string, field: string): number {
  const millis = Date.parse(value);
  if (!Number.isFinite(millis)) throw new Error(`${field} is invalid.`);
  return millis;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function snapshotData(
  snapshot: DocumentSnapshot,
): Readonly<Record<string, unknown>> | null {
  const data = snapshot.data();
  return data === undefined ? null : data;
}

async function loadSourceAccount(
  firestore: Firestore,
  authUser: UserRecord,
  now: Timestamp,
): Promise<AccountSource> {
  const uid = authUser.uid;
  const refs = [
    firestore.collection("userHomes").doc(uid),
    firestore.collection("users").doc(uid),
    firestore.collection("publicProfiles").doc(uid),
    firestore.collection("userEntitlements").doc(uid),
    firestore.collection("userUsage").doc(uid),
    firestore.collection("accountSafety").doc(uid),
  ] as const;
  const activePlacesQuery = unarchivedPlacesQuery(firestore, uid);
  const [documents, activePlaces] = await Promise.all([
    firestore.getAll(...refs),
    activePlacesQuery.get(),
  ]);
  return accountSourceFromSnapshots(authUser, now, documents, activePlaces);
}

function unarchivedPlacesQuery(
  firestore: Firestore,
  uid: string,
): Query {
  return firestore.collection("places")
    .where("createdByUserId", "==", uid)
    .where("isArchived", "==", false)
    .limit(MAX_UNARCHIVED_NOTES_PER_ACCOUNT);
}

function accountSourceFromSnapshots(
  authUser: UserRecord,
  now: Timestamp,
  documents: readonly DocumentSnapshot[],
  activePlaces: QuerySnapshot,
): AccountSource {
  if (activePlaces.size === MAX_UNARCHIVED_NOTES_PER_ACCOUNT) {
    throw new Error("Account has too many unarchived notes to backfill.");
  }
  const activeNoteCount = activePlaces.docs.filter((place) =>
    !(place.get("activeNoteSlotReleasedAt") instanceof Timestamp),
  ).length;
  const createdAt = Timestamp.fromDate(new Date(
    authUser.metadata.creationTime,
  ));
  const authority = accountAuthorityData({
    identity: {
      uid: authUser.uid,
      displayName: authUser.displayName ?? null,
      email: authUser.email ?? null,
      photoUrl: authUser.photoURL ?? null,
      createdAt,
    },
    now,
    activeNoteCount,
    home: snapshotData(documents[0]),
    user: snapshotData(documents[1]),
    profile: snapshotData(documents[2]),
    entitlement: snapshotData(documents[3]),
    usage: snapshotData(documents[4]),
    safety: snapshotData(documents[5]),
  });
  const current = documents.map(snapshotData);
  return Object.freeze({
    authority,
    authorityWrites: Object.freeze([
      shouldWriteCanonicalFields(authority.home, current[0]),
      shouldWriteCanonicalFields(authority.user, current[1]),
      shouldWriteCanonicalFields(authority.profile, current[2]),
      shouldWriteCanonicalFields(authority.entitlement, current[3]),
      shouldWriteCanonicalFields(authority.usage, current[4]),
      shouldWriteCanonicalFields(authority.safety, current[5]),
    ]),
  });
}

async function writeAuthorityBundle(
  firestore: Firestore,
  authUser: UserRecord,
): Promise<AccountSource> {
  return firestore.runTransaction(async (transaction) => {
    const uid = authUser.uid;
    const refs = {
      home: firestore.collection("userHomes").doc(uid),
      user: firestore.collection("users").doc(uid),
      profile: firestore.collection("publicProfiles").doc(uid),
      entitlement: firestore.collection("userEntitlements").doc(uid),
      usage: firestore.collection("userUsage").doc(uid),
      safety: firestore.collection("accountSafety").doc(uid),
    };
    const [home, user, profile, entitlement, usage, safety, activePlaces] =
      await Promise.all([
        transaction.get(refs.home),
        transaction.get(refs.user),
        transaction.get(refs.profile),
        transaction.get(refs.entitlement),
        transaction.get(refs.usage),
        transaction.get(refs.safety),
        transaction.get(unarchivedPlacesQuery(firestore, uid)),
      ]);
    const source = accountSourceFromSnapshots(
      authUser,
      Timestamp.now(),
      [home, user, profile, entitlement, usage, safety],
      activePlaces,
    );
    const data = [
      source.authority.home,
      source.authority.user,
      source.authority.profile,
      source.authority.entitlement,
      source.authority.usage,
      source.authority.safety,
    ];
    const references = [
      refs.home,
      refs.user,
      refs.profile,
      refs.entitlement,
      refs.usage,
      refs.safety,
    ];
    source.authorityWrites.forEach((write, index) => {
      if (write) {
        transaction.set(references[index], {...data[index]}, {merge: true});
      }
    });
    return source;
  });
}

async function mirrorPlan(
  firestore: Firestore,
  uid: string,
  authority: AccountAuthorityData,
): Promise<MirrorPlan> {
  const snapshots = await firestore.getAll(
    firestore.collection("userHomes").doc(uid),
    firestore.collection("publicProfiles").doc(uid),
    firestore.collection("userEntitlements").doc(uid),
    firestore.collection("accountSafety").doc(uid),
  );
  return Object.freeze({
    home: shouldWriteHomeMarker(authority.home, snapshotData(snapshots[0])),
    profile: shouldWritePublicProfile(
      authority.profile,
      snapshotData(snapshots[1]),
    ),
    entitlement: shouldWriteProjection(
      authority.entitlement,
      snapshotData(snapshots[2]),
    ),
    safety: shouldWriteProjection(
      authority.safety,
      snapshotData(snapshots[3]),
    ),
  });
}

async function applyMirrorPlan(
  firestore: Firestore,
  uid: string,
  authority: AccountAuthorityData,
): Promise<MirrorPlan> {
  return firestore.runTransaction(async (transaction) => {
    const refs = [
      firestore.collection("userHomes").doc(uid),
      firestore.collection("publicProfiles").doc(uid),
      firestore.collection("userEntitlements").doc(uid),
      firestore.collection("accountSafety").doc(uid),
    ] as const;
    const snapshots = await Promise.all(refs.map((ref) =>
      transaction.get(ref)));
    const plan: MirrorPlan = Object.freeze({
      home: shouldWriteHomeMarker(
        authority.home,
        snapshotData(snapshots[0]),
      ),
      profile: shouldWritePublicProfile(
        authority.profile,
        snapshotData(snapshots[1]),
      ),
      entitlement: shouldWriteProjection(
        authority.entitlement,
        snapshotData(snapshots[2]),
      ),
      safety: shouldWriteProjection(
        authority.safety,
        snapshotData(snapshots[3]),
      ),
    });
    if (plan.home) {
      transaction.set(refs[0], {...authority.home}, {merge: true});
    }
    if (plan.profile) {
      transaction.set(
        refs[1],
        {...publicProfileMirrorData(authority.profile)},
        {merge: true},
      );
    }
    if (plan.entitlement) {
      transaction.set(
        refs[2],
        {...authority.entitlement},
        {merge: true},
      );
    }
    if (plan.safety) {
      transaction.set(refs[3], {...authority.safety}, {merge: true});
    }
    return plan;
  });
}

function countsForPlan(plan: MirrorPlan): BackfillCounts {
  return Object.freeze({
    ...emptyCounts(),
    homeMirrorWrites: Number(plan.home),
    profileMirrorWrites: Number(plan.profile),
    entitlementMirrorWrites: Number(plan.entitlement),
    safetyMirrorWrites: Number(plan.safety),
  });
}

async function processAccount(
  sourceFirestore: Firestore,
  mirrorFirestores: readonly Firestore[],
  auth: Auth,
  authUser: UserRecord,
  mode: BackfillMode,
): Promise<BackfillCounts> {
  const source = mode === "apply" ?
    await writeAuthorityBundle(sourceFirestore, authUser) :
    await loadSourceAccount(
      sourceFirestore,
      authUser,
      Timestamp.now(),
    );
  let counts: BackfillCounts = Object.freeze({
    ...emptyCounts(),
    eligible: 1,
    authorityWrites: source.authorityWrites.filter(Boolean).length,
  });
  for (const firestore of mirrorFirestores) {
    const plan = mode === "apply" ?
      await applyMirrorPlan(firestore, authUser.uid, source.authority) :
      await mirrorPlan(firestore, authUser.uid, source.authority);
    counts = addCounts(counts, countsForPlan(plan));
  }
  const claimsReady = authUser.customClaims?.homeWorld === "asia" &&
    authUser.customClaims?.homeEpoch === ACCOUNT_HOME_EPOCH;
  if (!claimsReady) {
    counts = addCounts(counts, Object.freeze({
      ...emptyCounts(),
      authClaimWrites: 1,
    }));
    if (mode === "apply") {
      await auth.setCustomUserClaims(authUser.uid, {
        ...authUser.customClaims,
        homeWorld: "asia",
        homeEpoch: ACCOUNT_HOME_EPOCH,
      });
    }
  }
  return counts;
}

function nextCheckpoint(
  current: BackfillCheckpoint,
  nextPageToken: string | undefined,
  pageCounts: BackfillCounts,
): BackfillCheckpoint {
  const totals = addCounts(current.totals, pageCounts);
  if (nextPageToken !== undefined) {
    return Object.freeze({
      ...current,
      pageToken: nextPageToken,
      completedPages: current.completedPages + 1,
      totals,
    });
  }
  if (current.phase === "scan") {
    return Object.freeze({
      ...current,
      phase: "reconcile",
      pageToken: null,
      completedPages: current.completedPages + 1,
      totals,
    });
  }
  return Object.freeze({
    ...current,
    phase: "complete",
    pageToken: null,
    completedPages: current.completedPages + 1,
    totals,
  });
}

async function writeProgress(
  args: ParsedArgs,
  checkpoint: BackfillCheckpoint,
): Promise<void> {
  await writeJsonAtomic(args.checkpointPath, checkpoint);
  await writeJsonAtomic(args.reportPath, {
    version: CHECKPOINT_VERSION,
    sourceProject: checkpoint.sourceProject,
    targetProject: checkpoint.targetProject,
    mode: checkpoint.mode,
    highWaterAt: checkpoint.highWaterAt,
    phase: checkpoint.phase,
    completedPages: checkpoint.completedPages,
    complete: checkpoint.phase === "complete",
    totals: checkpoint.totals,
  });
}

async function main(): Promise<void> {
  const args = parseAccountBackfillArgs(process.argv.slice(2));
  let checkpoint = await readCheckpoint(args);
  if (checkpoint.phase === "complete") {
    await writeProgress(args, checkpoint);
    console.log("Account backfill checkpoint is already complete.");
    return;
  }
  const app = initializeApp({projectId: args.sourceProject});
  const sourceFirestore = createAdminWorldFirestoreClient(
    app,
    DEFAULT_FIRESTORE_DATABASE_ID,
  );
  const mirrorFirestores = WORLD_CATALOG.worlds
    .filter((world) => world.worldId !== "asia")
    .map((world) => createAdminWorldFirestoreClient(
      app,
      world.databaseId as WorldFirestoreDatabaseId,
    ));
  const auth = getAuth(app);
  const highWaterMillis = requireIsoTimestamp(
    checkpoint.highWaterAt,
    "checkpoint high-water time",
  );
  let pagesThisRun = 0;
  try {
    while (checkpoint.phase !== "complete" &&
        (args.maxPages === null || pagesThisRun < args.maxPages)) {
      const page = await auth.listUsers(
        args.pageSize,
        checkpoint.pageToken ?? undefined,
      );
      let pageCounts: BackfillCounts = Object.freeze({
        ...emptyCounts(),
        listed: page.users.length,
      });
      for (const authUser of page.users) {
        const createdAt = Date.parse(authUser.metadata.creationTime);
        if (!Number.isFinite(createdAt) || createdAt > highWaterMillis) {
          pageCounts = addCounts(pageCounts, Object.freeze({
            ...emptyCounts(),
            skippedAfterHighWater: 1,
          }));
          continue;
        }
        pageCounts = addCounts(pageCounts, await processAccount(
          sourceFirestore,
          mirrorFirestores,
          auth,
          authUser,
          args.mode,
        ));
      }
      checkpoint = nextCheckpoint(
        checkpoint,
        page.pageToken,
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
      errorType: error instanceof Error ? error.name : "UnknownError",
    }));
    process.exitCode = 1;
  });
}
