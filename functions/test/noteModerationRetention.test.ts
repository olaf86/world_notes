/* eslint-disable require-jsdoc */

import assert from "node:assert/strict";
import test from "node:test";

import {
  Firestore,
  Timestamp,
  Transaction,
} from "firebase-admin/firestore";

import {parseCleanupJob} from "../src/cleanupJobs";
import {HIDDEN_CONTENT_RETENTION_MILLIS} from "../src/moderationRetention";
import {
  enqueueHiddenNoteRetention,
  hiddenNoteRetentionHandler,
  noteRetentionAuditId,
  PURGE_HIDDEN_NOTE_JOB,
} from "../src/noteModerationRetention";

const HIDDEN_AT = Timestamp.fromMillis(1_753_000_000_000);

test("hidden note retention starts at one exact 30-day deadline", () => {
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

  enqueueHiddenNoteRetention(transaction, firestore, {
    world: "asia",
    placeId: "place-1",
    hiddenAt: HIDDEN_AT,
  });

  assert.equal(writes.length, 2);
  const jobWrite = writes.find(({path}) => path.includes("cleanupQueues/"));
  const targetWrite = writes.find(({path}) =>
    path.startsWith("noteModerationRetentionTargets/"));
  assert.ok(jobWrite);
  assert.ok(targetWrite);
  const job = parseCleanupJob(jobWrite.data, "asia");
  assert.equal(job.jobType, PURGE_HIDDEN_NOTE_JOB);
  assert.equal(job.entityId, "place-1");
  assert.equal(job.revision, HIDDEN_AT.toMillis());
  assert.equal(
    job.nextAttemptAt?.toMillis(),
    HIDDEN_AT.toMillis() + HIDDEN_CONTENT_RETENTION_MILLIS,
  );
  assert.equal(targetWrite.data.targetPath, "places/place-1");
});

test("note retention evidence has one path-safe target identity", () => {
  const first = noteRetentionAuditId("place-1");

  assert.match(first, /^noteRetention_[0-9a-f]{64}$/);
  assert.equal(noteRetentionAuditId("place-1"), first);
  assert.notEqual(noteRetentionAuditId("place-2"), first);
});

test("hidden note retention owns its cleanup job type", () => {
  assert.equal(hiddenNoteRetentionHandler.queue, "firestore");
  assert.equal(hiddenNoteRetentionHandler.jobType, PURGE_HIDDEN_NOTE_JOB);
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
