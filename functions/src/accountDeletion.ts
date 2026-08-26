/* eslint-disable require-jsdoc, valid-jsdoc */

import {createHash} from "node:crypto";

import {getAuth} from "firebase-admin/auth";
import {
  DocumentReference,
  DocumentSnapshot,
  FieldValue,
  Firestore,
  Timestamp,
} from "firebase-admin/firestore";

import {
  cleanupJobId,
  cleanupJobPath,
  CleanupBatchContext,
  CleanupBatchResult,
  CleanupJobHandler,
  newCleanupJobData,
  NewCleanupJobInput,
} from "./cleanupJobs";
import {onCall, HttpsError} from "./platform/worldCallable";
import {worldContext} from "./platform/worldContext";
import {WORLD_REGISTRY} from "./platform/worldRegistry";

export const DELETE_ACCOUNT_DATA_JOB = "deleteAccountData";
export const DELETE_ACCOUNT_STORAGE_JOB = "deleteAccountStorage";

const RECENT_AUTH_MAX_AGE_SECONDS = 5 * 60;
const DELETED_ACCOUNT_USER_ID = "deleted-account";
const FIRESTORE_TARGETS = "accountDeletionFirestoreTargets";
const STORAGE_TARGETS = "accountDeletionStorageTargets";
const ACCOUNT_ROOTS = [
  "userHomes",
  "publicProfiles",
  "userEntitlements",
  "userUsage",
] as const;

const FIRESTORE_STAGES = [
  "ownedNotes",
  "messages",
  "members",
  "administrators",
  "visitors",
  "noteLikes",
  "messageLikes",
  "followingEdges",
  "followerEdges",
  "blockedByOthers",
  "reportsByUser",
  "reportsAboutUser",
  "invitationsToUser",
  "invitationsByUser",
  "accountRoots",
  "complete",
] as const;

type FirestoreStage = typeof FIRESTORE_STAGES[number];

interface DeleteAccountData {
  readonly confirmation?: unknown;
}

interface AccountDeletionTarget {
  readonly uid: string;
  readonly ownedPlaceIds: readonly string[];
  readonly requestedAt: Timestamp;
}

interface CleanupCursor {
  readonly stage: FirestoreStage;
  readonly pass: number;
}

/**
 * Accepts an irreversible deletion only after recent provider reauthentication.
 * Every regional cleanup intent is durable before the Auth record is removed.
 */
export const deleteAccount = onCall<DeleteAccountData>(
  {
    auditAction: "account.delete",
    enforceAppCheck: true,
    requireHomeWorld: true,
    timeoutSeconds: 120,
  },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError("unauthenticated", "Sign in required.");
    }
    if (request.data?.confirmation !== "DELETE") {
      throw new HttpsError(
        "invalid-argument",
        "Account deletion confirmation is required.",
      );
    }
    requireRecentAuthentication(request.auth?.token.auth_time);

    const deletionId = accountDeletionId(uid);
    const requestedAt = Timestamp.now();
    const targets = await Promise.all(
      WORLD_REGISTRY.catalog.worlds.map(async (world) => {
        const firestore = worldContext(world.worldId).firestore;
        const existing = await readExistingTarget(
          firestore,
          deletionId,
          uid,
        );
        if (existing !== null) return {world: world.worldId, target: existing};
        const ownedNotes = await firestore
          .collection("places")
          .where("createdByUserId", "==", uid)
          .select()
          .get();
        return {
          world: world.worldId,
          target: Object.freeze({
            uid,
            ownedPlaceIds: ownedNotes.docs.map((snapshot) => snapshot.id),
            requestedAt,
          }),
        };
      }),
    );

    await Promise.all(targets.map(({world, target}) =>
      ensureDeletionJobs(world, deletionId, requestedAt, target),
    ));

    await getAuth().deleteUser(uid);
    return {deletionAccepted: true};
  },
);

