/* eslint-disable require-jsdoc, no-console */

import {deleteApp, initializeApp} from "firebase-admin/app";
import {
  DocumentSnapshot,
  FieldPath,
  Firestore,
  Timestamp,
} from "firebase-admin/firestore";

import {normalizeMentionSearchText, mentionSearchBigrams} from "../mentions";
import {
  createAdminWorldFirestoreClient,
  WorldFirestoreDatabaseId,
} from "../platform/worldFirestoreProvider";
import {WORLD_REGISTRY} from "../platform/worldRegistry";

const DEFAULT_PAGE_SIZE = 100;
const MAX_PAGE_SIZE = 200;
const PROJECT_PATTERN = /^[a-z][a-z0-9-]{4,28}[a-z0-9]$/;
const READABLE_ACTIONS = new Set(["allow", "sensitive", "review"]);

interface BackfillArgs {
  readonly project: string;
  readonly world: string;
  readonly pageSize: number;
  readonly maxPages: number | null;
  readonly startAfter: string | null;
  readonly apply: boolean;
}

interface ParticipantSource {
  readonly placeId: string;
  readonly userId: string;
  readonly displayName: string;
  readonly photoUrl: string | null;
  readonly publishAt: Timestamp;
}

export function parseMentionParticipantBackfillArgs(
  argv: readonly string[],
): BackfillArgs {
  let project: string | null = null;
  let world: string | null = null;
  let pageSize = DEFAULT_PAGE_SIZE;
  let maxPages: number | null = null;
  let startAfter: string | null = null;
  let apply = false;
  let confirmation: string | null = null;
  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (argument === "--project") project = argv[++index] ?? null;
    else if (argument === "--world") world = argv[++index] ?? null;
    else if (argument === "--page-size") pageSize = Number(argv[++index]);
    else if (argument === "--max-pages") maxPages = Number(argv[++index]);
    else if (argument === "--start-after") startAfter = argv[++index] ?? null;
    else if (argument === "--apply") apply = true;
    else if (argument === "--confirm-project") {
      confirmation = argv[++index] ?? null;
    } else throw new Error(`Unknown argument: ${String(argument)}`);
  }
  if (project === null || !PROJECT_PATTERN.test(project)) {
    throw new Error("A valid --project is required.");
  }
  if (world === null) throw new Error("An explicit --world is required.");
  WORLD_REGISTRY.requireWorld(world);
  requireInteger(pageSize, "page-size", MAX_PAGE_SIZE);
  if (maxPages !== null) requireInteger(maxPages, "max-pages");
  if (startAfter !== null && !validMessagePath(startAfter)) {
    throw new Error("--start-after must be a full message document path.");
  }
  if (apply && confirmation !== project) {
    throw new Error("Apply requires an exact --confirm-project value.");
  }
  if (!apply && confirmation !== null) {
    throw new Error("--confirm-project is accepted only with --apply.");
  }
  return Object.freeze({
    project,
    world,
    pageSize,
    maxPages,
    startAfter,
    apply,
  });
}

export function mentionParticipantSource(
  message: DocumentSnapshot,
): ParticipantSource | null {
  if (!message.exists || !validMessagePath(message.ref.path) ||
      message.get("isPubliclyVisible") !== true ||
      message.get("isVisible") !== true ||
      !READABLE_ACTIONS.has(message.get("moderationAction"))) {
    return null;
  }
  const segments = message.ref.path.split("/");
  const userId = message.get("userId");
  const displayName = message.get("userName");
  const photoUrl = message.get("userPhotoUrl");
  const publishAt = message.get("publishAt");
  if (typeof userId !== "string" || userId.length === 0 ||
      userId.length > 128 || userId.includes("/") ||
      typeof displayName !== "string" || displayName.length === 0 ||
      displayName.length > 20 ||
      (photoUrl != null && typeof photoUrl !== "string") ||
      !(publishAt instanceof Timestamp)) {
    return null;
  }
  return Object.freeze({
    placeId: segments[1],
    userId,
    displayName,
    photoUrl: photoUrl ?? null,
    publishAt,
  });
}

