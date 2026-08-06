/* eslint-disable require-jsdoc */

import assert from "node:assert/strict";
import test from "node:test";

import {DocumentSnapshot, Timestamp} from "firebase-admin/firestore";

import {isActiveNoteForAdministration} from "../src/noteMaintenance";

const NOW_MILLIS = 1_000;

test("active-note administration requires a visible unexpired note", () => {
  assert.equal(isActiveNoteForAdministration(snapshot({
    isArchived: false,
    isModerationHidden: false,
    expiresAt: Timestamp.fromMillis(NOW_MILLIS + 1),
  }), NOW_MILLIS), true);
  assert.equal(isActiveNoteForAdministration(snapshot({
    isArchived: true,
    isModerationHidden: false,
    expiresAt: Timestamp.fromMillis(NOW_MILLIS + 1),
  }), NOW_MILLIS), false);
  assert.equal(isActiveNoteForAdministration(snapshot({
    isArchived: false,
    isModerationHidden: true,
    expiresAt: Timestamp.fromMillis(NOW_MILLIS + 1),
  }), NOW_MILLIS), false);
  assert.equal(isActiveNoteForAdministration(snapshot({
    isArchived: false,
    isModerationHidden: false,
    expiresAt: Timestamp.fromMillis(NOW_MILLIS),
  }), NOW_MILLIS), false);
  assert.equal(
    isActiveNoteForAdministration(snapshot(null), NOW_MILLIS),
    false,
  );
});

function snapshot(
  data: Record<string, unknown> | null,
): DocumentSnapshot {
  return {
    exists: data !== null,
    get: (field: string) => data?.[field],
  } as unknown as DocumentSnapshot;
}
