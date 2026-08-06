/* eslint-disable require-jsdoc, valid-jsdoc */

import {createHash} from "node:crypto";

import {
  DocumentSnapshot,
  Firestore,
  Timestamp,
  Transaction,
} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/v2/https";

import {GLOBAL_OPERATION_TERMINAL_RETENTION_MILLIS} from "./globalOperations";
import {ImageStorageRoute, parseImageStorageRoute} from "./imageAccess";
import {enqueueStorageObjectDeletion} from "./storageObjectCleanup";

export const IMAGE_UPLOAD_ORPHAN_GRACE_MILLIS = 24 * 60 * 60 * 1000;
export const IMAGE_UPLOAD_SWEEP_BATCH_SIZE = 50;

export type ImageUploadStatus =
  "unreferenced" | "referenced" | "deletionQueued" | "deleted";

export interface ImageUploadData {
  readonly objectPath: string;
  readonly ownerUid: string;
  readonly contentKind: "message" | "pin";
  readonly generation: string | null;
  readonly status: ImageUploadStatus;
  readonly contentPath: string | null;
  readonly uploadedAt: Timestamp | null;
  readonly checkAfter: Timestamp | null;
  readonly updatedAt: Timestamp;
  readonly expireAt: Timestamp | null;
}

export interface ImageUploadSweepResult {
  readonly inspected: number;
  readonly referenced: number;
  readonly queued: number;
}

type OrphanImageDeletionOutcome = "skipped" | "referenced" | "queued";

/** Returns the deterministic tracker ID for one immutable object path. */
export function imageUploadId(objectPath: string): string {
  parseImageStorageRoute(objectPath);
  return createHash("sha256").update(objectPath, "utf8").digest("hex");
}

/** Records a finalized regional object without weakening an existing bind. */
export async function recordFinalizedImageUpload(
  firestore: Firestore,
  input: Readonly<{
    objectPath: string;
    generation: string;
    uploadedAt: Timestamp;
  }>,
): Promise<void> {
  const route = parseImageStorageRoute(input.objectPath);
  requireGeneration(input.generation);
  const reference = firestore.collection("imageUploads")
    .doc(imageUploadId(input.objectPath));
  await firestore.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(reference);
    if (!snapshot.exists) {
      transaction.create(reference, finalizedUploadData(route, input));
      return;
    }
    const current = parseImageUpload(snapshot, input.objectPath);
    if (current.generation !== null &&
        current.generation !== input.generation &&
        current.status === "referenced") {
      throw new Error("A referenced image path received another generation.");
    }
    const replacement = current.generation !== null &&
      current.generation !== input.generation;
    transaction.set(reference, replacement ?
      finalizedUploadData(route, input) : {
        ...current,
        generation: input.generation,
        uploadedAt: current.uploadedAt ?? input.uploadedAt,
        checkAfter: current.status === "unreferenced" ?
          Timestamp.fromMillis(
            input.uploadedAt.toMillis() + IMAGE_UPLOAD_ORPHAN_GRACE_MILLIS,
          ) : current.checkAfter,
        updatedAt: input.uploadedAt,
      });
  });
}

/** Binds accepted content to uploads in the same authority transaction. */
export async function bindImageUploadsToContent(
  transaction: Transaction,
  firestore: Firestore,
  objectPaths: readonly string[],
  contentPath: string,
  now: Timestamp,
): Promise<void> {
  if (objectPaths.length === 0) return;
  const routes = objectPaths.map(parseImageStorageRoute);
  const references = routes.map((route) => firestore
    .collection("imageUploads").doc(imageUploadId(route.storagePath)));
  const snapshots = await Promise.all(
    references.map((reference) => transaction.get(reference)),
  );
  for (let index = 0; index < routes.length; index++) {
    const route = routes[index];
    requireMatchingContentPath(route, contentPath);
    const snapshot = snapshots[index];
    const current = snapshot.exists ?
      parseImageUpload(snapshot, route.storagePath) : null;
    if (current?.status === "deletionQueued" ||
        current?.status === "deleted" ||
        (current?.status === "referenced" &&
         current.contentPath !== contentPath)) {
      throw new HttpsError(
        "failed-precondition",
        "The image upload is no longer attachable.",
        {reason: "image_upload_expired"},
      );
    }
    transaction.set(references[index], {
      objectPath: route.storagePath,
      ownerUid: route.ownerUid,
      contentKind: route.kind,
      generation: current?.generation ?? null,
      status: "referenced",
      contentPath,
      uploadedAt: current?.uploadedAt ?? null,
      checkAfter: current?.checkAfter ?? null,
      updatedAt: now,
      expireAt: Timestamp.fromMillis(
        now.toMillis() + GLOBAL_OPERATION_TERMINAL_RETENTION_MILLIS,
      ),
    });
  }
}

/** Queues due unreferenced objects after rechecking their content document. */
export async function sweepOrphanImageUploads(
  firestore: Firestore,
  world: string,
  now: Timestamp = Timestamp.now(),
): Promise<ImageUploadSweepResult> {
  const due = await firestore.collection("imageUploads")
    .where("status", "==", "unreferenced")
    .where("checkAfter", "<=", now)
    .orderBy("checkAfter")
    .limit(IMAGE_UPLOAD_SWEEP_BATCH_SIZE)
    .get();
  let referenced = 0;
  let queued = 0;
  for (const snapshot of due.docs) {
    const outcome = await queueOrphanImageDeletion(
      firestore,
      world,
      snapshot.id,
      now,
    );
    if (outcome === "referenced") referenced += 1;
    if (outcome === "queued") queued += 1;
  }
  return {inspected: due.size, referenced, queued};
}

