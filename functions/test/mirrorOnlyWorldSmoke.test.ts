/* eslint-disable require-jsdoc */

import assert from "node:assert/strict";
import test from "node:test";

import {
  parseMirrorOnlySmokeArgs,
  requireMirrorOnlyTarget,
} from "../src/scripts/smokeMirrorOnlyWorld";

const BASE = [
  "--project", "world-notes-prod",
  "--world", "europe",
  "--report", "/tmp/europe-smoke.json",
];

test("mirror-only smoke requires exact project and world confirmation", () => {
  assert.throws(() => parseMirrorOnlySmokeArgs(BASE));
  assert.throws(() => parseMirrorOnlySmokeArgs([
    ...BASE,
    "--confirm-project", "world-notes-prod",
    "--confirm-world", "northAmerica",
  ]));
  assert.deepEqual(parseMirrorOnlySmokeArgs([
    ...BASE,
    "--confirm-project", "world-notes-prod",
    "--confirm-world", "europe",
  ]), {
    projectId: "world-notes-prod",
    worldId: "europe",
    reportPath: "/tmp/europe-smoke.json",
  });
});

test("mirror-only smoke accepts only closed non-Asia catalog worlds", () => {
  assert.equal(requireMirrorOnlyTarget("europe").databaseId, "europe");
  assert.throws(() => requireMirrorOnlyTarget("northAmerica"));
  assert.throws(() => requireMirrorOnlyTarget("asia"));
  assert.throws(() => requireMirrorOnlyTarget("missing"));
});
