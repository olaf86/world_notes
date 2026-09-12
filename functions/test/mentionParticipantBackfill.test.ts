/* eslint-disable require-jsdoc */

import assert from "node:assert/strict";
import test from "node:test";

import {DocumentSnapshot, Timestamp} from "firebase-admin/firestore";

import {
  mentionParticipantSource,
  parseMentionParticipantBackfillArgs,
} from "../src/scripts/backfillMentionParticipants";

test("mention participant backfill is dry-run unless exactly confirmed", () => {
  const args = parseMentionParticipantBackfillArgs([
    "--project", "world-notes-test",
    "--world", "asia",
  ]);
  assert.equal(args.apply, false);
  assert.equal(args.pageSize, 100);

  assert.throws(() => parseMentionParticipantBackfillArgs([
    "--project", "world-notes-test",
    "--world", "asia",
    "--apply",
  ]), /exact --confirm-project/);
  assert.equal(parseMentionParticipantBackfillArgs([
    "--project", "world-notes-test",
    "--world", "asia",
    "--apply",
    "--confirm-project", "world-notes-test",
  ]).apply, true);
});

test("participant backfill accepts only publicly visible messages", () => {
  const publishAt = Timestamp.fromMillis(1_000);
  const source = mentionParticipantSource(messageSnapshot({
    userId: "alice",
    userName: "Alice",
    userPhotoUrl: null,
    publishAt,
    isPubliclyVisible: true,
    isVisible: true,
    isDeleted: false,
    moderationAction: "allow",
  }));

  assert.equal(source?.placeId, "place-1");
  assert.equal(source?.userId, "alice");
  assert.equal(source?.publishAt, publishAt);
  assert.equal(mentionParticipantSource(messageSnapshot({
    userId: "alice",
    userName: "Alice",
    publishAt,
    isPubliclyVisible: false,
    isVisible: true,
    moderationAction: "allow",
  })), null);
});

function messageSnapshot(fields: Record<string, unknown>): DocumentSnapshot {
  return {
    exists: true,
    ref: {path: "places/place-1/messages/message-1"},
    get: (field: string) => fields[field],
  } as unknown as DocumentSnapshot;
}
