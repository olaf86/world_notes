/* eslint-disable require-jsdoc */

import assert from "node:assert/strict";
import test from "node:test";

import {
  DocumentSnapshot,
  Timestamp,
} from "firebase-admin/firestore";

import {
  nextSocialEdgeProjection,
  parseSocialEdgeProjection,
  SET_USER_FOLLOW_OPERATION,
  socialCounterDeltas,
  socialEdgeId,
  socialEdgeReplicationHandler,
} from "../src/socialEdgeReplication";

const NOW = Timestamp.fromMillis(2_000);
const EARLIER = Timestamp.fromMillis(1_000);

test("social edge IDs are stable and delimiter-safe", () => {
  assert.equal(socialEdgeId("alice", "bob"), "YWxpY2U.Ym9i");
  assert.notEqual(
    socialEdgeId("a_b", "c"),
    socialEdgeId("a", "b_c"),
  );
  assert.throws(() => socialEdgeId("alice", "alice"));
});

test("social projection parses active state and inactive tombstones", () => {
  const edgeId = socialEdgeId("alice", "bob");
  const active = parseSocialEdgeProjection(snapshot({
    followerUid: "alice",
    followeeUid: "bob",
    following: true,
    revision: 3,
    createdAt: EARLIER,
    updatedAt: NOW,
  }), edgeId);
  const inactive = parseSocialEdgeProjection(snapshot({
    ...active,
    following: false,
    revision: 4,
  }), edgeId);

  assert.equal(active.following, true);
  assert.equal(inactive.following, false);
  assert.throws(
    () => parseSocialEdgeProjection(snapshot({...active, extra: true})),
    /fields are invalid/,
  );
  assert.throws(
    () => parseSocialEdgeProjection(snapshot({...active, createdAt: null})),
    /requires createdAt/,
  );
});

test("next social state refreshes followedAt only on a new follow", () => {
  const first = nextSocialEdgeProjection(
    "alice",
    "bob",
    true,
    1,
    EARLIER,
  );
  const unchanged = nextSocialEdgeProjection(
    "alice",
    "bob",
    true,
    2,
    NOW,
    first,
  );
  const removed = nextSocialEdgeProjection(
    "alice",
    "bob",
    false,
    3,
    NOW,
    unchanged,
  );
  const followedAgain = nextSocialEdgeProjection(
    "alice",
    "bob",
    true,
    4,
    Timestamp.fromMillis(3_000),
    removed,
  );

  assert.equal(first.createdAt, EARLIER);
  assert.equal(unchanged.createdAt, EARLIER);
  assert.equal(removed.createdAt, EARLIER);
  assert.equal(followedAgain.createdAt?.toMillis(), 3_000);
});

test("social counter deltas follow the directed edge transition", () => {
  assert.deepEqual(socialCounterDeltas(false, true), {
    followerFollowingCount: 1,
    followeeFollowerCount: 1,
  });
  assert.deepEqual(socialCounterDeltas(true, false), {
    followerFollowingCount: -1,
    followeeFollowerCount: -1,
  });
  assert.deepEqual(socialCounterDeltas(true, true), {
    followerFollowingCount: 0,
    followeeFollowerCount: 0,
  });
  assert.equal(
    socialEdgeReplicationHandler.operationType,
    SET_USER_FOLLOW_OPERATION,
  );
});

function snapshot(
  data: Readonly<Record<string, unknown>>,
): DocumentSnapshot {
  return {
    exists: true,
    data: () => data,
    get: (field: string) => data[field],
  } as unknown as DocumentSnapshot;
}
