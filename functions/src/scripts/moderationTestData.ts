/* eslint-disable require-jsdoc, no-console, max-len */
import {randomBytes} from "node:crypto";

import {deleteApp, initializeApp} from "firebase-admin/app";
import {
  DocumentData,
  DocumentReference,
  Firestore,
  Timestamp,
  getFirestore,
} from "firebase-admin/firestore";

const RUN_COLLECTION = "moderationTestRuns";
const RUN_KIND = "admin-moderation-v1";
const LIST_LIMIT = 100;

type Command = "seed" | "list" | "cleanup";

interface ParsedArgs {
  command: Command;
  projectId: string;
  allowLive: boolean;
  confirmProject?: string;
  runId?: string;
}

interface TestRunData {
  kind: string;
  status: string;
  projectId: string;
  placeId: string;
  messageIds: string[];
  reviewIds: string[];
  reportIds: string[];
  createdAt: Timestamp;
}

interface Fixture {
  key: "allow" | "sensitive" | "hide" | "resolved";
  instruction: string;
}

const fixtures: Fixture[] = [
  {
    key: "allow",
    instruction: "TRY ALLOW: restore this automatically hidden message.",
  },
  {
    key: "sensitive",
    instruction: "TRY SENSITIVE: resolve this user-reported message.",
  },
  {
    key: "hide",
    instruction: "TRY HIDE: remove this risk-signaled message.",
  },
  {
    key: "resolved",
    instruction: "RESOLVED: verify this item in the Resolved tab.",
  },
];

function usage(): string {
  return [
    "Usage:",
    "  npm run moderation:test-data -- seed --project <project-id>",
    "  npm run moderation:test-data -- list --project <project-id> [--run-id <run-id>]",
    "  npm run moderation:test-data -- cleanup --project <project-id> --run-id <run-id>",
    "",
    "For a non-emulator target, also pass:",
    "  --allow-live --confirm-project <project-id>",
  ].join("\n");
}

function requiredFlagValue(argv: string[], index: number, flag: string): string {
  const value = argv[index + 1];
  if (value == null || value.startsWith("--")) {
    throw new Error(`${flag} requires a value.\n\n${usage()}`);
  }
  return value;
}

function parseArgs(argv: string[]): ParsedArgs {
  const command = argv[0];
  if (command !== "seed" && command !== "list" && command !== "cleanup") {
    throw new Error(`Specify seed, list, or cleanup.\n\n${usage()}`);
  }

  let projectId: string | undefined;
  let confirmProject: string | undefined;
  let runId: string | undefined;
  let allowLive = false;

  for (let index = 1; index < argv.length; index++) {
    const arg = argv[index];
    if (arg === "--project") {
      projectId = requiredFlagValue(argv, index, arg);
      index++;
    } else if (arg === "--confirm-project") {
      confirmProject = requiredFlagValue(argv, index, arg);
      index++;
    } else if (arg === "--run-id") {
      runId = requiredFlagValue(argv, index, arg);
      index++;
    } else if (arg === "--allow-live") {
      allowLive = true;
    } else {
      throw new Error(`Unknown argument: ${arg}\n\n${usage()}`);
    }
  }

  if (projectId == null || projectId.trim().length === 0) {
    throw new Error(`--project is required.\n\n${usage()}`);
  }
  if (command === "cleanup" && runId == null) {
    throw new Error(`cleanup requires --run-id.\n\n${usage()}`);
  }
  if (command === "seed" && runId != null) {
    throw new Error("seed generates its own run ID; omit --run-id.");
  }

  return {
    command,
    projectId: projectId.trim(),
    allowLive,
    confirmProject: confirmProject?.trim(),
    runId: runId?.trim(),
  };
}

function isFirestoreEmulator(): boolean {
  return (process.env.FIRESTORE_EMULATOR_HOST ?? "").trim().length > 0;
}

function assertSafeTarget(args: ParsedArgs): void {
  if (isFirestoreEmulator()) return;
  if (!args.allowLive || args.confirmProject !== args.projectId) {
    throw new Error(
      "Live Firestore access is blocked. Pass --allow-live and " +
      `--confirm-project ${args.projectId} to confirm the target.`,
    );
  }
}

function createRunId(now = new Date()): string {
  const compactTime = now.toISOString()
    .replace(/[-:]/g, "")
    .replace("T", "_")
    .replace(/\.\d{3}Z$/, "");
  return `modtest_${compactTime}_${randomBytes(2).toString("hex")}`;
}

