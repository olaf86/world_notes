/* eslint-disable require-jsdoc */

import assert from "node:assert/strict";
import test from "node:test";

import {DocumentSnapshot, Timestamp} from "firebase-admin/firestore";

import {
  isActiveNoteForAdministration,
  isNoteMaintainer,
} from "../src/noteMaintenance";

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

test("normalizes creator and delegated administrator authority", () => {
  const place = snapshot({createdByUserId: "creator"}, "place");
  assert.equal(isNoteMaintainer(place, null, "creator"), true);
  assert.equal(
    isNoteMaintainer(
      place,
      snapshot({userId: "delegate"}, "delegate"),
      "delegate",
    ),
    true,
  );
  assert.equal(
    isNoteMaintainer(
      place,
      snapshot({userId: "someone-else"}, "delegate"),
      "delegate",
    ),
    false,
  );
  assert.equal(isNoteMaintainer(place, snapshot(null, "delegate"), "delegate"),
    false);
});

function snapshot(
  data: Record<string, unknown> | null,
  id = "test",
): DocumentSnapshot {
  return {
    id,
    exists: data !== null,
    get: (field: string) => data?.[field],
  } as unknown as DocumentSnapshot;
}
