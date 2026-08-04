/* eslint-disable require-jsdoc, valid-jsdoc */

import {Firestore, Timestamp} from "firebase-admin/firestore";

import {
  executeAdminAccountSafetyUpdate,
  parseAccountSafetyProjection,
  parseAdminAccountSafetyAction,
} from "./accountSafety";
import {REGION} from "./constants";
import {
  GlobalOperationBindingError,
  GlobalOperationValidationError,
} from "./globalOperations";
import {onCall, HttpsError} from "./platform/worldCallable";
import {
  WorldDatabaseConfig,
  WorldFirestoreDatabaseId,
  WorldFirestoreProvider,
} from "./platform/worldFirestoreProvider";
import {WORLD_CATALOG} from "./platform/worldCatalog";
import {ASIA_WORLD_ID, WORLD_REGISTRY} from "./platform/worldRegistry";

const DEFAULT_AUDIT_LIMIT = 20;
const MAX_AUDIT_LIMIT = 50;
const worldDatabases = WORLD_CATALOG.worlds.map((world) => ({
  worldId: world.worldId,
  databaseId: world.databaseId as WorldFirestoreDatabaseId,
})) satisfies readonly WorldDatabaseConfig[];
const worldFirestore = new WorldFirestoreProvider(worldDatabases);

interface AdminGetAccountSafetyData {
  readonly targetUid?: unknown;
  readonly auditLimit?: unknown;
}

interface AdminUpdateAccountSafetyData {
  readonly targetUid?: unknown;
  readonly operationId?: unknown;
  readonly action?: unknown;
  readonly reason?: unknown;
  readonly reference?: unknown;
}

export const adminGetAccountSafety = onCall<AdminGetAccountSafetyData>(
  {enforceAppCheck: true, region: REGION},
  async (request, sourceWorld) => {
    assertAdmin(request.auth?.uid, request.auth?.token.admin);
    const targetUid = requireUid(request.data?.targetUid);
    const auditLimit = requireAuditLimit(request.data?.auditLimit);
    const authority = await resolveTargetAuthority(
      sourceWorld.firestore,
      sourceWorld.worldId,
      targetUid,
    );
    const safetyRef = authority.firestore
      .collection("accountSafety")
      .doc(targetUid);
    const [safetySnapshot, audits] = await Promise.all([
      safetyRef.get(),
      safetyRef.collection("adminAudits")
        .orderBy("createdAt", "desc")
        .limit(auditLimit)
        .get(),
    ]);
    const safety = parseAccountSafetyProjection(
      safetySnapshot,
      authority.worldId,
    );
    return {
      targetUid,
      authorityWorld: authority.worldId,
      revision: safety.revision,
      violationPoints: safety.violationPoints,
      lastViolationAtMillis: millis(safety.lastViolationAt),
      nextPointDecayAtMillis: millis(safety.nextPointDecayAt),
      restrictedUntilMillis: millis(safety.restrictedUntil),
      bannedUntilMillis: millis(safety.bannedUntil),
      isPermanentlyBanned: safety.isPermanentlyBanned,
      updatedAtMillis: safety.updatedAt.toMillis(),
      audits: audits.docs.map((audit) => ({
        operationId: audit.id,
        adminUid: audit.get("adminUid") ?? null,
        action: audit.get("action") ?? null,
        reason: audit.get("reason") ?? null,
        reference: audit.get("reference") ?? null,
        revision: audit.get("revision") ?? null,
        createdAtMillis: millis(audit.get("createdAt")),
      })),
    };
  },
);

export const adminUpdateAccountSafety = onCall<AdminUpdateAccountSafetyData>(
  {enforceAppCheck: true, region: REGION},
  async (request, sourceWorld) => {
    const adminUid = request.auth?.uid;
    assertAdmin(adminUid, request.auth?.token.admin);
    const targetUid = requireUid(request.data?.targetUid);
    const action = parseAdminAccountSafetyAction(request.data?.action);
    const reason = requireReason(request.data?.reason);
    const reference = requireReference(request.data?.reference);
    const authority = await resolveTargetAuthority(
      sourceWorld.firestore,
      sourceWorld.worldId,
      targetUid,
    );
    try {
      return await executeAdminAccountSafetyUpdate({
        firestore: authority.firestore,
        authorityWorld: authority.worldId,
        targetUid,
        adminUid: adminUid as string,
        operationId: request.data?.operationId,
        action,
        reason,
        reference,
      });
    } catch (error) {
      throw commandError(error);
    }
  },
);

/** Resolves the target user's immutable userHomes assignment and authority. */
async function resolveTargetAuthority(
  sourceFirestore: Firestore,
  sourceWorld: string,
  uid: string,
): Promise<Readonly<{worldId: string; firestore: Firestore}>> {
  let homeAssignmentSnapshot = await sourceFirestore
    .collection("userHomes")
    .doc(uid)
    .get();
  if (!homeAssignmentSnapshot.exists && sourceWorld !== ASIA_WORLD_ID) {
    homeAssignmentSnapshot = await worldFirestore.forWorld(ASIA_WORLD_ID)
      .collection("userHomes")
      .doc(uid)
      .get();
  }
  const worldId = homeAssignmentSnapshot.get("world");
  if (typeof worldId !== "string") {
    throw new HttpsError("not-found", "Target account was not found.");
  }
  try {
    WORLD_REGISTRY.requireWorld(worldId);
  } catch {
    throw new HttpsError(
      "failed-precondition",
      "Target account home assignment is invalid.",
    );
  }
  return Object.freeze({
    worldId,
    firestore: worldFirestore.forWorld(worldId),
  });
}

function assertAdmin(uid: string | undefined, claim: unknown): void {
  if (uid === undefined) {
    throw new HttpsError("unauthenticated", "Sign in required.");
  }
  if (claim !== true) {
    throw new HttpsError("permission-denied", "Admin only.");
  }
}

function requireUid(value: unknown): string {
  if (typeof value !== "string" || value.length === 0 ||
      value.length > 128 || value.includes("/") || /\s/.test(value)) {
    throw new HttpsError("invalid-argument", "targetUid is invalid.");
  }
  return value;
}

function requireAuditLimit(value: unknown): number {
  if (value === undefined) return DEFAULT_AUDIT_LIMIT;
  if (typeof value !== "number" || !Number.isInteger(value) ||
      value < 1 || value > MAX_AUDIT_LIMIT) {
    throw new HttpsError("invalid-argument", "auditLimit is invalid.");
  }
  return value;
}

function requireReason(value: unknown): string {
  if (typeof value !== "string" || value.trim().length === 0 ||
      value.trim().length > 500) {
    throw new HttpsError("invalid-argument", "reason is invalid.");
  }
  return value.trim();
}

function requireReference(value: unknown): string | null {
  if (value === undefined || value === null) return null;
  if (typeof value !== "string" || value.trim().length === 0 ||
      value.trim().length > 256) {
    throw new HttpsError("invalid-argument", "reference is invalid.");
  }
  return value.trim();
}

function millis(value: unknown): number | null {
  return value instanceof Timestamp ? value.toMillis() : null;
}

function commandError(error: unknown): unknown {
  if (error instanceof GlobalOperationBindingError) {
    return new HttpsError(
      "already-exists",
      "operationId is already bound to another command.",
    );
  }
  if (error instanceof GlobalOperationValidationError) {
    return new HttpsError("invalid-argument", error.message);
  }
  return error;
}
