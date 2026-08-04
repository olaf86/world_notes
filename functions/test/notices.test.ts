/* eslint-disable require-jsdoc */

import assert from "node:assert/strict";
import test from "node:test";

import {
  Firestore,
  Timestamp,
  Transaction,
} from "firebase-admin/firestore";

import {parseNotificationOutbox} from "../src/notificationOutbox";
import {
  enqueueUserNoticeNotification,
  USER_NOTICE_NOTIFICATION_EVENT,
  userNoticeNotificationHandler,
} from "../src/notices";

const CREATED_AT = Timestamp.fromMillis(1_000);

test("notice push is owned by home and retains its source world", () => {
  const writes: Array<{ref: {path: string}; data: unknown}> = [];
  const eventId = enqueueUserNoticeNotification(
    transactionRecording(writes),
    firestoreStub(),
    {
      homeWorld: "europe",
      sourceWorld: "northAmerica",
      uid: "test-recipient",
      noticeId: "test-notice",
      createdAt: CREATED_AT,
    },
  );

  assert.equal(writes.length, 1);
  assert.equal(writes[0].ref.path, `notificationOutbox/${eventId}`);
  const event = parseNotificationOutbox(
    writes[0].data,
    eventId,
    "europe",
  );
  assert.equal(event.eventType, USER_NOTICE_NOTIFICATION_EVENT);
  assert.equal(event.ownerWorld, "europe");
  assert.equal(event.sourceWorld, "northAmerica");
  assert.equal(event.entityType, "notice");
  assert.equal(event.entityId, "test-notice");
  assert.equal(
    event.sourcePath,
    "users/test-recipient/notices/test-notice",
  );
  assert.deepEqual(event.recipientUids, ["test-recipient"]);
});

test("notice outbox handler owns its explicit event type", () => {
  assert.equal(
    userNoticeNotificationHandler.eventType,
    USER_NOTICE_NOTIFICATION_EVENT,
  );
});

function transactionRecording(
  writes: Array<{ref: {path: string}; data: unknown}>,
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
