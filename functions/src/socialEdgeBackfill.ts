/* eslint-disable require-jsdoc, valid-jsdoc */

import {Timestamp} from "firebase-admin/firestore";

import {derivedGlobalOperationId} from "./globalOperations";
import type {SocialEdgeProjection} from "./socialEdgeReplication";

const SOCIAL_BACKFILL_OPERATION_ROOT =
  "00000000-0000-7000-8000-000000000000";

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
