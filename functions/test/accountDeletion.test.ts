/* eslint-disable require-jsdoc */

import assert from "node:assert/strict";
import test from "node:test";

import {
  accountDeletionFirestoreHandler,
  accountDeletionId,
  accountDeletionStorageHandler,
  deleteAccount,
  DELETE_ACCOUNT_DATA_JOB,
  DELETE_ACCOUNT_STORAGE_JOB,
  requireRecentAuthentication,
} from "../src/accountDeletion";

test("account deletion uses a deterministic opaque identity", () => {
  const uid = "firebase-user-123";
  const first = accountDeletionId(uid);

  assert.equal(accountDeletionId(uid), first);
  assert.match(first, /^[0-9a-f]{64}$/);
  assert.equal(first.includes(uid), false);
  assert.notEqual(accountDeletionId("another-user"), first);
});

test("account deletion requires recent authentication", () => {
  const now = 10_000;

  assert.doesNotThrow(() => requireRecentAuthentication(now, now));
  assert.doesNotThrow(() => requireRecentAuthentication(now - 300, now));
  assert.throws(
    () => requireRecentAuthentication(now - 301, now),
    /Recent authentication is required/,
  );
  assert.throws(
    () => requireRecentAuthentication(now + 1, now),
    /Recent authentication is required/,
  );
  assert.throws(
    () => requireRecentAuthentication(undefined, now),
    /Recent authentication is required/,
  );
});

test("account cleanup handlers explicitly own separate queues", () => {
  assert.equal(accountDeletionFirestoreHandler.queue, "firestore");
  assert.equal(
    accountDeletionFirestoreHandler.jobType,
    DELETE_ACCOUNT_DATA_JOB,
  );
  assert.equal(accountDeletionStorageHandler.queue, "storage");
  assert.equal(
    accountDeletionStorageHandler.jobType,
    DELETE_ACCOUNT_STORAGE_JOB,
  );
});

test("account deletion callable deploys to every active region", () => {
  const endpoint = (deleteAccount as unknown as {
    readonly __endpoint: {readonly region?: readonly string[]};
  }).__endpoint;

  assert.deepEqual(
    [...(endpoint.region ?? [])].sort(),
    ["asia-northeast1", "europe-west1", "us-central1"],
  );
});
