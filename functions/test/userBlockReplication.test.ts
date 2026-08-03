/* eslint-disable require-jsdoc */

import assert from "node:assert/strict";
import test from "node:test";

import {
  DocumentSnapshot,
  Timestamp,
} from "firebase-admin/firestore";

import {
  isActiveUserBlock,
  parseUserBlockEntityId,
  parseUserBlockProjection,
  SET_USER_BLOCK_OPERATION,
  userBlockEntityId,
  userBlockReplicationHandler,
} from "../src/userBlockReplication";

test("block entity IDs reversibly bind one directional user pair", () => {
  const entityId = userBlockEntityId("test-blocker", "test-blocked");

  assert.deepEqual(parseUserBlockEntityId(entityId), {
    blockerUid: "test-blocker",
    blockedUid: "test-blocked",
  });
  assert.throws(
    () => userBlockEntityId("same-user", "same-user"),
    /cannot target its owner/,
  );
  assert.throws(
    () => parseUserBlockEntityId(`${entityId}.extra`),
    /invalid/,
  );
});

test("block projection parser enforces active and tombstone invariants", () => {
  const updatedAt = Timestamp.fromMillis(1_000);
  const activeData = {
    blockedUid: "test-blocked",
    isBlocked: true,
    revision: 3,
    authorityWorld: "asia",
    updatedAt,
    expireAt: null,
  };
  const active = blockSnapshot(activeData);
  const tombstone = blockSnapshot({
    blockedUid: "test-blocked",
    isBlocked: false,
    revision: 4,
    authorityWorld: "asia",
    updatedAt,
    expireAt: Timestamp.fromMillis(2_000),
  });

  assert.equal(
    parseUserBlockProjection(active, "test-blocker", "test-blocked").revision,
    3,
  );
  assert.equal(
    isActiveUserBlock(active, "test-blocker", "test-blocked"),
    true,
  );
  assert.equal(
    isActiveUserBlock(tombstone, "test-blocker", "test-blocked"),
    false,
  );
  assert.throws(
    () => parseUserBlockProjection(
      blockSnapshot({...activeData, expireAt: updatedAt}),
      "test-blocker",
      "test-blocked",
    ),
    /cannot expire/,
  );
});

test("block replication registers its explicit global operation type", () => {
  assert.equal(
    userBlockReplicationHandler.operationType,
    SET_USER_BLOCK_OPERATION,
  );
});

function blockSnapshot(
  data: Record<string, unknown>,
): DocumentSnapshot {
  return {
    exists: true,
    data: () => data,
  } as unknown as DocumentSnapshot;
}
