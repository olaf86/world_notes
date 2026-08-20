/* eslint-disable require-jsdoc */

import assert from "node:assert/strict";
import test from "node:test";

import {HttpsError} from "firebase-functions/v2/https";

import {
  adminMessagePublicTransition,
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

test("hiding and restoring a public message changes the aggregate once", () => {
  assert.deepEqual(
    adminMessagePublicTransition({
      action: "hidden",
      currentIsPubliclyVisible: true,
      restorePubliclyVisible: false,
      isDeleted: false,
      isVisible: true,
    }),
    {wasPublic: true, willBePublic: false, delta: -1},
  );
  assert.deepEqual(
    adminMessagePublicTransition({
      action: "allow",
      currentIsPubliclyVisible: false,
      restorePubliclyVisible: true,
      isDeleted: true,
      isVisible: false,
    }),
    {wasPublic: false, willBePublic: true, delta: 1},
  );
});

test(
  "changing a visible moderation result preserves the public aggregate",
  () => {
    assert.deepEqual(
      adminMessagePublicTransition({
        action: "sensitive",
        currentIsPubliclyVisible: true,
        restorePubliclyVisible: false,
        isDeleted: false,
        isVisible: true,
      }),
      {wasPublic: true, willBePublic: true, delta: 0},
    );
  },
);

test(
  "restoring a scheduled message keeps it out of the public aggregate",
  () => {
    assert.deepEqual(
      adminMessagePublicTransition({
        action: "allow",
        currentIsPubliclyVisible: false,
        restorePubliclyVisible: false,
        isDeleted: true,
        isVisible: false,
      }),
      {wasPublic: false, willBePublic: false, delta: 0},
    );
  },
);