async function applyParticipant(
  firestore: Firestore,
  source: ParticipantSource,
): Promise<void> {
  const reference = firestore.collection("places").doc(source.placeId)
    .collection("participants").doc(source.userId);
  await firestore.runTransaction(async (transaction) => {
    const existing = await transaction.get(reference);
    const previousFirst = existing.exists ?
      existing.get("firstParticipatedAt") : undefined;
    const previousLast = existing.exists ?
      existing.get("lastParticipatedAt") : undefined;
    const useSourceProfile = !(previousLast instanceof Timestamp) ||
      source.publishAt.toMillis() >= previousLast.toMillis();
    const displayName = useSourceProfile ? source.displayName :
      existing.get("displayName");
    const photoUrl = useSourceProfile ? source.photoUrl :
      existing.get("photoUrl");
    const firstParticipatedAt = previousFirst instanceof Timestamp &&
      previousFirst.toMillis() < source.publishAt.toMillis() ?
      previousFirst : source.publishAt;
    const lastParticipatedAt = previousLast instanceof Timestamp &&
      previousLast.toMillis() > source.publishAt.toMillis() ?
      previousLast : source.publishAt;
    const searchKey = normalizeMentionSearchText(displayName);
    transaction.set(reference, {
      userId: source.userId,
      displayName,
      displayNameSearchKey: searchKey,
      searchBigrams: mentionSearchBigrams(searchKey),
      photoUrl,
      firstParticipatedAt,
      lastParticipatedAt,
      updatedAt: Timestamp.now(),
    });
  });
}

async function runBackfill(
  firestore: Firestore,
  args: BackfillArgs,
): Promise<void> {
  let cursor = args.startAfter;
  let pages = 0;
  let inspected = 0;
  let eligible = 0;
  while (args.maxPages === null || pages < args.maxPages) {
    let query = firestore.collectionGroup("messages")
      .orderBy(FieldPath.documentId()).limit(args.pageSize);
    if (cursor !== null) query = query.startAfter(cursor);
    const snapshot = await query.get();
    if (snapshot.empty) break;
    for (const message of snapshot.docs) {
      inspected += 1;
      const source = mentionParticipantSource(message);
      if (source === null) continue;
      eligible += 1;
      if (args.apply) await applyParticipant(firestore, source);
    }
    cursor = snapshot.docs.at(-1)?.ref.path ?? cursor;
    pages += 1;
    console.log(JSON.stringify({pages, inspected, eligible, cursor}));
    if (snapshot.size < args.pageSize) break;
  }
  console.log(JSON.stringify({
    status: "complete",
    mode: args.apply ? "apply" : "dry-run",
    world: args.world,
    pages,
    inspected,
    eligible,
    nextStartAfter: cursor,
  }));
}

function requireInteger(value: number, field: string, maximum?: number): void {
  if (!Number.isSafeInteger(value) || value < 1 ||
      (maximum !== undefined && value > maximum)) {
    throw new Error(`--${field} is outside its supported range.`);
  }
}

function validMessagePath(path: string): boolean {
  const segments = path.split("/");
  return segments.length === 4 && segments[0] === "places" &&
    segments[1].length > 0 && segments[2] === "messages" &&
    segments[3].length > 0;
}

async function main(): Promise<void> {
  const args = parseMentionParticipantBackfillArgs(process.argv.slice(2));
  const app = initializeApp({projectId: args.project});
  try {
    const world = WORLD_REGISTRY.requireWorld(args.world);
    const firestore = createAdminWorldFirestoreClient(
      app,
      world.databaseId as WorldFirestoreDatabaseId,
    );
    await runBackfill(firestore, args);
  } finally {
    await deleteApp(app);
  }
}

if (require.main === module) {
  main().catch((error) => {
    console.error(JSON.stringify({
      status: "failed",
      message: error instanceof Error ? error.message : "unknown error",
    }));
    process.exitCode = 1;
  });
}