function testLabel(runId: string, instruction: string): string {
  return `[MODERATION TEST:${runId}] ${instruction}`;
}

function messageData({
  runId,
  placeId,
  authorId,
  fixture,
  createdAt,
}: {
  runId: string;
  placeId: string;
  authorId: string;
  fixture: Fixture;
  createdAt: Timestamp;
}): DocumentData {
  const hidden = fixture.key === "allow";
  const resolved = fixture.key === "resolved";
  const content = testLabel(runId, fixture.instruction);
  return {
    testDataRunId: runId,
    testDataKind: RUN_KIND,
    placeId,
    userId: authorId,
    userName: "Moderation Test User",
    userPhotoUrl: null,
    content: hidden ? "" : content,
    imageStoragePaths: [],
    createdAt,
    publishAt: createdAt,
    placeAggregateAppliedAt: createdAt,
    isScheduled: false,
    isDeleted: hidden,
    deletedAt: hidden ? createdAt : null,
    deletedReason: hidden ? "moderation" : null,
    isVisible: true,
    isPubliclyVisible: true,
    isSensitive: hidden || resolved,
    reviewRequired: !resolved,
    moderationAction: hidden ? "hidden" : resolved ? "sensitive" : "review",
    moderationProvider: "test-fixture",
    moderationPolicyVersion: RUN_KIND,
    reportCount: fixture.key === "sensitive" ? 2 : 0,
    likeCount: 0,
  };
}

function reviewData({
  runId,
  placeId,
  messageId,
  authorId,
  fixture,
  createdAt,
}: {
  runId: string;
  placeId: string;
  messageId: string;
  authorId: string;
  fixture: Fixture;
  createdAt: Timestamp;
}): DocumentData {
  const resolved = fixture.key === "resolved";
  const isReport = fixture.key === "sensitive";
  const isRisk = fixture.key === "hide";
  const content = testLabel(runId, fixture.instruction);
  const reviewSources = isReport ? ["userReport"] :
    isRisk ? ["provider", "riskSignal"] : ["provider"];

  return {
    testDataRunId: runId,
    testDataKind: RUN_KIND,
    userId: authorId,
    placeId,
    messageId,
    messagePath: `places/${placeId}/messages/${messageId}`,
    content,
    imageStoragePaths: [],
    status: resolved ? "resolved" : "open",
    reviewSources,
    reportCount: isReport ? 2 : 0,
    reportReasonsSummary: isReport ? ["Spam or advertising", "Harassment"] : [],
    riskSignals: isRisk ? [{
      category: "phoneNumber",
      severity: "high",
      reviewRecommended: true,
    }] : [],
    provider: "test-fixture",
    providerModel: "moderation-test-model",
    policyVersion: RUN_KIND,
    flagged: !isReport,
    action: fixture.key === "allow" ? "hidden" :
      fixture.key === "hide" ? "review" : "sensitive",
    maxScore: fixture.key === "allow" ? 0.96 :
      fixture.key === "hide" ? 0.84 : 0.72,
    categories: isReport ? [] : [{
      category: fixture.key === "allow" ? "harassment" : "violence",
      score: fixture.key === "allow" ? 0.96 : 0.84,
      matched: true,
      severity: "high",
    }],
    providerResultId: `test-${runId}-${fixture.key}`,
    createdAt,
    checkedAt: createdAt,
    humanDecision: resolved ? "sensitive" : null,
    decisionReason: resolved ? "Pre-resolved test fixture" : null,
    reviewedAt: resolved ? createdAt : null,
    reviewedBy: resolved ? "moderation-test-admin" : null,
  };
}

function placeData(runId: string, authorId: string, now: Timestamp): DocumentData {
  return {
    testDataRunId: runId,
    testDataKind: RUN_KIND,
    title: `[TEST] Moderation ${runId}`,
    subtitle: "Private fixture container for administrator moderation testing.",
    latitude: 0,
    longitude: 0,
    geohash: "7zzzzz",
    mapGeohashMid: "7zzzz",
    discoveryGeohash: "7zz",
    colorHex: "#64748B",
    themeId: "standard",
    icon: "place",
    createdByUserId: authorId,
    creatorName: "Moderation Test User",
    maintainerIds: [authorId],
    createdAt: now,
    publishAt: now,
    messageCount: fixtures.length,
    likeCount: 0,
    lastMessageAt: now,
    visibility: "private",
    passwordVersion: 0,
    lockType: null,
    lockHint: null,
    isOpen: false,
    isArchived: true,
    archivedAt: now,
    expiresAt: now,
    footprintEnabled: false,
    visitorCount: 0,
  };
}

