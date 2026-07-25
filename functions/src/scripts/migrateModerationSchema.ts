/* eslint-disable require-jsdoc, no-console */
import {deleteApp, initializeApp} from "firebase-admin/app";
import {
  DocumentData,
  FieldValue,
  Firestore,
  Timestamp,
  getFirestore,
} from "firebase-admin/firestore";

type TargetType = "message" | "note";

interface ParsedArgs {
  projectId: string;
  apply: boolean;
  allowLive: boolean;
  confirmProject?: string;
}

interface Target {
  type: TargetType;
  id: string;
  path: string;
  placeId: string;
}

interface MigrationCounts {
  scanned: number;
  changed: number;
  skipped: number;
}

const LEGACY_REASON_CODES: Record<string, string> = {
  "Spam or advertising": "spam",
  "Harassment or bullying": "harassment",
  "Harassment": "harassment",
  "Adult or explicit content": "sexual",
  "Illegal content": "illegal",
  "Other": "other",
};

const REASON_CODES = new Set([
  "spam",
  "harassment",
  "sexual",
  "illegal",
  "other",
]);

function usage(): string {
  return [
    "Usage:",
    "  npm run migrate:moderation-schema -- --project <project-id>",
    "  npm run migrate:moderation-schema -- --project <project-id> --apply",
    "",
    "The command is a dry run unless --apply is passed.",
    "For a non-emulator target, also pass:",
    "  --allow-live --confirm-project <project-id>",
  ].join("\n");
}

function requiredFlagValue(
  argv: string[],
  index: number,
  flag: string,
): string {
  const value = argv[index + 1];
  if (value == null || value.startsWith("--")) {
    throw new Error(`${flag} requires a value.\n\n${usage()}`);
  }
  return value;
}

