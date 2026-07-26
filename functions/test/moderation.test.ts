/* eslint-disable require-jsdoc */
import assert from "node:assert/strict";
import test from "node:test";

import {
  automatedRejectionAuditFields,
  detectAppModerationRiskSignals,
  type OpenAiModerationResponse,
  moderationFields,
  normalizeOpenAiModeration,
} from "../src/moderation";

function moderationResponse({
  scores = {},
  categories = {},
}: {
  scores?: Record<string, number>;
  categories?: Record<string, boolean>;
}): OpenAiModerationResponse {
  return {
    id: "modr_test",
    model: "omni-moderation-latest",
    results: [{
      flagged: Object.values(categories).some((matched) => matched),
      categories,
      category_scores: scores,
    }],
  };
}

test("normalizes low-risk OpenAI moderation results as allow", () => {
  const result = normalizeOpenAiModeration(moderationResponse({
    scores: {
      harassment: 0.12,
      sexual: 0.04,
      violence: 0.08,
    },
  }));

  assert.equal(result.action, "allow");
  assert.equal(result.flagged, false);
  assert.equal(result.maxScore, 0.12);
  assert.deepEqual(moderationFields(result), {
    moderationAction: "allow",
    moderationProvider: "openai",
    moderationPolicyVersion: "2026-07-moderation-v1",
    isSensitive: false,
    isVisible: true,
    reviewRequired: false,
  });
});

test("builds a content-free automated rejection audit event", () => {
  const result = normalizeOpenAiModeration(moderationResponse({
    scores: {violence: 0.95},
    categories: {violence: true},
  }));
  const fields = automatedRejectionAuditFields({
    uid: "user-1",
    sourceType: "noteDraft",
    result,
    violationPointsAfter: 7,
  });

  assert.equal(fields.eventType, "automatedRejection");
  assert.equal(fields.actorType, "provider");
  assert.equal(fields.actorId, "openai");
  assert.equal(fields.subjectUserId, "user-1");
  assert.equal(fields.sourceType, "noteDraft");
  assert.equal(fields.action, "hidden");
  assert.equal(fields.violationPointsAfter, 7);
  assert.equal("content" in fields, false);
  assert.equal("imageBytes" in fields, false);
});

test("marks threshold-level scores as sensitive without review", () => {
  const result = normalizeOpenAiModeration(moderationResponse({
    scores: {
      sexual: 0.71,
    },
  }));

  assert.equal(result.action, "sensitive");
  assert.deepEqual(moderationFields(result), {
    moderationAction: "sensitive",
    moderationProvider: "openai",
    moderationPolicyVersion: "2026-07-moderation-v1",
    isSensitive: true,
    isVisible: true,
    reviewRequired: false,
  });
});

test("sends high-but-not-hidden scores to review", () => {
  const result = normalizeOpenAiModeration(moderationResponse({
    scores: {
      harassment: 0.83,
    },
  }));

  assert.equal(result.action, "review");
  assert.deepEqual(moderationFields(result), {
    moderationAction: "review",
    moderationProvider: "openai",
    moderationPolicyVersion: "2026-07-moderation-v1",
    isSensitive: true,
    isVisible: true,
    reviewRequired: true,
  });
});

test("hides content when any category crosses the hidden threshold", () => {
  const result = normalizeOpenAiModeration(moderationResponse({
    scores: {
      "harassment/threatening": 0.91,
    },
    categories: {
      "harassment/threatening": true,
    },
  }));

  const harassment = result.categories.find((entry) =>
    entry.category === "harassment"
  );
  assert.equal(result.action, "hidden");
  assert.equal(result.flagged, true);
  assert.equal(harassment?.score, 0.91);
  assert.equal(harassment?.matched, true);
  assert.equal(harassment?.severity, "high");
});

test("hides matched sexual-minors results even with low scores", () => {
  const result = normalizeOpenAiModeration(moderationResponse({
    scores: {
      "sexual/minors": 0.1,
    },
    categories: {
      "sexual/minors": true,
    },
  }));

  const sexualMinors = result.categories.find((entry) =>
    entry.category === "sexualMinors"
  );
  assert.equal(result.action, "hidden");
  assert.equal(sexualMinors?.matched, true);
  assert.equal(sexualMinors?.severity, "critical");
});

test("uses the riskiest result from multimodal moderation", () => {
  const result = normalizeOpenAiModeration({
    id: "modr_multimodal",
    model: "omni-moderation-latest",
    results: [
      {
        flagged: false,
        categories: {harassment: false},
        category_scores: {harassment: 0.1},
      },
      {
        flagged: true,
        categories: {"violence/graphic": true},
        category_scores: {"violence/graphic": 0.93},
      },
    ],
  });

  assert.equal(result.action, "hidden");
  assert.equal(result.flagged, true);
  assert.equal(result.maxScore, 0.93);
});

test("detects email addresses as app moderation risk signals", () => {
  const signals = detectAppModerationRiskSignals(
    "Contact me at user@example.com later.",
  );

  assert.deepEqual(signals, [{
    category: "email",
    severity: "high",
    reviewRecommended: true,
  }]);
});

test("detects Japanese phone numbers as app moderation risk signals", () => {
  const signals = detectAppModerationRiskSignals(
    "LINEできないなら 09012345678 に電話して",
  );

  assert.deepEqual(signals, [{
    category: "phoneNumber",
    severity: "high",
    reviewRecommended: true,
  }]);
});

test("detects international phone numbers as risk signals", () => {
  const signals = detectAppModerationRiskSignals(
    "Call me at +1 415 555 2671 tomorrow.",
  );

  assert.deepEqual(signals, [{
    category: "phoneNumber",
    severity: "high",
    reviewRecommended: true,
  }]);
});

test("does not treat order-like numbers as phone risk signals", () => {
  const signals = detectAppModerationRiskSignals(
    "注文番号 202607110001 を確認してください。",
  );

  assert.deepEqual(signals, []);
});

test("does not emit app moderation risk signals for ordinary text", () => {
  const signals = detectAppModerationRiskSignals(
    "今日は駅前のカフェがとても混んでいました。",
  );

  assert.deepEqual(signals, []);
});