async function seed(db: Firestore, projectId: string): Promise<void> {
  const runId = createRunId();
  const placeId = `${runId}_place`;
  const authorId = `${runId}_author`;
  const messageIds = fixtures.map((fixture) => `${runId}_${fixture.key}`);
  const reviewIds = messageIds.map((messageId) => `${placeId}_${messageId}`);
  const reportIds = [
    `${runId}_report_spam`,
    `${runId}_report_harassment`,
  ];
  const now = Timestamp.now();
  // The admin API lists the oldest 20 reviews. Dates near 2000 keep fixtures
  // visible even when a live project already has a review backlog.
  const visibleBaseMillis = Date.UTC(2000, 0, 1);
  const batch = db.batch();
  const runRef = db.collection(RUN_COLLECTION).doc(runId);
  const placeRef = db.collection("places").doc(placeId);

  batch.create(placeRef, placeData(runId, authorId, now));

  fixtures.forEach((fixture, index) => {
    const messageId = messageIds[index];
    const reviewId = reviewIds[index];
    const createdAt = Timestamp.fromMillis(visibleBaseMillis + index * 60_000);
    batch.create(
      placeRef.collection("messages").doc(messageId),
      messageData({runId, placeId, authorId, fixture, createdAt}),
    );
    batch.create(
      db.collection("moderationReviews").doc(reviewId),
      reviewData({
        runId,
        placeId,
        messageId,
        authorId,
        fixture,
        createdAt,
      }),
    );
  });

  reportIds.forEach((reportId, index) => {
    const messageId = messageIds[1];
    batch.create(db.collection("reports").doc(reportId), {
      testDataRunId: runId,
      testDataKind: RUN_KIND,
      placeId,
      messageId,
      messagePath: `places/${placeId}/messages/${messageId}`,
      reporterId: `${runId}_reporter_${index + 1}`,
      reportedUserId: authorId,
      reason: index === 0 ? "Spam or advertising" : "Harassment",
      status: "open",
      createdAt: Timestamp.fromMillis(visibleBaseMillis + index * 60_000),
    });
  });

  batch.create(runRef, {
    kind: RUN_KIND,
    status: "ready",
    projectId,
    placeId,
    messageIds,
    reviewIds,
    reportIds,
    createdAt: now,
  });
  await batch.commit();

  console.log("Moderation test data created.");
  console.log(`project: ${projectId}`);
  console.log(`runId: ${runId}`);
  console.log(`reviews: ${reviewIds.length}`);
  console.log(`placeId: ${placeId}`);
  console.log("");
  console.log("Cleanup:");
  console.log(cleanupCommand(projectId, runId));
}

function cleanupCommand(projectId: string, runId: string): string {
  const liveFlags = isFirestoreEmulator() ? "" :
    ` --allow-live --confirm-project ${projectId}`;
  return "npm run moderation:test-data -- cleanup " +
    `--project ${projectId} --run-id ${runId}${liveFlags}`;
}

function runData(data: DocumentData): TestRunData | null {
  if (
    data.kind !== RUN_KIND ||
    typeof data.projectId !== "string" ||
    typeof data.placeId !== "string" ||
    !(data.createdAt instanceof Timestamp)
  ) {
    return null;
  }
  return {
    kind: data.kind,
    status: typeof data.status === "string" ? data.status : "unknown",
    projectId: data.projectId,
    placeId: data.placeId,
    messageIds: stringArray(data.messageIds),
    reviewIds: stringArray(data.reviewIds),
    reportIds: stringArray(data.reportIds),
    createdAt: data.createdAt,
  };
}

function stringArray(value: unknown): string[] {
  return Array.isArray(value) ? value.filter((item): item is string =>
    typeof item === "string") : [];
}

