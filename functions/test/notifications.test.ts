/* eslint-disable require-jsdoc */

import assert from "node:assert/strict";
import test from "node:test";

import {
  DocumentSnapshot,
  Firestore,
  Timestamp,
  Transaction,
} from "firebase-admin/firestore";

import {parseNotificationOutbox} from "../src/notificationOutbox";
import {
  enqueueMyNotesMessageNotification,
  MY_NOTES_MESSAGE_NOTIFICATION_EVENT,
  myNotesMessageNotificationHandler,
} from "../src/notifications";

const MESSAGE_ID = "00000000-0000-7000-8000-000000000001";
const CREATED_AT = Timestamp.fromMillis(1_000);

test("message publication snapshots one deterministic outbox event", () => {
  const first = notificationWrite([
    "test-sender",
    "test-delegate",
    "test-delegate",
  ]);
  const second = notificationWrite([
    "test-sender",
    "test-delegate",
  ]);

  assert.equal(first.eventId, second.eventId);
  assert.equal(first.path, `notificationOutbox/${first.eventId}`);
  const event = parseNotificationOutbox(
    first.data,
    first.eventId as string,
    "europe",
  );
  assert.equal(event.eventType, MY_NOTES_MESSAGE_NOTIFICATION_EVENT);
  assert.equal(event.ownerWorld, "europe");
  assert.equal(event.sourceWorld, "europe");
  assert.equal(event.entityId, MESSAGE_ID);
  assert.equal(
    event.sourcePath,
    `places/test-place/messages/${MESSAGE_ID}`,
  );
  assert.deepEqual(event.recipientUids, ["test-creator", "test-delegate"]);
  assert.equal(
    event.expiresAt.toMillis() - event.createdAt.toMillis(),
    24 * 60 * 60 * 1000,
  );
});

test("message publication omits an event with no other maintainer", () => {
  const writes: unknown[] = [];
  const eventId = enqueueMyNotesMessageNotification(
    transactionRecording(writes),
    firestoreStub(),
    {
      sourceWorld: "asia",
      place: placeSnapshot("test-sender"),
      administratorUids: [],
      messageId: MESSAGE_ID,
      senderId: "test-sender",
      createdAt: CREATED_AT,
    },
  );

  assert.equal(eventId, null);
  assert.deepEqual(writes, []);
});

test("message outbox handler owns its explicit event type", () => {
  assert.equal(
    myNotesMessageNotificationHandler.eventType,
    MY_NOTES_MESSAGE_NOTIFICATION_EVENT,
  );
});

function notificationWrite(administratorUids: string[]) {
  const writes: Array<{ref: {path: string}; data: unknown}> = [];
  const eventId = enqueueMyNotesMessageNotification(
    transactionRecording(writes),
    firestoreStub(),
    {
      sourceWorld: "europe",
      place: placeSnapshot("test-creator"),
      administratorUids,
      messageId: MESSAGE_ID,
      senderId: "test-sender",
      createdAt: CREATED_AT,
    },
  );
  assert.equal(writes.length, 1);
  return {
    eventId,
    path: writes[0].ref.path,
    data: writes[0].data,
  };
}

function transactionRecording(
  writes: Array<{ref: {path: string}; data: unknown}> | unknown[],
): Transaction {
  const transaction = {
    create: (ref: {path: string}, data: unknown) => {
      writes.push({ref, data});
      return transaction;
    },
  };
  return transaction as unknown as Transaction;
}

function firestoreStub(): Firestore {
  return {
    collection: (collection: string) => ({
      doc: (id: string) => ({id, path: `${collection}/${id}`}),
    }),
  } as unknown as Firestore;
}

function placeSnapshot(creatorUid: string): DocumentSnapshot {
  const fields: Record<string, unknown> = {
    createdByUserId: creatorUid,
  };
  return {
    id: "test-place",
    get: (field: string) => fields[field],
  } as unknown as DocumentSnapshot;
}
