/* eslint-disable require-jsdoc */

import assert from "node:assert/strict";
import test from "node:test";

import {Timestamp} from "firebase-admin/firestore";

import {
  accountAuthorityData,
  accountBackfillOperationId,
  publicProfileMirrorData,
  shouldWriteCanonicalFields,
  shouldWriteHomeMarker,
  shouldWritePublicProfile,
  shouldWriteProjection,
} from "../src/accountBackfill";
import {
  parseAccountBackfillArgs,
  safeAccountBackfillError,
} from "../src/scripts/backfillAccounts";

const CREATED_AT = Timestamp.fromMillis(1_700_000_000_000);
const NOW = Timestamp.fromMillis(1_800_000_000_000);

test("builds canonical Asia updates from legacy account fields", () => {
  const account = accountAuthorityData({
    identity: {
      uid: "user-1",
      displayName: "Auth name",
      email: "user@example.com",
      photoUrl: null,
      createdAt: CREATED_AT,
    },
    now: NOW,
    activeNoteCount: 2,
    home: null,
    user: {displayName: "Legacy name", isPremium: true},
    profile: {
      displayName: "Legacy name",
      photoUrl: null,
      photoVersion: 1,
      followerCount: 3,
      followingCount: 4,
      createdAt: CREATED_AT,
      updatedAt: CREATED_AT,
    },
    entitlement: null,
    usage: null,
    safety: null,
  });

  assert.equal(account.home.world, "asia");
  assert.equal(account.user.isPremium, undefined);
  assert.equal(account.profile.revision, 1);
  assert.equal(account.profile.followerCount, 3);
  assert.equal(account.entitlement.isPremium, true);
  assert.equal(account.usage.activeNoteCount, 2);
  assert.equal(account.safety.authorityWorld, "asia");
});

test("derives stable and purpose-bound operation IDs", () => {
  assert.equal(
    accountBackfillOperationId("user-1", "profile"),
    accountBackfillOperationId("user-1", "profile"),
  );
  assert.notEqual(
    accountBackfillOperationId("user-1", "profile"),
    accountBackfillOperationId("user-1", "entitlement"),
  );
  assert.notEqual(
    accountBackfillOperationId("user-1", "profile"),
    accountBackfillOperationId("user-2", "profile"),
  );
});

test("writes only missing or older projections", () => {
  const source = {revision: 2, value: "current"};
  assert.equal(shouldWriteProjection(source, null), true);
  assert.equal(
    shouldWriteProjection(source, {revision: 1, value: "old"}),
    true,
  );
  assert.equal(
    shouldWriteProjection(
      source,
      {revision: 2, value: "current", legacy: true},
    ),
    false,
  );
  assert.throws(() => shouldWriteProjection(
    source,
    {revision: 3, value: "future"},
  ));
  assert.throws(() => shouldWriteProjection(
    source,
    {revision: 2, value: "different"},
  ));
});

test("canonical updates ignore preserved destination-only fields", () => {
  assert.equal(shouldWriteCanonicalFields(
    {value: "current"},
    {value: "current", legacy: true},
  ), false);
  assert.equal(shouldWriteCanonicalFields(
    {value: "current"},
    {legacy: true},
  ), true);
});

test("replicates public identity without replacing social counters", () => {
  const source = {
    displayName: "Name",
    photoUrl: null,
    photoVersion: 1,
    revision: 2,
    followerCount: 4,
    followingCount: 5,
    createdAt: CREATED_AT,
    updatedAt: NOW,
  };
  const destination = {
    ...source,
    followerCount: 9,
    followingCount: 10,
  };
  assert.equal(shouldWritePublicProfile(source, destination), false);
  assert.deepEqual(publicProfileMirrorData(source), {
    displayName: "Name",
    photoUrl: null,
    photoVersion: 1,
    revision: 2,
    createdAt: CREATED_AT,
    updatedAt: NOW,
  });
  assert.throws(() => shouldWritePublicProfile(source, {
    ...destination,
    displayName: "Different",
  }));
});

test("copies only missing or incomplete compatible home markers", () => {
  const source = {world: "asia", epoch: 1, createdAt: CREATED_AT};
  assert.equal(shouldWriteHomeMarker(source, null), true);
  assert.equal(shouldWriteHomeMarker(source, {...source}), false);
  assert.equal(
    shouldWriteHomeMarker(source, {...source, legacy: true}),
    false,
  );
  assert.equal(
    shouldWriteHomeMarker(source, {world: "asia", epoch: 1}),
    true,
  );
  assert.throws(() => shouldWriteHomeMarker(
    source,
    {world: "europe", epoch: 1},
  ));
});

test("account backfill defaults to dry-run with explicit projects", () => {
  const parsed = parseAccountBackfillArgs([
    "--source-project", "world-notes-prod",
    "--target-project", "world-notes-prod",
    "--checkpoint", "/tmp/checkpoint.json",
    "--report", "/tmp/report.json",
  ]);
  assert.equal(parsed.mode, "dry-run");
  assert.equal(parsed.pageSize, 100);
});

test("account backfill apply requires an exact project confirmation", () => {
  const base = [
    "--source-project", "world-notes-prod",
    "--target-project", "world-notes-prod",
    "--checkpoint", "/tmp/checkpoint.json",
    "--report", "/tmp/report.json",
    "--apply",
  ];
  assert.throws(() => parseAccountBackfillArgs(base));
  assert.equal(parseAccountBackfillArgs([
    ...base,
    "--confirm-project", "world-notes-prod",
  ]).mode, "apply");
  assert.throws(() => parseAccountBackfillArgs([
    ...base,
    "--confirm-project", "another-prod",
  ]));
});

test("account backfill refuses cross-project and unbounded pages", () => {
  const base = [
    "--source-project", "world-notes-prod",
    "--target-project", "world-notes-other",
    "--checkpoint", "/tmp/checkpoint.json",
    "--report", "/tmp/report.json",
  ];
  assert.throws(() => parseAccountBackfillArgs(base));
  assert.throws(() => parseAccountBackfillArgs([
    ...base.slice(0, 4),
    "--target-project", "world-notes-prod",
    ...base.slice(4),
    "--page-size", "201",
  ]));
});

test("account backfill diagnostics redact identity-bearing values", () => {
  const error = Object.assign(new Error(
    "User abcdefghijklmnopqrstuvwxyz12 user@example.com " +
      "at https://example.com/private?token=secret",
  ), {code: 7});
  assert.deepEqual(safeAccountBackfillError(error), {
    errorType: "Error",
    errorCode: 7,
    message: "User [identifier] [email] at [url]",
  });
});
