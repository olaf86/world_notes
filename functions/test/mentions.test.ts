/* eslint-disable require-jsdoc */

import assert from "node:assert/strict";
import test from "node:test";

import {
  DocumentSnapshot,
  Firestore,
  Timestamp,
  Transaction,
} from "firebase-admin/firestore";

import {
  enqueueMessageMentionNotification,
  mentionSearchBigrams,
  mentionUserIdsFromMessage,
  MESSAGE_MENTION_NOTIFICATION_EVENT,
  messageMentionNotificationHandler,
  normalizeMentionSearchText,
  parseMentionUserIds,
} from "../src/mentions";
import {parseNotificationOutbox} from "../src/notificationOutbox";

const MESSAGE_ID = "00000000-0000-7000-8000-000000000030";
const CREATED_AT = Timestamp.fromMillis(1_000);

test("mention search normalizes width, case, kana, and whitespace", () => {
  assert.equal(normalizeMentionSearchText("  ＡＢＣ　カナ  "), "abc かな");
  assert.deepEqual(mentionSearchBigrams("かなかな"), ["かな", "なか"]);
});

test("recipients are distinct, bounded, and cannot include sender", () => {
  assert.deepEqual(
    parseMentionUserIds(["recipient-1", "recipient-2"], "sender"),
    ["recipient-1", "recipient-2"],
  );
  assert.throws(
    () => parseMentionUserIds(["recipient", "recipient"], "sender"),
    /no longer available/,
  );
  assert.throws(
    () => parseMentionUserIds(["sender"], "sender"),
    /no longer available/,
  );
  assert.throws(
    () => parseMentionUserIds(["a", "b", "c", "d"], "sender"),
    /no longer available/,
  );
});

test("malformed mention snapshots are rejected as a whole", () => {
  assert.deepEqual(
    mentionUserIdsFromMessage(messageSnapshot([
      {userId: "recipient-1", displayName: "A"},
      {userId: "recipient-2", displayName: "B"},
    ])),
    ["recipient-1", "recipient-2"],
  );
  assert.deepEqual(
    mentionUserIdsFromMessage(messageSnapshot([
      {userId: "recipient", displayName: "A"},
      {userId: "recipient", displayName: "A"},
    ])),
    [],
  );
  assert.deepEqual(
    mentionUserIdsFromMessage(messageSnapshot([
      {userId: "recipient", displayName: "A"},
      {displayName: "missing id"},
    ])),
    [],
  );
});

test("message publication snapshots one deterministic mention event", () => {
  const first = mentionNotificationWrite(["recipient-2", "recipient-1"]);
  const second = mentionNotificationWrite(["recipient-1", "recipient-2"]);

  assert.equal(first.eventId, second.eventId);
  const event = parseNotificationOutbox(first.data, first.eventId, "asia");
  assert.equal(event.eventType, MESSAGE_MENTION_NOTIFICATION_EVENT);
  assert.equal(event.entityId, MESSAGE_ID);
  assert.equal(event.sourcePath, `places/place-1/messages/${MESSAGE_ID}`);
  assert.deepEqual(event.recipientUids, ["recipient-1", "recipient-2"]);
  assert.equal(
    event.expiresAt.toMillis() - event.createdAt.toMillis(),
    24 * 60 * 60 * 1_000,
  );
});

test("mention notification handler owns its explicit event type", () => {
  assert.equal(
    messageMentionNotificationHandler.eventType,
    MESSAGE_MENTION_NOTIFICATION_EVENT,
  );
});

function mentionNotificationWrite(recipientUids: string[]) {
  const writes: Array<{ref: {path: string}; data: unknown}> = [];
  const eventId = enqueueMessageMentionNotification(
    transactionRecording(writes),
    firestoreStub(),
    {
      sourceWorld: "asia",
      place: placeSnapshot(),
      message: messageSnapshot(recipientUids.map((userId) => ({
        userId,
        displayName: userId,
      }))),
      createdAt: CREATED_AT,
    },
  );
  assert.equal(typeof eventId, "string");
  assert.equal(writes.length, 1);
  return {eventId: eventId as string, data: writes[0].data};
}

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

function placeSnapshot(): DocumentSnapshot {
  return {id: "place-1"} as unknown as DocumentSnapshot;
}

function messageSnapshot(mentions: unknown[]): DocumentSnapshot {
  const fields: Record<string, unknown> = {
    userId: "sender",
    mentions,
  };
  return {
    id: MESSAGE_ID,
    get: (field: string) => fields[field],
  } as unknown as DocumentSnapshot;
}