/** Deletes account-owned Firestore content in bounded replay-safe stages. */
export const accountDeletionFirestoreHandler: CleanupJobHandler = {
  queue: "firestore",
  jobType: DELETE_ACCOUNT_DATA_JOB,
  async processBatch(context) {
    const targetRef = context.firestore
      .collection(FIRESTORE_TARGETS)
      .doc(context.job.entityId);
    const snapshot = await targetRef.get();
    if (!snapshot.exists) return {complete: true};
    const target = parseTarget(snapshot);
    const cursor = parseCursor(context.job.cursor);
    const result = await processFirestoreStage(
      context,
      targetRef,
      target,
      cursor.stage,
    );
    if (!result.complete) {
      return incomplete(cursor.stage, cursor.pass + 1);
    }
    const next = nextStage(cursor.stage);
    if (next === null) return {complete: true};
    return incomplete(next, cursor.pass + 1);
  },
};

/** Deletes tracked Storage objects owned by the account or its notes. */
export const accountDeletionStorageHandler: CleanupJobHandler = {
  queue: "storage",
  jobType: DELETE_ACCOUNT_STORAGE_JOB,
  async processBatch(context) {
    if (context.bucket === undefined) {
      throw new Error("Account deletion bucket is unavailable.");
    }
    const targetRef = context.firestore
      .collection(STORAGE_TARGETS)
      .doc(context.job.entityId);
    const snapshot = await targetRef.get();
    if (!snapshot.exists) return {complete: true};
    const target = parseTarget(snapshot);
    const cursor = parseStorageCursor(context.job.cursor);

    if (cursor.stage === "ownedUploads") {
      const upload = await context.firestore.collection("imageUploads")
        .where("ownerUid", "==", target.uid)
        .limit(1)
        .get();
      if (!upload.empty) {
        await deleteTrackedObject(context, upload.docs[0].ref);
        return storageIncomplete("ownedUploads", cursor.pass + 1, 0);
      }
      return storageIncomplete("ownedNotes", cursor.pass + 1, 0);
    }

    for (let index = cursor.placeIndex;
      index < target.ownedPlaceIds.length;
      index += 1) {
      const prefix = `places/${target.ownedPlaceIds[index]}`;
      const exactUpload = await context.firestore.collection("imageUploads")
        .where("contentPath", "==", prefix)
        .limit(1)
        .get();
      const upload = exactUpload.empty ?
        await context.firestore.collection("imageUploads")
          .where("contentPath", ">=", `${prefix}/`)
          .where("contentPath", "<", `${prefix}/\uf8ff`)
          .limit(1)
          .get() : exactUpload;
      if (!upload.empty) {
        await deleteTrackedObject(context, upload.docs[0].ref);
        return storageIncomplete("ownedNotes", cursor.pass + 1, index);
      }
    }

    await targetRef.delete();
    return {complete: true};
  },
};

export function requireRecentAuthentication(
  value: unknown,
  nowSeconds = Math.floor(Date.now() / 1000),
): void {
  if (typeof value !== "number" || !Number.isFinite(value)) {
    throw new HttpsError(
      "failed-precondition",
      "Recent authentication is required.",
      {reason: "recent-login-required"},
    );
  }
  const age = nowSeconds - value;
  if (age < 0 || age > RECENT_AUTH_MAX_AGE_SECONDS) {
    throw new HttpsError(
      "failed-precondition",
      "Recent authentication is required.",
      {reason: "recent-login-required"},
    );
  }
}

export function accountDeletionId(uid: string): string {
  return createHash("sha256")
    .update(`account-deletion:${uid}`, "utf8")
    .digest("hex");
}

async function readExistingTarget(
  firestore: Firestore,
  deletionId: string,
  uid: string,
): Promise<AccountDeletionTarget | null> {
  const snapshots = await Promise.all([
    firestore.collection(FIRESTORE_TARGETS).doc(deletionId).get(),
    firestore.collection(STORAGE_TARGETS).doc(deletionId).get(),
  ]);
  const existing = snapshots.find((snapshot) => snapshot.exists);
  if (existing === undefined) return null;
  const target = parseTarget(existing);
  if (target.uid !== uid) {
    throw new Error("Account deletion target identity collision.");
  }
  return target;
}

