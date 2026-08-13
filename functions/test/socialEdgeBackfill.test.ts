/* eslint-disable require-jsdoc */

import assert from "node:assert/strict";
import test from "node:test";

import {Timestamp} from "firebase-admin/firestore";

import {
  shouldWriteSocialEdge,
  socialEdgeBackfillOperationId,
} from "../src/socialEdgeBackfill";
import {
  parseSocialEdgeBackfillArgs,
} from "../src/scripts/backfillSocialEdges";

const NOW = Timestamp.fromMillis(1_800_000_000_000);
const EDGE = Object.freeze({
  followerUid: "user-1",
  followeeUid: "user-2",
  following: true,
  revision: 2,
  createdAt: NOW,
  updatedAt: NOW,
});

test("social edge backfill operation IDs are stable and edge-bound", () => {
  assert.equal(
    socialEdgeBackfillOperationId("edge-1"),
    socialEdgeBackfillOperationId("edge-1"),
  );
  assert.notEqual(
    socialEdgeBackfillOperationId("edge-1"),
    socialEdgeBackfillOperationId("edge-2"),
  );
});

test("social edge backfill accepts only missing or older destinations", () => {
  assert.equal(shouldWriteSocialEdge(EDGE, null), true);
  assert.equal(shouldWriteSocialEdge(EDGE, {...EDGE, revision: 1}), true);
  assert.equal(shouldWriteSocialEdge(EDGE, {...EDGE}), false);
  assert.throws(() => shouldWriteSocialEdge(
    EDGE,
    {...EDGE, revision: 3},
  ));
  assert.throws(() => shouldWriteSocialEdge(
    EDGE,
    {...EDGE, following: false},
  ));
});

test("social edge apply requires an exact target confirmation", () => {
  const base = [
    "--source-project", "world-notes-prod",
    "--target-project", "world-notes-prod",
    "--checkpoint", "/tmp/social-checkpoint.json",
    "--report", "/tmp/social-report.json",
  ];
  assert.equal(parseSocialEdgeBackfillArgs(base).mode, "dry-run");
  assert.throws(() => parseSocialEdgeBackfillArgs([...base, "--apply"]));
  assert.equal(parseSocialEdgeBackfillArgs([
    ...base,
    "--apply",
    "--confirm-project", "world-notes-prod",
  ]).mode, "apply");
});
