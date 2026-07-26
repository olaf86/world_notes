import assert from "node:assert/strict";
import test from "node:test";

import {takeVisibleMapPins} from "../src/mapPins";

interface TestPin {
  id: string;
  creatorUid: string;
}

/**
 * Creates the minimal map pin shape required by the selection helper.
 *
 * @param {string} id Test pin id.
 * @param {string} creatorUid Test creator id.
 * @return {TestPin} Test pin.
 */
function pin(id: string, creatorUid = id): TestPin {
  return {id, creatorUid};
}

test("checks only the initial window when every pin is visible", async () => {
  const pins = Array.from(
    {length: 130},
    (_, index) => pin(`pin-${index}`, `creator-${index}`),
  );
  const checkedCreatorBatches: string[][] = [];

  const result = await takeVisibleMapPins(
    pins,
    120,
    async (candidateUids) => {
      checkedCreatorBatches.push(candidateUids);
      return new Set();
    },
  );

  assert.equal(result.length, 120);
  assert.deepEqual(
    result.map((candidate) => candidate.id),
    pins.slice(0, 120).map((candidate) => candidate.id),
  );
  assert.equal(checkedCreatorBatches.length, 1);
  assert.deepEqual(
    checkedCreatorBatches[0],
    pins.slice(0, 120).map((candidate) => candidate.creatorUid),
  );
});

test("checks later pins only to fill blocked vacancies", async () => {
  const pins = [
    pin("blocked-first", "blocked"),
    pin("visible-first", "visible-first"),
    pin("blocked-again", "blocked"),
    pin("visible-second", "visible-second"),
    pin("visible-third", "visible-third"),
  ];
  const checkedCreatorBatches: string[][] = [];

  const result = await takeVisibleMapPins(
    pins,
    3,
    async (candidateUids) => {
      checkedCreatorBatches.push(candidateUids);
      return new Set(candidateUids.filter((uid) => uid === "blocked"));
    },
  );

  assert.deepEqual(
    result.map((candidate) => candidate.id),
    ["visible-first", "visible-second", "visible-third"],
  );
  assert.deepEqual(checkedCreatorBatches, [
    ["blocked", "visible-first"],
    ["visible-second", "visible-third"],
  ]);
});