async function ensureDeletionJobs(
  world: string,
  deletionId: string,
  requestedAt: Timestamp,
  target: AccountDeletionTarget,
): Promise<void> {
  const firestore = worldContext(world).firestore;
  const inputs = [
    deletionJobInput(world, deletionId, "firestore", DELETE_ACCOUNT_DATA_JOB),
    deletionJobInput(world, deletionId, "storage", DELETE_ACCOUNT_STORAGE_JOB),
  ] as const;
  await firestore.runTransaction(async (transaction) => {
    const references = inputs.map((input) => firestore.doc(
      cleanupJobPath(input.queue, cleanupJobId(input)),
    ));
    const targetReferences = [
      firestore.collection(FIRESTORE_TARGETS).doc(deletionId),
      firestore.collection(STORAGE_TARGETS).doc(deletionId),
    ];
    const snapshots = await Promise.all([
      ...references.map((reference) => transaction.get(reference)),
      ...targetReferences.map((reference) => transaction.get(reference)),
    ]);
    for (let index = 0; index < inputs.length; index += 1) {
      const job = snapshots[index];
      const targetSnapshot = snapshots[index + inputs.length];
      if (!job.exists) {
        transaction.set(targetReferences[index], {
          ...target,
          ownedPlaceIds: [...target.ownedPlaceIds],
        });
        transaction.create(references[index], {
          ...newCleanupJobData(inputs[index], requestedAt),
        });
      } else if (job.get("status") !== "complete" &&
          !targetSnapshot.exists) {
        transaction.set(targetReferences[index], {
          ...target,
          ownedPlaceIds: [...target.ownedPlaceIds],
        });
      }
    }
  });
}

function deletionJobInput(
  world: string,
  deletionId: string,
  queue: "firestore" | "storage",
  jobType: string,
): NewCleanupJobInput {
  return {
    sourceOperationId: deletionId,
    entityType: "accountDeletion",
    entityId: deletionId,
    revision: 1,
    world,
    queue,
    jobType,
  };
}

async function processFirestoreStage(
  context: CleanupBatchContext,
  targetRef: DocumentReference,
  target: AccountDeletionTarget,
  stage: FirestoreStage,
): Promise<CleanupBatchResult> {
  switch (stage) {
  case "ownedNotes":
    return deleteOwnedNote(context, target);
  case "messages":
    return deleteAuthoredMessage(context.firestore, target.uid);
  case "members":
    return deleteParticipation(context.firestore, "members", target.uid);
  case "administrators":
    return deleteParticipation(
      context.firestore,
      "administrators",
      target.uid,
      "administratorCount",
    );
  case "visitors":
    return deleteParticipation(
      context.firestore,
      "visitors",
      target.uid,
      "visitorCount",
    );
  case "noteLikes":
    return deleteParticipation(
      context.firestore,
      "likes",
      target.uid,
      "likeCount",
      "liked",
    );
  case "messageLikes":
    return deleteParticipation(
      context.firestore,
      "likedMessages",
      target.uid,
    );
  case "followingEdges":
    return deleteSocialEdge(context.firestore, "followerUid", target.uid);
  case "followerEdges":
    return deleteSocialEdge(context.firestore, "followeeUid", target.uid);
  case "blockedByOthers":
    return deleteOneByField(
      context.firestore,
      "blockedUsers",
      "blockedUid",
      target.uid,
      true,
    );
  case "reportsByUser":
    return deleteOneByField(
      context.firestore,
      "reports",
      "reporterId",
      target.uid,
    );
  case "reportsAboutUser":
    return clearOneField(
      context.firestore,
      "reports",
      "reportedUserId",
      target.uid,
    );
  case "invitationsToUser":
    return deleteOneByField(
      context.firestore,
      "noteAdministratorInvitations",
      "targetUid",
      target.uid,
    );
  case "invitationsByUser":
    return deleteOneByField(
      context.firestore,
      "noteAdministratorInvitations",
      "invitedByUid",
      target.uid,
    );
  case "accountRoots":
    return deleteAccountRoots(context.firestore, target.uid);
  case "complete":
    await targetRef.delete();
    return {complete: true};
  }
}

