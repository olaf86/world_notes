/* eslint-disable require-jsdoc */
import {initializeApp} from "firebase-admin/app";
import {
  FieldValue,
  getFirestore,
  type DocumentData,
  type DocumentReference,
  type UpdateData,
} from "firebase-admin/firestore";
import {getStorage} from "firebase-admin/storage";

interface PendingUpdate {
  ref: DocumentReference<DocumentData>;
  data: UpdateData<DocumentData>;
}

interface StorageCopy {
  from: string;
  to: string;
}

interface NormalizedPaths {
  paths: string[];
  copies: StorageCopy[];
}

const BATCH_LIMIT = 400;
const DEFAULT_PROJECT_ID = "world-notes-prod";
const DEFAULT_STORAGE_BUCKET = "world-notes-prod.firebasestorage.app";
const UUID_V7_PATTERN =
  "[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}";
const LEGACY_MESSAGE_IMAGE_PATTERN = new RegExp(
  `^images/messages/([^/]+)/([^/]+)/(${UUID_V7_PATTERN})[.]webp$`,
);

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

function existingStoragePaths(imageStoragePaths: unknown): string[] {
  if (!Array.isArray(imageStoragePaths)) return [];
  return imageStoragePaths
    .map((path) => nonEmptyString(path))
    .filter((path): path is string => path !== null);
}

function arraysEqual(left: string[], right: string[]): boolean {
  return left.length === right.length &&
    left.every((value, index) => value === right[index]);
}

function normalizedStoragePaths(paths: string[]): NormalizedPaths {
  const copies: StorageCopy[] = [];
  const normalized = paths.map((path) => {
    const match = LEGACY_MESSAGE_IMAGE_PATTERN.exec(path);
    if (match == null) return path;

    const [, placeId, userId, messageId] = match;
    const nextPath =
      `images/messages/${placeId}/${userId}/${messageId}/0.webp`;
    copies.push({from: path, to: nextPath});
    return nextPath;
  });

  return {paths: normalized, copies};
}

async function copyStorageObjects(copies: StorageCopy[]): Promise<void> {
  if (copies.length === 0) return;
  const bucket = getStorage().bucket();
  for (const copy of copies) {
    await bucket.file(copy.from).copy(bucket.file(copy.to));
  }
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

  initializeApp({
    projectId: argValue("--project-id") ?? DEFAULT_PROJECT_ID,
    storageBucket: argValue("--storage-bucket") ?? DEFAULT_STORAGE_BUCKET,
  });

  const db = getFirestore();
  const snap = await db
    .collectionGroup("messages")
    .select("imageStoragePath", "imageStoragePaths")
    .get();

  let scanned = 0;
  let migrated = 0;
  let copied = 0;
  const pending: PendingUpdate[] = [];

  for (const doc of snap.docs) {
    scanned += 1;
    if (limit != null && migrated >= limit) break;

    const imageStoragePath = nonEmptyString(doc.get("imageStoragePath"));
    const rawImageStoragePaths = doc.get("imageStoragePaths");
    const existingPaths = existingStoragePaths(rawImageStoragePaths);
    if (
      imageStoragePath == null &&
      existingPaths.length === 0
    ) {
      continue;
    }

    const imageStoragePaths = imageStoragePath == null ?
      existingPaths :
      migratedPaths(imageStoragePath, rawImageStoragePaths);
    const normalized = normalizedStoragePaths(imageStoragePaths);
    const needsFieldDelete = imageStoragePath != null;
    const needsPathUpdate = !arraysEqual(existingPaths, normalized.paths);
    if (!needsFieldDelete && !needsPathUpdate) continue;
    if (normalized.paths.length === 0) continue;

    migrated += 1;
    copied += normalized.copies.length;
    const data: UpdateData<DocumentData> = {
      imageStoragePaths: normalized.paths,
      imageStoragePath: FieldValue.delete(),
    };

    if (dryRun) {
      console.log(`${doc.ref.path}: ${JSON.stringify(normalized.paths)}`);
      for (const copy of normalized.copies) {
        console.log(`  copy ${copy.from} -> ${copy.to}`);
      }
      continue;
    }

    await copyStorageObjects(normalized.copies);
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
      `and ${dryRun ? "would copy" : "copied"} ${copied} images ` +
      `after scanning ${scanned}.`,
  );
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
