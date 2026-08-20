/* eslint-disable require-jsdoc, valid-jsdoc */

import {createHash} from "node:crypto";

import {
  DocumentSnapshot,
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
import {GLOBAL_OPERATION_TERMINAL_RETENTION_MILLIS} from "./globalOperations";
import {WorldBucket} from "./platform/worldBucketProvider";

export const DELETE_STORAGE_OBJECT_JOB = "deleteStorageObject";

const MANIFEST_FIELDS = new Set([
  "objectPath",
  "generation",
  "sourceOperationId",
  "revision",
  "world",
  "createdAt",
]);

interface StorageObjectManifest {
  readonly objectPath: string;
  // Null only when cleanup is committed before the finalize event has stored
  // the object's generation. The worker resolves it before deleting.
  readonly generation: string | null;
  readonly sourceOperationId: string;
  readonly revision: number;
  readonly world: string;
  readonly createdAt: Timestamp;
}

type StorageObjectDeletionTarget =
  | Readonly<{status: "missing"}>
  | Readonly<{status: "present"; generation: string}>;

type WorldFile = ReturnType<WorldBucket["file"]>;

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
    const trackerRef = firestore.collection("imageUploads").doc(job.entityId);
    const trackerBeforeDelete = await trackerRef.get();
    const file = bucket.file(manifest.objectPath);
    const target = await resolveStorageObjectDeletionTarget(
      file,
      manifest,
      trackerBeforeDelete,
    );

    let generationMatched = true;
    try {
      if (target.status === "present") {
        await file.delete({
          ignoreNotFound: true,
          ifGenerationMatch: target.generation,
        });
      }
    } catch (error) {
      if (!isGenerationPreconditionFailure(error)) throw error;
      generationMatched = false;
    }
    await firestore.runTransaction(async (transaction) => {
      const tracker = await transaction.get(trackerRef);
      if (generationMatched && tracker.exists &&
          tracker.get("objectPath") === manifest.objectPath &&
          (target.status === "missing" ||
           tracker.get("generation") === null ||
           tracker.get("generation") === target.generation)) {
        const completedAt = Timestamp.now();
        transaction.update(trackerRef, {
          status: "deleted",
          updatedAt: completedAt,
          expireAt: Timestamp.fromMillis(
            completedAt.toMillis() +
              GLOBAL_OPERATION_TERMINAL_RETENTION_MILLIS,
          ),
        });
      }
      transaction.delete(manifestRef);
    });
    return {complete: true};
  },
};

/**
 * Resolves an exact generation even when finalize delivery is still pending.
 */
async function resolveStorageObjectDeletionTarget(
  file: WorldFile,
  manifest: StorageObjectManifest,
  tracker: DocumentSnapshot,
): Promise<StorageObjectDeletionTarget> {
  if (manifest.generation !== null) {
    return {status: "present", generation: manifest.generation};
  }
  if (tracker.exists && tracker.get("objectPath") === manifest.objectPath) {
    const trackedGeneration = tracker.get("generation");
    if (typeof trackedGeneration === "string") {
      return {
        status: "present",
        generation: requireGeneration(trackedGeneration),
      };
    }
  }
  try {
    const [metadata] = await file.getMetadata();
    return {
      status: "present",
      generation: requireGeneration(String(metadata.generation)),
    };
  } catch (error) {
    if (!isStorageObjectMissing(error)) throw error;
    return {status: "missing"};
  }
}

/** Creates one path-bound manifest and queue job in the source transaction. */
export function enqueueStorageObjectDeletion(
  transaction: Transaction,
  firestore: Firestore,
  input: {
    readonly sourceOperationId: string;
    readonly revision: number;
    readonly world: string;
    readonly objectPath: string;
    // Omitted when the producer must commit cleanup before finalize delivery.
    readonly generation?: string;
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
      generation: input.generation === undefined ?
        null : requireGeneration(input.generation),
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
    generation: data.generation === null ?
      null : requireGeneration(data.generation),
    sourceOperationId: data.sourceOperationId,
    revision: data.revision,
    world: data.world,
    createdAt: data.createdAt,
  });
}

function requireGeneration(value: unknown): string {
  if (typeof value !== "string" || !/^[1-9][0-9]{0,31}$/.test(value)) {
    throw new Error("Storage cleanup generation is invalid.");
  }
  return value;
}

function isGenerationPreconditionFailure(error: unknown): boolean {
  if (typeof error !== "object" || error === null) return false;
  const candidate = error as {code?: unknown; statusCode?: unknown};
  return candidate.code === 412 || candidate.statusCode === 412;
}

function isStorageObjectMissing(error: unknown): boolean {
  if (typeof error !== "object" || error === null) return false;
  const candidate = error as {code?: unknown; statusCode?: unknown};
  return candidate.code === 404 || candidate.statusCode === 404;
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
