/* eslint-disable require-jsdoc */

import assert from "node:assert/strict";
import test from "node:test";

import {Timestamp} from "firebase-admin/firestore";

import {
  likedMessagesData,
  parseLikedMessages,
  updatedMessageIds,
} from "../src/likedMessages";

const NOW = Timestamp.fromMillis(1_753_000_000_000);

test("normalizes one liked-messages document deterministically", () => {
  const likedMessages = likedMessagesData({
    userId: "user-1",
    placeId: "place-1",
    messageIds: ["message-b", "message-a"],
    updatedAt: NOW,
  });

  assert.deepEqual(likedMessages.messageIds, ["message-a", "message-b"]);
  assert.equal(
    parseLikedMessages({...likedMessages}, {
      userId: "user-1",
      placeId: "place-1",
    }).updatedAt,
    NOW,
  );
});

test("adds and removes one desired message Like idempotently", () => {
  assert.deepEqual(
    updatedMessageIds(["message-a"], "message-b", true),
    ["message-a", "message-b"],
  );
  assert.deepEqual(
    updatedMessageIds(["message-a"], "message-a", true),
    ["message-a"],
  );
  assert.deepEqual(
    updatedMessageIds(["message-a"], "message-a", false),
    [],
  );
});

test("rejects duplicate, oversized, and route-mismatched documents", () => {
  assert.throws(() => likedMessagesData({
    userId: "user-1",
    placeId: "place-1",
    messageIds: ["message-a", "message-a"],
    updatedAt: NOW,
  }));
  assert.throws(() => likedMessagesData({
    userId: "user-1",
    placeId: "place-1",
    messageIds: Array.from({length: 10_001}, (_, index) => `m-${index}`),
    updatedAt: NOW,
  }));
  assert.throws(() => likedMessagesData({
    userId: "user-1",
    placeId: "place-1",
    messageIds: Array.from(
      {length: 2_000},
      (_, index) => `${index}-${"x".repeat(250)}`,
    ),
    updatedAt: NOW,
  }));
  assert.throws(() => parseLikedMessages({
    userId: "user-2",
    placeId: "place-1",
    messageIds: [],
    updatedAt: NOW,
  }, {userId: "user-1", placeId: "place-1"}));
});