async function listOne(db: Firestore, projectId: string, runId: string): Promise<void> {
  const snap = await db.collection(RUN_COLLECTION).doc(runId).get();
  if (!snap.exists) {
    console.log(`No moderation test data found for runId: ${runId}`);
    return;
  }
  const run = runData(snap.data() ?? {});
  if (run == null || run.projectId !== projectId) {
    throw new Error(`Invalid moderation test run document: ${runId}`);
  }

  const reviewRefs = run.reviewIds.map((id) =>
    db.collection("moderationReviews").doc(id));
  const reviewSnaps = reviewRefs.length === 0 ? [] : await db.getAll(...reviewRefs);

  console.log(`runId: ${runId}`);
  console.log(`status: ${run.status}`);
  console.log(`createdAt: ${run.createdAt.toDate().toISOString()}`);
  console.log(`placeId: ${run.placeId}`);
  console.log("reviews:");
  reviewSnaps.forEach((review) => {
    const status = review.exists ? review.get("status") ?? "unknown" : "missing";
    console.log(`  ${review.id}: ${status}`);
  });
  console.log("");
  console.log("Cleanup:");
  console.log(cleanupCommand(projectId, runId));
}

async function listAll(db: Firestore, projectId: string): Promise<void> {
  const snap = await db.collection(RUN_COLLECTION)
    .orderBy("createdAt", "desc")
    .limit(LIST_LIMIT)
    .get();
  const runs = snap.docs
    .map((doc) => ({id: doc.id, data: runData(doc.data())}))
    .filter((entry): entry is {id: string; data: TestRunData} =>
      entry.data != null && entry.data.projectId === projectId);

  if (runs.length === 0) {
    console.log(`No moderation test data runs found in ${projectId}.`);
    return;
  }

  console.log(`Moderation test data runs in ${projectId}:`);
  runs.forEach(({id, data}) => {
    console.log(
      `${id}  ${data.status}  ${data.createdAt.toDate().toISOString()}  ` +
      `${data.reviewIds.length} reviews`,
    );
  });
}

async function list(db: Firestore, projectId: string, runId?: string): Promise<void> {
  if (runId != null) {
    await listOne(db, projectId, runId);
    return;
  }
  await listAll(db, projectId);
}

function deleteRefsInBatch(
  db: Firestore,
  refs: DocumentReference<DocumentData>[],
): FirebaseFirestore.WriteBatch {
  const batch = db.batch();
  refs.forEach((ref) => batch.delete(ref));
  return batch;
}

async function cleanup(db: Firestore, projectId: string, runId: string): Promise<void> {
  const runRef = db.collection(RUN_COLLECTION).doc(runId);
  const runSnap = await runRef.get();
  if (!runSnap.exists) {
    console.log(`No moderation test data found for runId: ${runId}`);
    return;
  }
  const run = runData(runSnap.data() ?? {});
  if (run == null || run.projectId !== projectId) {
    throw new Error(`Invalid moderation test run document: ${runId}`);
  }

  const auditSnap = await db.collection("moderationAuditLogs")
    .where("placeId", "==", run.placeId)
    .get();
  const placeRef = db.collection("places").doc(run.placeId);
  const refs: DocumentReference<DocumentData>[] = [
    ...auditSnap.docs.map((doc) => doc.ref),
    ...run.reportIds.map((id) => db.collection("reports").doc(id)),
    ...run.reviewIds.map((id) => db.collection("moderationReviews").doc(id)),
    ...run.messageIds.map((id) => placeRef.collection("messages").doc(id)),
    placeRef,
    runRef,
  ];
  if (refs.length > 500) {
    throw new Error("Refusing cleanup: the run contains more than 500 documents.");
  }

  await deleteRefsInBatch(db, refs).commit();
  console.log("Moderation test data deleted.");
  console.log(`project: ${projectId}`);
  console.log(`runId: ${runId}`);
  console.log(`auditLogs: ${auditSnap.size}`);
}

async function main(): Promise<void> {
  const args = parseArgs(process.argv.slice(2));
  assertSafeTarget(args);
  const app = initializeApp({projectId: args.projectId});
  const db = getFirestore(app);
  try {
    if (args.command === "seed") {
      await seed(db, args.projectId);
    } else if (args.command === "list") {
      await list(db, args.projectId, args.runId);
    } else {
      await cleanup(db, args.projectId, args.runId as string);
    }
  } finally {
    await deleteApp(app);
  }
}

main().catch((error) => {
  console.error(error instanceof Error ? error.message : error);
  process.exitCode = 1;
});