async function queueOrphanImageDeletion(
  firestore: Firestore,
  world: string,
  trackerId: string,
  now: Timestamp,
): Promise<OrphanImageDeletionOutcome> {
  const trackerRef = firestore.collection("imageUploads").doc(trackerId);
  return firestore.runTransaction(async (transaction) => {
    const trackerSnapshot = await transaction.get(trackerRef);
    if (!trackerSnapshot.exists) return "skipped";
    const tracker = parseImageUpload(trackerSnapshot);
    if (tracker.status !== "unreferenced" || tracker.checkAfter === null ||
        tracker.checkAfter.toMillis() > now.toMillis()) {
      return "skipped";
    }
    const route = parseImageStorageRoute(tracker.objectPath);
    const contentRef = contentReference(firestore, route);
    const content = await transaction.get(contentRef);
    const contentPath = contentReferencesImage(content, route) ?
      contentRef.path : null;
    if (contentPath !== null) {
      transaction.update(trackerRef, {
        status: "referenced",
        contentPath,
        updatedAt: now,
        expireAt: Timestamp.fromMillis(
          now.toMillis() + GLOBAL_OPERATION_TERMINAL_RETENTION_MILLIS,
        ),
      });
      return "referenced";
    }
    if (tracker.generation === null) {
      throw new Error("Orphan image generation has not been observed.");
    }
    enqueueStorageObjectDeletion(transaction, firestore, {
      sourceOperationId: `orphan:${trackerId}:${tracker.generation}`,
      revision: 1,
      world,
      objectPath: tracker.objectPath,
      generation: tracker.generation,
      createdAt: now,
    });
    transaction.update(trackerRef, {
      status: "deletionQueued",
      updatedAt: now,
      expireAt: null,
    });
    return "queued";
  });
}

function finalizedUploadData(
  route: ImageStorageRoute,
  input: Readonly<{
    generation: string;
    uploadedAt: Timestamp;
  }>,
): ImageUploadData {
  return Object.freeze({
    objectPath: route.storagePath,
    ownerUid: route.ownerUid,
    contentKind: route.kind,
    generation: input.generation,
    status: "unreferenced",
    contentPath: null,
    uploadedAt: input.uploadedAt,
    checkAfter: Timestamp.fromMillis(
      input.uploadedAt.toMillis() + IMAGE_UPLOAD_ORPHAN_GRACE_MILLIS,
    ),
    updatedAt: input.uploadedAt,
    expireAt: null,
  });
}

function parseImageUpload(
  snapshot: DocumentSnapshot,
  expectedPath?: string,
): ImageUploadData {
  const objectPath = snapshot.get("objectPath");
  const ownerUid = snapshot.get("ownerUid");
  const contentKind = snapshot.get("contentKind");
  const generation = snapshot.get("generation");
  const status = snapshot.get("status");
  const contentPath = snapshot.get("contentPath");
  const uploadedAt = snapshot.get("uploadedAt");
  const checkAfter = snapshot.get("checkAfter");
  const updatedAt = snapshot.get("updatedAt");
  const expireAt = snapshot.get("expireAt");
  if (typeof objectPath !== "string" ||
      (expectedPath !== undefined && objectPath !== expectedPath) ||
      typeof ownerUid !== "string" || ownerUid.length === 0 ||
      (contentKind !== "message" && contentKind !== "pin") ||
      (generation !== null && typeof generation !== "string") ||
      (status !== "unreferenced" && status !== "referenced" &&
       status !== "deletionQueued" && status !== "deleted") ||
      (contentPath !== null && typeof contentPath !== "string") ||
      (uploadedAt !== null && !(uploadedAt instanceof Timestamp)) ||
      (checkAfter !== null && !(checkAfter instanceof Timestamp)) ||
      !(updatedAt instanceof Timestamp) ||
      (expireAt !== null && !(expireAt instanceof Timestamp))) {
    throw new Error("Image upload tracker is invalid.");
  }
  parseImageStorageRoute(objectPath);
  return Object.freeze({
    objectPath,
    ownerUid,
    contentKind,
    generation,
    status,
    contentPath,
    uploadedAt,
    checkAfter,
    updatedAt,
    expireAt,
  });
}

function contentReference(firestore: Firestore, route: ImageStorageRoute) {
  const place = firestore.collection("places").doc(route.placeId);
  return route.kind === "message" ?
    place.collection("messages").doc(route.messageId) : place;
}

function contentReferencesImage(
  content: DocumentSnapshot,
  route: ImageStorageRoute,
): boolean {
  if (!content.exists) return false;
  if (route.kind === "pin") {
    return content.get("pinImageStoragePath") === route.storagePath;
  }
  const paths = content.get("imageStoragePaths");
  return content.get("userId") === route.ownerUid &&
    Array.isArray(paths) && paths.includes(route.storagePath);
}

function requireMatchingContentPath(
  route: ImageStorageRoute,
  contentPath: string,
): void {
  const expected = route.kind === "message" ?
    `places/${route.placeId}/messages/${route.messageId}` :
    `places/${route.placeId}`;
  if (contentPath !== expected) {
    throw new HttpsError("invalid-argument", "Image content route mismatch.");
  }
}

function requireGeneration(value: string): void {
  if (!/^[1-9][0-9]{0,31}$/.test(value)) {
    throw new Error("Image upload generation is invalid.");
  }
}
