import assert from "node:assert/strict";
import test from "node:test";

import {HttpsError} from "firebase-functions/v2/https";

import {
  adminModerationReviewCursor,
  parseAdminModerationReviewCursor,
} from "../src/adminModeration";

const CURSOR_DATA = {
  schemaVersion: 1 as const,
  worldId: "europe",
  status: "open" as const,
  createdAtMillis: 1_753_000_000_000,
  documentId: "review_test_message",
};

test("moderation cursor round-trips its world and list position", () => {
  const encoded = adminModerationReviewCursor(CURSOR_DATA);

  assert.deepEqual(
    parseAdminModerationReviewCursor(encoded, "europe", "open"),
    CURSOR_DATA,
  );
});

test("moderation cursor cannot cross worlds or review states", () => {
  const encoded = adminModerationReviewCursor(CURSOR_DATA);

  for (const [worldId, status] of [
    ["northAmerica", "open"],
    ["europe", "resolved"],
  ] as const) {
    assert.throws(
      () => parseAdminModerationReviewCursor(encoded, worldId, status),
      (error: unknown) =>
        error instanceof HttpsError && error.code === "invalid-argument",
    );
  }
});

test("moderation cursor rejects malformed or path-like document ids", () => {
  const pathCursor = adminModerationReviewCursor({
    ...CURSOR_DATA,
    documentId: "reviews/another",
  });

  for (const value of ["not-base64-json", pathCursor]) {
    assert.throws(
      () => parseAdminModerationReviewCursor(value, "europe", "open"),
      (error: unknown) =>
        error instanceof HttpsError && error.code === "invalid-argument",
    );
  }
});
