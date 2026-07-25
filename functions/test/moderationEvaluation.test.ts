/* eslint-disable require-jsdoc */
import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import {resolve} from "node:path";
import test from "node:test";

import {
  buildModerationEvaluationReport,
  evaluateModerationCase,
  parseModerationEvaluationDataset,
} from "../src/moderationEvaluation";
import type {InternalModerationResult} from "../src/moderation";

const allowedResult: InternalModerationResult = {
  provider: "openai",
  providerModel: "omni-moderation-latest",
  policyVersion: "test",
  flagged: false,
  action: "allow",
  maxScore: 0.03,
  categories: [],
};

test("ships a valid dataset that covers all final moderation actions", () => {
  const dataset = parseModerationEvaluationDataset(JSON.parse(readFileSync(
    resolve(process.cwd(), "evaluation/moderation-cases.json"),
    "utf8",
  )) as unknown);
  const actions = new Set(dataset.cases.map((item) => item.expectedAction));

  assert.deepEqual(
    actions,
    new Set(["allow", "sensitive", "review", "hidden"]),
  );
});

test("parses a labelled moderation evaluation dataset", () => {
  const dataset = parseModerationEvaluationDataset({
    schemaVersion: 1,
    cases: [{
      id: "ordinary-note",
      description: "Ordinary location diary note.",
      content: "The bakery by the station has great bread.",
      expectedAction: "allow",
      expectedRiskSignals: [],
    }],
  });

  assert.equal(dataset.cases[0]?.id, "ordinary-note");
  assert.equal(dataset.cases[0]?.expectedAction, "allow");
});

test("rejects duplicate evaluation ids", () => {
  assert.throws(() => parseModerationEvaluationDataset({
    schemaVersion: 1,
    cases: [{
      id: "same",
      description: "First case.",
      content: "First content.",
      expectedAction: "allow",
      expectedRiskSignals: [],
    }, {
      id: "same",
      description: "Second case.",
      content: "Second content.",
      expectedAction: "allow",
      expectedRiskSignals: [],
    }],
  }), /Duplicate evaluation case id/);
});

test("rejects unsupported expected actions", () => {
  assert.throws(() => parseModerationEvaluationDataset({
    schemaVersion: 1,
    cases: [{
      id: "unsupported-action",
      description: "A case with an unsupported expected action.",
      content: "Content.",
      expectedAction: "pending",
      expectedRiskSignals: [],
    }],
  }), /Invalid expected action/);
});

test("reports a false allow and a missed review queue", () => {
  const dataset = parseModerationEvaluationDataset({
    schemaVersion: 1,
    cases: [{
      id: "expected-review",
      description: "A human-labelled review case.",
      content: "Please review this message.",
      expectedAction: "review",
      expectedRiskSignals: [],
    }],
  });
  const evaluationCase = dataset.cases[0];
  assert.ok(evaluationCase);
  const result = evaluateModerationCase(evaluationCase, allowedResult);
  const report = buildModerationEvaluationReport(
    [result],
    "2026-07-15T00:00:00.000Z",
  );

  assert.equal(report.actionAccuracy, 0);
  assert.equal(report.reviewQueueAccuracy, 0);
  assert.deepEqual(report.falseAllowCaseIds, ["expected-review"]);
  assert.deepEqual(report.missedReviewQueueCaseIds, ["expected-review"]);
});

test("includes app risk signals in review queue evaluation", () => {
  const dataset = parseModerationEvaluationDataset({
    schemaVersion: 1,
    cases: [{
      id: "contact-information",
      description: "A case with a Japanese phone number.",
      content: "Call me at 09012345678.",
      expectedAction: "allow",
      expectedRiskSignals: ["phoneNumber"],
    }],
  });
  const evaluationCase = dataset.cases[0];
  assert.ok(evaluationCase);
  const result = evaluateModerationCase(evaluationCase, allowedResult);

  assert.equal(result.riskSignalsMatched, true);
  assert.equal(result.expectedReviewQueue, true);
  assert.equal(result.actualReviewQueue, true);
});