function parseArgs(argv: string[]): ParsedArgs {
  let projectId: string | undefined;
  let confirmProject: string | undefined;
  let apply = false;
  let allowLive = false;

  for (let index = 0; index < argv.length; index++) {
    const arg = argv[index];
    if (arg === "--project") {
      projectId = requiredFlagValue(argv, index, arg);
      index++;
    } else if (arg === "--confirm-project") {
      confirmProject = requiredFlagValue(argv, index, arg);
      index++;
    } else if (arg === "--apply") {
      apply = true;
    } else if (arg === "--allow-live") {
      allowLive = true;
    } else {
      throw new Error(`Unknown argument: ${arg}\n\n${usage()}`);
    }
  }

  if (projectId == null || projectId.trim().length === 0) {
    throw new Error(`--project is required.\n\n${usage()}`);
  }
  return {
    projectId: projectId.trim(),
    confirmProject: confirmProject?.trim(),
    apply,
    allowLive,
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

function own(data: DocumentData, field: string): boolean {
  return Object.prototype.hasOwnProperty.call(data, field);
}

function nonEmptyString(value: unknown): string | null {
  return typeof value === "string" && value.trim().length > 0 ?
    value.trim() :
    null;
}

function stableReasonCode(value: unknown): string | null {
  const reason = nonEmptyString(value);
  if (reason == null) return null;
  if (REASON_CODES.has(reason)) return reason;
  return LEGACY_REASON_CODES[reason] ?? null;
}

function targetFrom(data: DocumentData): Target | null {
  const placeId = nonEmptyString(data.placeId);
  if (placeId == null) return null;

  const targetType =
    data.targetType === "message" || data.targetType === "note" ?
      data.targetType as TargetType :
      nonEmptyString(data.messageId) == null ? "note" : "message";
  const inferredId = targetType === "message" ?
    nonEmptyString(data.messageId) :
    placeId;
  const targetId = nonEmptyString(data.targetId) ?? inferredId;
  if (targetId == null) return null;

  return {
    type: targetType,
    id: targetId,
    path: targetType === "message" ?
      `places/${placeId}/messages/${targetId}` :
      `places/${placeId}`,
    placeId,
  };
}

function targetPatch(
  data: DocumentData,
  target: Target,
): Record<string, unknown> {
  const patch: Record<string, unknown> = {};
  if (data.targetType !== target.type) patch.targetType = target.type;
  if (data.targetId !== target.id) patch.targetId = target.id;
  if (data.targetPath !== target.path) patch.targetPath = target.path;
  if (own(data, "messageId")) patch.messageId = FieldValue.delete();
  if (own(data, "messagePath")) patch.messagePath = FieldValue.delete();
  return patch;
}

async function migrateReports(
  db: Firestore,
  apply: boolean,
): Promise<MigrationCounts> {
  const counts = {scanned: 0, changed: 0, skipped: 0};
  const writer = apply ? db.bulkWriter() : null;
  const snapshot = await db.collection("reports").get();

  for (const doc of snapshot.docs) {
    counts.scanned++;
    const data = doc.data();
    const target = targetFrom(data);
    const reasonCode =
      stableReasonCode(data.reasonCode) ?? stableReasonCode(data.reason);
    if (target == null || reasonCode == null) {
      counts.skipped++;
      const targetState = target == null ? "invalid" : "ok";
      const reasonState = reasonCode == null ? "invalid" : "ok";
      console.warn(
        `Skipped invalid report (target=${targetState}, ` +
        `reason=${reasonState}): ${doc.ref.path}`,
      );
      continue;
    }
    const patch = targetPatch(data, target);
    if (data.reasonCode !== reasonCode) patch.reasonCode = reasonCode;
    if (own(data, "reason")) patch.reason = FieldValue.delete();
    if (Object.keys(patch).length === 0) continue;
    counts.changed++;
    writer?.update(doc.ref, patch);
  }

  await writer?.close();
  return counts;
}

async function migrateReviews(
  db: Firestore,
  apply: boolean,
): Promise<MigrationCounts> {
  const counts = {scanned: 0, changed: 0, skipped: 0};
  const writer = apply ? db.bulkWriter() : null;
  const snapshot = await db.collection("moderationReviews").get();

  for (const doc of snapshot.docs) {
    counts.scanned++;
    const data = doc.data();
    const target = targetFrom(data);
    if (target == null) {
      counts.skipped++;
      console.warn(`Skipped invalid moderation review: ${doc.ref.path}`);
      continue;
    }
    const patch = targetPatch(data, target);
    if (Array.isArray(data.reportReasonsSummary)) {
      const reasonCodes = data.reportReasonsSummary
        .map(stableReasonCode)
        .filter((reason): reason is string => reason != null);
      if (
        reasonCodes.length !== data.reportReasonsSummary.length ||
        reasonCodes.some((reason, index) =>
          reason !== data.reportReasonsSummary[index])
      ) {
        patch.reportReasonsSummary = [...new Set(reasonCodes)];
      }
    }
    if (Object.keys(patch).length === 0) continue;
    counts.changed++;
    writer?.update(doc.ref, patch);
  }

  await writer?.close();
  return counts;
}

async function migrateAuditLogs(
  db: Firestore,
  apply: boolean,
): Promise<MigrationCounts> {
  const counts = {scanned: 0, changed: 0, skipped: 0};
  const writer = apply ? db.bulkWriter() : null;
  const snapshot = await db.collection("moderationAuditLogs").get();

  for (const doc of snapshot.docs) {
    counts.scanned++;
    const data = doc.data();
    const target = targetFrom(data);
    if (target == null) {
      counts.skipped++;
      console.warn(`Skipped invalid moderation audit log: ${doc.ref.path}`);
      continue;
    }
    const patch = targetPatch(data, target);
    if (Object.keys(patch).length === 0) continue;
    counts.changed++;
    writer?.update(doc.ref, patch);
  }

  await writer?.close();
  return counts;
}

function timestampMillis(value: unknown): number {
  return value instanceof Timestamp ? value.toMillis() : -1;
}

function genericRateLimitData(data: DocumentData): Record<string, unknown> {
  const placeId = nonEmptyString(data.lastPlaceId);
  const targetId =
    nonEmptyString(data.lastTargetId) ??
    nonEmptyString(data.lastMessageId) ??
    placeId;
  const targetType: TargetType =
    data.lastTargetType === "note" && targetId === placeId ?
      "note" :
      "message";
  return {
    ...data,
    lastTargetType: targetType,
    lastTargetId: targetId,
    lastMessageId: FieldValue.delete(),
  };
}

async function migrateRateLimits(
  db: Firestore,
  apply: boolean,
): Promise<MigrationCounts> {
  const counts = {scanned: 0, changed: 0, skipped: 0};
  const snapshot = await db.collectionGroup("rateLimits").get();
  const byPath = new Map(snapshot.docs.map((doc) => [doc.ref.path, doc]));
  const writer = apply ? db.bulkWriter() : null;

  for (const doc of snapshot.docs) {
    if (doc.id !== "reportMessage" && doc.id !== "reportContent") continue;
    counts.scanned++;
    const data = doc.data();
    if (doc.id === "reportContent" && !own(data, "lastMessageId")) continue;

    const targetRef = doc.ref.parent.doc("reportContent");
    const current = byPath.get(targetRef.path);
    const sourceIsNewer =
      current == null ||
      timestampMillis(data.lastCreatedAt) >=
        timestampMillis(current.data().lastCreatedAt);
    if (doc.id === "reportMessage" && !sourceIsNewer) {
      counts.changed++;
      writer?.delete(doc.ref);
      continue;
    }

    const migrated = genericRateLimitData(data);
    const targetId = nonEmptyString(migrated.lastTargetId);
    if (targetId == null) {
      counts.skipped++;
      console.warn(`Skipped invalid report rate limit: ${doc.ref.path}`);
      continue;
    }
    counts.changed++;
    writer?.set(targetRef, migrated, {merge: true});
    if (doc.id === "reportMessage") writer?.delete(doc.ref);
  }

  await writer?.close();
  return counts;
}

async function runMigration(
  db: Firestore,
  apply: boolean,
): Promise<Record<string, MigrationCounts>> {
  return {
    reports: await migrateReports(db, apply),
    moderationReviews: await migrateReviews(db, apply),
    moderationAuditLogs: await migrateAuditLogs(db, apply),
    reportRateLimits: await migrateRateLimits(db, apply),
  };
}

function printCounts(
  mode: "DRY RUN" | "APPLY",
  projectId: string,
  counts: Record<string, MigrationCounts>,
): void {
  console.log(`Moderation schema migration: ${mode}`);
  console.log(`projectId: ${projectId}`);
  for (const [name, value] of Object.entries(counts)) {
    console.log(
      `${name}: scanned=${value.scanned}, changed=${value.changed}, ` +
      `skipped=${value.skipped}`,
    );
  }
}

async function main(): Promise<void> {
  const args = parseArgs(process.argv.slice(2));
  assertSafeTarget(args);
  const app = initializeApp({projectId: args.projectId});
  try {
    const counts = await runMigration(getFirestore(app), args.apply);
    printCounts(args.apply ? "APPLY" : "DRY RUN", args.projectId, counts);
    if (!args.apply) {
      console.log("No documents were written. Pass --apply to migrate.");
    }
  } finally {
    await deleteApp(app);
  }
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