async function deleteOwnedNote(
  context: CleanupBatchContext,
  target: AccountDeletionTarget,
): Promise<CleanupBatchResult> {
  for (const placeId of target.ownedPlaceIds) {
    const placeRef = context.firestore.collection("places").doc(placeId);
    const place = await placeRef.get();
    if (!place.exists) continue;
    const related = [
      "moderationReviews",
      "reports",
      "noteAdministratorInvitations",
      "noteAdministratorInviteNotifications",
      "moderationRetentionTargets",
      "noteModerationRetentionTargets",
    ];
    for (const collection of related) {
      const deleted = await deleteQueryBatch(
        context.firestore.collection(collection)
          .where("placeId", "==", placeId)
          .limit(100),
      );
      if (deleted > 0) return {complete: false, cursor: "owned-note-related"};
    }
    await context.firestore.recursiveDelete(placeRef);
    return {complete: false, cursor: "owned-note"};
  }
  return {complete: true};
}

async function deleteAuthoredMessage(
  firestore: Firestore,
  uid: string,
): Promise<CleanupBatchResult> {
  const messages = await firestore.collectionGroup("messages")
    .where("userId", "==", uid)
    .limit(1)
    .get();
  if (messages.empty) return {complete: true};
  const messageRef = messages.docs[0].ref;
  const placeRef = messageRef.parent.parent;
  if (placeRef === null) throw new Error("Message parent is invalid.");
  const messageId = messageRef.id;
  const placeId = placeRef.id;
  await firestore.runTransaction(async (transaction) => {
    const message = await transaction.get(messageRef);
    if (!message.exists || message.get("userId") !== uid) return;
    if (message.get("isPubliclyVisible") === true) {
      transaction.update(messageRef, {
        userId: DELETED_ACCOUNT_USER_ID,
        userName: "Deleted user",
        userPhotoUrl: null,
        content: "",
        imageStoragePaths: FieldValue.delete(),
        moderationRiskSignals: FieldValue.delete(),
        isDeleted: true,
        deletedAt: Timestamp.now(),
        deletedReason: "account",
      });
      return;
    }
    const counterRef = placeRef.collection("counters").doc("messageSlots");
    const counter = await transaction.get(counterRef);
    const count = counter.get("count");
    if (typeof count === "number") {
      transaction.set(counterRef, {
        count: Math.max(0, count - 1),
        updatedAt: Timestamp.now(),
      }, {merge: true});
    }
    transaction.delete(messageRef);
  });
  await Promise.all([
    firestore.collection("moderationReviews")
      .doc(`${placeId}_${messageId}`).delete(),
    deleteQueryBatch(firestore.collection("reports")
      .where("targetPath", "==", messageRef.path).limit(100)),
  ]);
  return {complete: false, cursor: "message"};
}

async function deleteParticipation(
  firestore: Firestore,
  collection: string,
  uid: string,
  counterField?: string,
  contributionField?: string,
): Promise<CleanupBatchResult> {
  const matches = await firestore.collectionGroup(collection)
    .where("userId", "==", uid)
    .limit(1)
    .get();
  if (matches.empty) return {complete: true};
  const reference = matches.docs[0].ref;
  const placeRef = reference.parent.parent;
  await firestore.runTransaction(async (transaction) => {
    const current = await transaction.get(reference);
    if (!current.exists || current.get("userId") !== uid) return;
    if (counterField !== undefined && placeRef !== null &&
        (contributionField === undefined ||
         current.get(contributionField) === true)) {
      const place = await transaction.get(placeRef);
      const count = place.get(counterField);
      if (place.exists && typeof count === "number") {
        transaction.update(placeRef, {
          [counterField]: Math.max(0, count - 1),
        });
      }
    }
    transaction.delete(reference);
  });
  return {complete: false, cursor: collection};
}

