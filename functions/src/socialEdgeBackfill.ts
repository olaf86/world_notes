/* eslint-disable require-jsdoc, valid-jsdoc */

import {
  type DocumentSnapshot,
  Timestamp,
} from "firebase-admin/firestore";

import {derivedGlobalOperationId} from "./globalOperations";
import {
  parseSocialEdgeProjection,
  socialEdgeId,
  type SocialEdgeProjection,
} from "./socialEdgeReplication";

const SOCIAL_BACKFILL_OPERATION_ROOT =
  "00000000-0000-7000-8000-000000000000";
const LEGACY_EDGE_FIELDS = new Set([
  "followerUid",
  "followeeUid",
  "createdAt",
]);

export interface SocialEdgeBackfillSource {
  readonly projection: SocialEdgeProjection;
  readonly legacy: boolean;
}

/** Parses either the canonical edge or the one production legacy shape. */
export function parseSocialEdgeBackfillSource(
  snapshot: DocumentSnapshot,
  expectedEdgeId: string,
): SocialEdgeBackfillSource {
  try {
    return Object.freeze({
      projection: parseSocialEdgeProjection(snapshot, expectedEdgeId),
      legacy: false,
    });
  } catch (canonicalError) {
    if (!snapshot.exists) throw canonicalError;
    const data = snapshot.data();
    if (data === undefined ||
        Object.keys(data).length !== LEGACY_EDGE_FIELDS.size ||
        [...LEGACY_EDGE_FIELDS].some((field) => !(field in data)) ||
        typeof data.followerUid !== "string" ||
        typeof data.followeeUid !== "string" ||
        socialEdgeId(data.followerUid, data.followeeUid) !== expectedEdgeId ||
        !(data.createdAt instanceof Timestamp)) {
      throw canonicalError;
    }
    return Object.freeze({
      projection: Object.freeze({
        followerUid: data.followerUid,
        followeeUid: data.followeeUid,
        following: true,
        revision: 1,
        createdAt: data.createdAt,
        updatedAt: data.createdAt,
      }),
      legacy: true,
    });
  }
}

/** Returns the deterministic P21 operation for one social edge. */
export function socialEdgeBackfillOperationId(edgeId: string): string {
  if (edgeId.length === 0 || edgeId.length > 256 || edgeId.includes("/")) {
    throw new Error("Social edge backfill identity is invalid.");
  }
  return derivedGlobalOperationId(
    SOCIAL_BACKFILL_OPERATION_ROOT,
    `social-edge-backfill:${edgeId}`,
  );
}

/** Enforces monotonic destination state and reports whether a copy is due. */
export function shouldWriteSocialEdge(
  source: SocialEdgeProjection,
  destination: SocialEdgeProjection | null,
): boolean {
  if (destination === null) return true;
  if (destination.revision > source.revision) {
    throw new Error("Destination social edge is ahead of its authority.");
  }
  if (destination.revision < source.revision) return true;
  if (destination.followerUid !== source.followerUid ||
      destination.followeeUid !== source.followeeUid ||
      destination.following !== source.following ||
      !sameTimestamp(destination.createdAt, source.createdAt) ||
      !destination.updatedAt.isEqual(source.updatedAt)) {
    throw new Error("Equal-revision social edges diverge.");
  }
  return false;
}

function sameTimestamp(
  left: Timestamp | null,
  right: Timestamp | null,
): boolean {
  if (left === null || right === null) return left === right;
  return left.isEqual(right);
}
