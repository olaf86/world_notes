/* eslint-disable require-jsdoc */

import assert from "node:assert/strict";
import test from "node:test";

import {
  DocumentSnapshot,
  Timestamp,
} from "firebase-admin/firestore";

import {
  parsePublicProfileProjection,
  parseUserEntitlementProjection,
  publicProfileReplicationHandler,
  SET_USER_ENTITLEMENT_OPERATION,
  shouldApplyEntitlementSource,
  UPDATE_PUBLIC_PROFILE_OPERATION,
  userEntitlementReplicationHandler,
} from "../src/profileEntitlementReplication";

const NOW = Timestamp.fromMillis(1_000);

test("public profile projection requires revisioned bounded identity", () => {
  const profile = parsePublicProfileProjection(snapshot({
    displayName: "Alice",
    photoUrl: null,
    photoVersion: 2,
    revision: 3,
    followerCount: 4,
    followingCount: 5,
    createdAt: NOW,
    updatedAt: NOW,
  }));

  assert.equal(profile.displayName, "Alice");
  assert.equal(profile.revision, 3);
  assert.throws(
    () => parsePublicProfileProjection(snapshot({...profile, revision: 0})),
    /revision is invalid/,
  );
  assert.throws(
    () => parsePublicProfileProjection(snapshot({
      ...profile,
      displayName: ` ${profile.displayName}`,
    })),
    /displayName is invalid/,
  );
});

test("entitlement source timestamps reject a delayed old response", () => {
  const older = Timestamp.fromMillis(1_000);
  const newer = Timestamp.fromMillis(2_000);

  assert.equal(shouldApplyEntitlementSource(null, null), true);
  assert.equal(shouldApplyEntitlementSource(null, newer), true);
  assert.equal(shouldApplyEntitlementSource(newer, older), false);
  assert.equal(shouldApplyEntitlementSource(newer, newer), true);
  assert.equal(shouldApplyEntitlementSource(newer, null), false);
});

test("entitlement projection is a small revisioned server mirror", () => {
  const entitlement = parseUserEntitlementProjection(snapshot({
    isPremium: true,
    revision: 7,
    sourceCheckedAt: NOW,
    updatedAt: NOW,
  }));

  assert.deepEqual(entitlement, {
    isPremium: true,
    revision: 7,
    sourceCheckedAt: NOW,
    updatedAt: NOW,
  });
  assert.throws(
    () => parseUserEntitlementProjection(snapshot({
      isPremium: "true",
      revision: 7,
      sourceCheckedAt: NOW,
      updatedAt: NOW,
    })),
    /isPremium is invalid/,
  );
});

test("replication registry types stay aligned with their projections", () => {
  assert.equal(
    publicProfileReplicationHandler.operationType,
    UPDATE_PUBLIC_PROFILE_OPERATION,
  );
  assert.equal(
    userEntitlementReplicationHandler.operationType,
    SET_USER_ENTITLEMENT_OPERATION,
  );
});

function snapshot(
  data: Readonly<Record<string, unknown>>,
): DocumentSnapshot {
  return {
    exists: true,
    get: (field: string) => data[field],
  } as unknown as DocumentSnapshot;
}