async function deleteSocialEdge(
  firestore: Firestore,
  field: "followerUid" | "followeeUid",
  uid: string,
): Promise<CleanupBatchResult> {
  const edges = await firestore.collection("socialEdges")
    .where(field, "==", uid)
    .limit(1)
    .get();
  if (edges.empty) return {complete: true};
  const edgeRef = edges.docs[0].ref;
  await firestore.runTransaction(async (transaction) => {
    const edge = await transaction.get(edgeRef);
    if (!edge.exists || edge.get(field) !== uid) return;
    const followerUid = edge.get("followerUid");
    const followeeUid = edge.get("followeeUid");
    if (edge.get("following") === true &&
        typeof followerUid === "string" &&
        typeof followeeUid === "string") {
      const followerRef = firestore.collection("publicProfiles")
        .doc(followerUid);
      const followeeRef = firestore.collection("publicProfiles")
        .doc(followeeUid);
      const [follower, followee] = await Promise.all([
        transaction.get(followerRef),
        transaction.get(followeeRef),
      ]);
      if (follower.exists) {
        const count = follower.get("followingCount");
        if (typeof count === "number") {
          transaction.update(followerRef, {
            followingCount: Math.max(0, count - 1),
          });
        }
      }
      if (followee.exists) {
        const count = followee.get("followerCount");
        if (typeof count === "number") {
          transaction.update(followeeRef, {
            followerCount: Math.max(0, count - 1),
          });
        }
      }
    }
    transaction.delete(edgeRef);
  });
  return {complete: false, cursor: field};
}

async function deleteOneByField(
  firestore: Firestore,
  collection: string,
  field: string,
  value: string,
  collectionGroup = false,
): Promise<CleanupBatchResult> {
  const query = collectionGroup ?
    firestore.collectionGroup(collection) : firestore.collection(collection);
  const matches = await query.where(field, "==", value).limit(1).get();
  if (matches.empty) return {complete: true};
  await matches.docs[0].ref.delete();
  return {complete: false, cursor: `${collection}:${field}`};
}

async function clearOneField(
  firestore: Firestore,
  collection: string,
  field: string,
  value: string,
): Promise<CleanupBatchResult> {
  const matches = await firestore.collection(collection)
    .where(field, "==", value)
    .limit(1)
    .get();
  if (matches.empty) return {complete: true};
  await matches.docs[0].ref.update({[field]: null});
  return {complete: false, cursor: `${collection}:${field}`};
}

async function deleteAccountRoots(
  firestore: Firestore,
  uid: string,
): Promise<CleanupBatchResult> {
  await firestore.recursiveDelete(firestore.collection("users").doc(uid));
  await firestore.recursiveDelete(
    firestore.collection("accountSafety").doc(uid),
  );
  const batch = firestore.batch();
  for (const collection of ACCOUNT_ROOTS) {
    batch.delete(firestore.collection(collection).doc(uid));
  }
  batch.delete(firestore.collection("accountHomeReservations").doc(uid));
  await batch.commit();
  return {complete: true};
}

async function deleteQueryBatch(
  query: FirebaseFirestore.Query,
): Promise<number> {
  const snapshots = await query.get();
  if (snapshots.empty) return 0;
  const batch = snapshots.docs[0].ref.firestore.batch();
  for (const snapshot of snapshots.docs) batch.delete(snapshot.ref);
  await batch.commit();
  return snapshots.size;
}

