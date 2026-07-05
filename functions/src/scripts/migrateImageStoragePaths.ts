/* eslint-disable require-jsdoc */
import {initializeApp} from "firebase-admin/app";
import {
  FieldValue,
  getFirestore,
  type DocumentData,
  type DocumentReference,
  type UpdateData,
} from "firebase-admin/firestore";

interface PendingUpdate {
  ref: DocumentReference<DocumentData>;
  data: UpdateData<DocumentData>;
}

const BATCH_LIMIT = 400;
const DEFAULT_PROJECT_ID = "world-notes-prod";

function argValue(name: string): string | null {
  const prefix = `${name}=`;
  const arg = process.argv.slice(2).find((value) => value.startsWith(prefix));
  return arg ? arg.slice(prefix.length) : null;
}

function nonEmptyString(value: unknown): string | null {
  return typeof value === "string" && value.trim().length > 0 ?
    value.trim() :
    null;
}

function migratedPaths(
  imageStoragePath: string,
  imageStoragePaths: unknown,
): string[] {
  if (!Array.isArray(imageStoragePaths) || imageStoragePaths.length === 0) {
    return [imageStoragePath];
  }
  return imageStoragePaths
    .map((path) => nonEmptyString(path))
    .filter((path): path is string => path !== null);
}

async function commitPending(updates: PendingUpdate[]): Promise<void> {
  if (updates.length === 0) return;

  const db = getFirestore();
  const batch = db.batch();
  for (const update of updates) {
    batch.update(update.ref, update.data);
  }
  await batch.commit();
}

async function main(): Promise<void> {
  const dryRun = process.argv.includes("--dry-run");
  const limitArg = argValue("--limit");
  const limit = limitArg == null ? null : Number.parseInt(limitArg, 10);
  if (limit != null && (!Number.isFinite(limit) || limit <= 0)) {
    throw new Error("--limit must be a positive integer.");
  }

  initializeApp({projectId: argValue("--project-id") ?? DEFAULT_PROJECT_ID});

  const db = getFirestore();
  const snap = await db
    .collectionGroup("messages")
    .select("imageStoragePath", "imageStoragePaths")
    .get();

  let scanned = 0;
  let migrated = 0;
  const pending: PendingUpdate[] = [];

  for (const doc of snap.docs) {
    scanned += 1;
    if (limit != null && migrated >= limit) break;

    const imageStoragePath = nonEmptyString(doc.get("imageStoragePath"));
    if (imageStoragePath == null) continue;

    const imageStoragePaths = migratedPaths(
      imageStoragePath,
      doc.get("imageStoragePaths"),
    );
    if (imageStoragePaths.length === 0) continue;

    migrated += 1;
    const data: UpdateData<DocumentData> = {
      imageStoragePaths,
      imageStoragePath: FieldValue.delete(),
    };

    if (dryRun) {
      console.log(`${doc.ref.path}: ${JSON.stringify(imageStoragePaths)}`);
      continue;
    }

    pending.push({ref: doc.ref, data});
    if (pending.length >= BATCH_LIMIT) {
      await commitPending(pending);
      pending.length = 0;
    }
  }

  if (!dryRun) {
    await commitPending(pending);
  }

  console.log(
    `${dryRun ? "Would migrate" : "Migrated"} ${migrated} messages ` +
      `after scanning ${scanned}.`,
  );
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
