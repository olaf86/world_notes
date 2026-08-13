/* eslint-disable require-jsdoc */

import assert from "node:assert/strict";
import test from "node:test";

import {
  parseMirrorOnlySmokeArgs,
  requireMirrorOnlyTarget,
} from "../src/scripts/smokeMirrorOnlyWorld";

const BASE = [
  "--project", "world-notes-prod",
  "--world", "northAmerica",
  "--report", "/tmp/north-america-smoke.json",
];

test("mirror-only smoke requires exact project and world confirmation", () => {
  assert.throws(() => parseMirrorOnlySmokeArgs(BASE));
  assert.throws(() => parseMirrorOnlySmokeArgs([
    ...BASE,
    "--confirm-project", "world-notes-prod",
    "--confirm-world", "europe",
  ]));
  assert.deepEqual(parseMirrorOnlySmokeArgs([
    ...BASE,
    "--confirm-project", "world-notes-prod",
    "--confirm-world", "northAmerica",
  ]), {
    projectId: "world-notes-prod",
    worldId: "northAmerica",
    reportPath: "/tmp/north-america-smoke.json",
  });
});

test("mirror-only smoke accepts only closed non-Asia catalog worlds", () => {
  assert.equal(
    requireMirrorOnlyTarget("northAmerica").databaseId,
    "north-america",
  );
  assert.equal(requireMirrorOnlyTarget("europe").databaseId, "europe");
  assert.throws(() => requireMirrorOnlyTarget("asia"));
  assert.throws(() => requireMirrorOnlyTarget("missing"));
});