async function deleteTrackedObject(
  context: CleanupBatchContext,
  trackerRef: DocumentReference,
): Promise<void> {
  if (context.bucket === undefined) {
    throw new Error("Account deletion bucket is unavailable.");
  }
  const tracker = await trackerRef.get();
  if (!tracker.exists) return;
  const objectPath = tracker.get("objectPath");
  if (typeof objectPath !== "string" || objectPath.length === 0) {
    throw new Error("Account image tracker is invalid.");
  }
  const file = context.bucket.file(objectPath);
  let generation: string | null = null;
  try {
    const [metadata] = await file.getMetadata();
    generation = typeof metadata.generation === "string" ?
      metadata.generation : String(metadata.generation ?? "");
    if (generation.length === 0) {
      throw new Error("Account image generation is invalid.");
    }
  } catch (error) {
    if (!isStorageObjectMissing(error)) throw error;
  }
  if (generation !== null) {
    await file.delete({
      ignoreNotFound: true,
      ifGenerationMatch: generation,
    });
  }
  await trackerRef.delete();
}

function isStorageObjectMissing(error: unknown): boolean {
  if (typeof error !== "object" || error === null) return false;
  const code = "code" in error ? String(error.code) : "";
  return code === "404" || code === "storage/object-not-found";
}

function parseTarget(snapshot: DocumentSnapshot): AccountDeletionTarget {
  const data = snapshot.data();
  const uid = data?.uid;
  const ownedPlaceIds = data?.ownedPlaceIds;
  const requestedAt = data?.requestedAt;
  if (typeof uid !== "string" || uid.length === 0 || uid.includes("/") ||
      !Array.isArray(ownedPlaceIds) ||
      ownedPlaceIds.some((id) => typeof id !== "string" || id.length === 0) ||
      !(requestedAt instanceof Timestamp)) {
    throw new Error("Account deletion target is invalid.");
  }
  return Object.freeze({
    uid,
    ownedPlaceIds: Object.freeze([...ownedPlaceIds]) as readonly string[],
    requestedAt,
  });
}

function parseCursor(value: string | null): CleanupCursor {
  if (value === null) return {stage: FIRESTORE_STAGES[0], pass: 0};
  const parsed = JSON.parse(value) as Record<string, unknown>;
  if (!FIRESTORE_STAGES.includes(parsed.stage as FirestoreStage) ||
      typeof parsed.pass !== "number" ||
      !Number.isSafeInteger(parsed.pass) || parsed.pass < 0) {
    throw new Error("Account deletion cursor is invalid.");
  }
  return {stage: parsed.stage as FirestoreStage, pass: parsed.pass};
}

function incomplete(stage: FirestoreStage, pass: number): CleanupBatchResult {
  return {complete: false, cursor: JSON.stringify({stage, pass})};
}

function nextStage(stage: FirestoreStage): FirestoreStage | null {
  const index = FIRESTORE_STAGES.indexOf(stage);
  return index >= FIRESTORE_STAGES.length - 1 ? null :
    FIRESTORE_STAGES[index + 1];
}

function parseStorageCursor(value: string | null): {
  readonly stage: "ownedUploads" | "ownedNotes";
  readonly pass: number;
  readonly placeIndex: number;
} {
  if (value === null) {
    return {stage: "ownedUploads", pass: 0, placeIndex: 0};
  }
  const parsed = JSON.parse(value) as Record<string, unknown>;
  if ((parsed.stage !== "ownedUploads" && parsed.stage !== "ownedNotes") ||
      typeof parsed.pass !== "number" ||
      !Number.isSafeInteger(parsed.pass) || parsed.pass < 0 ||
      typeof parsed.placeIndex !== "number" ||
      !Number.isSafeInteger(parsed.placeIndex) || parsed.placeIndex < 0) {
    throw new Error("Account deletion Storage cursor is invalid.");
  }
  return {
    stage: parsed.stage,
    pass: parsed.pass,
    placeIndex: parsed.placeIndex,
  };
}

function storageIncomplete(
  stage: "ownedUploads" | "ownedNotes",
  pass: number,
  placeIndex: number,
): CleanupBatchResult {
  return {
    complete: false,
    cursor: JSON.stringify({stage, pass, placeIndex}),
  };
}
