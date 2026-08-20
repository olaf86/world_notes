/* eslint-disable require-jsdoc */

import assert from "node:assert/strict";
import test from "node:test";

import {
  Firestore,
  Timestamp,
  Transaction,
} from "firebase-admin/firestore";

import {parseCleanupJob} from "../src/cleanupJobs";
import {
  enqueueHiddenMessageRetention,
  hiddenMessageRetentionHandler,
  messageRetentionEvidenceId,
  PURGE_HIDDEN_MESSAGE_JOB,
} from "../src/messageModerationRetention";
import {HIDDEN_CONTENT_RETENTION_MILLIS} from "../src/moderationRetention";

const HIDDEN_AT = Timestamp.fromMillis(1_753_000_000_000);

test("hidden message retention starts at one exact 30-day deadline", () => {
  const writes: Array<{
    path: string;
    data: Record<string, unknown>;
  }> = [];
  const firestore = fakeFirestore();
  const transaction = {
    create(reference: {path: string}, data: Record<string, unknown>) {
      writes.push({path: reference.path, data});
    },
  } as unknown as Transaction;

  enqueueHiddenMessageRetention(transaction, firestore, {
    world: "asia",
    placeId: "place-1",
    messageId: "message-1",
    hiddenAt: HIDDEN_AT,
  });

  assert.equal(writes.length, 2);
  const jobWrite = writes.find(({path}) => path.includes("cleanupQueues/"));
  const targetWrite = writes.find(({path}) =>
    path.startsWith("moderationRetentionTargets/"));
  assert.ok(jobWrite);
  assert.ok(targetWrite);
  const job = parseCleanupJob(jobWrite.data, "asia");
  assert.equal(job.jobType, PURGE_HIDDEN_MESSAGE_JOB);
  assert.equal(job.entityId, "message-1");
  assert.equal(job.revision, HIDDEN_AT.toMillis());
  assert.equal(
    job.nextAttemptAt?.toMillis(),
    HIDDEN_AT.toMillis() + HIDDEN_CONTENT_RETENTION_MILLIS,
  );
  assert.equal(
    targetWrite.data.targetPath,
    "places/place-1/messages/message-1",
  );
});

test("message retention evidence has one path-safe target identity", () => {
  const first = messageRetentionEvidenceId("place-1", "message-1");

  assert.match(first, /^messageRetention_[0-9a-f]{64}$/);
  assert.equal(messageRetentionEvidenceId("place-1", "message-1"), first);
  assert.notEqual(messageRetentionEvidenceId("place-2", "message-1"), first);
});

test("hidden message retention owns its cleanup job type", () => {
  assert.equal(hiddenMessageRetentionHandler.queue, "firestore");
  assert.equal(
    hiddenMessageRetentionHandler.jobType,
    PURGE_HIDDEN_MESSAGE_JOB,
  );
});

function fakeFirestore(): Firestore {
  const reference = (path: string) => ({path});
  return {
    doc: (path: string) => reference(path),
    collection: (path: string) => ({
      doc: (id: string) => reference(`${path}/${id}`),
    }),
  } as unknown as Firestore;
}
