/* eslint-disable require-jsdoc, valid-jsdoc */

import {createHash} from "node:crypto";

import {
  Firestore,
  Timestamp,
  Transaction,
} from "firebase-admin/firestore";

import {
  cleanupJobId,
  cleanupJobPath,
  CleanupJobHandler,
  newCleanupJobData,
  NewCleanupJobInput,
} from "./cleanupJobs";

export const DELETE_STORAGE_OBJECT_JOB = "deleteStorageObject";

const MANIFEST_FIELDS = new Set([
  "objectPath",
  "sourceOperationId",
  "revision",
  "world",
  "createdAt",
]);

interface StorageObjectManifest {
  readonly objectPath: string;
  readonly sourceOperationId: string;
  readonly revision: number;
  readonly world: string;
  readonly createdAt: Timestamp;
}

/** Deletes one explicitly manifested object and treats absence as success. */
export const storageObjectCleanupHandler: CleanupJobHandler = {
  queue: "storage",
  jobType: DELETE_STORAGE_OBJECT_JOB,
  processBatch: async ({firestore, bucket, jobId, job}) => {
    if (bucket === undefined) {
      throw new Error("Storage cleanup bucket is unavailable.");
    }
    const manifestRef = firestore
      .collection("storageCleanupObjects")
      .doc(jobId);
    const snapshot = await manifestRef.get();
    if (!snapshot.exists) return {complete: true};
    const manifest = parseStorageManifest(snapshot.data());
    if (manifest.sourceOperationId !== job.sourceOperationId ||
        manifest.revision !== job.revision ||
        manifest.world !== job.world) {
      throw new Error("Storage cleanup manifest does not match its job.");
    }
    await bucket.file(manifest.objectPath).delete({ignoreNotFound: true});
    await manifestRef.delete();
    return {complete: true};
  },
};

/** Creates one path-bound manifest and queue job in the source transaction. */
export function enqueueStorageObjectDeletion(
  transaction: Transaction,
  firestore: Firestore,
  input: {
    readonly sourceOperationId: string;
    readonly revision: number;
    readonly world: string;
    readonly objectPath: string;
    readonly createdAt: Timestamp;
  },
): void {
  const pathHash = createHash("sha256")
    .update(input.objectPath, "utf8")
    .digest("hex");
  const jobInput: NewCleanupJobInput = {
    sourceOperationId: input.sourceOperationId,
    entityType: "storageObject",
    entityId: pathHash,
    revision: input.revision,
    world: input.world,
    queue: "storage",
    jobType: DELETE_STORAGE_OBJECT_JOB,
    partition: pathHash,
  };
  const jobId = cleanupJobId(jobInput);
  transaction.create(
    firestore.doc(cleanupJobPath("storage", jobId)),
    {...newCleanupJobData(jobInput, input.createdAt)},
  );
  transaction.create(
    firestore.collection("storageCleanupObjects").doc(jobId),
    {
      objectPath: requireObjectPath(input.objectPath),
      sourceOperationId: input.sourceOperationId,
      revision: input.revision,
      world: input.world,
      createdAt: input.createdAt,
    },
  );
}

function parseStorageManifest(value: unknown): StorageObjectManifest {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    throw new Error("Storage cleanup manifest must be an object.");
  }
  const data = value as Record<string, unknown>;
  if (Object.keys(data).length !== MANIFEST_FIELDS.size ||
      [...MANIFEST_FIELDS].some((field) => !(field in data))) {
    throw new Error("Storage cleanup manifest fields are invalid.");
  }
  if (typeof data.sourceOperationId !== "string" ||
      data.sourceOperationId.length === 0 ||
      typeof data.world !== "string" || data.world.length === 0 ||
      typeof data.revision !== "number" ||
      !Number.isSafeInteger(data.revision) || data.revision <= 0 ||
      !(data.createdAt instanceof Timestamp)) {
    throw new Error("Storage cleanup manifest values are invalid.");
  }
  return Object.freeze({
    objectPath: requireObjectPath(data.objectPath),
    sourceOperationId: data.sourceOperationId,
    revision: data.revision,
    world: data.world,
    createdAt: data.createdAt,
  });
}

function requireObjectPath(value: unknown): string {
  if (typeof value !== "string" ||
      value.length === 0 || value.length > 1_024 ||
      value.startsWith("/") || value.endsWith("/") ||
      value.includes("//")) {
    throw new Error("Storage cleanup object path is invalid.");
  }
  return value;
}
