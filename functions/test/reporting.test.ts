import assert from "node:assert/strict";
import test from "node:test";

import {reportReasonCodeOf} from "../src/reporting";

test("accepts stable report reason codes", () => {
  assert.equal(reportReasonCodeOf("spam"), "spam");
  assert.equal(reportReasonCodeOf("harassment"), "harassment");
  assert.equal(reportReasonCodeOf("sexual"), "sexual");
  assert.equal(reportReasonCodeOf("illegal"), "illegal");
  assert.equal(reportReasonCodeOf("other"), "other");
});

test("maps legacy English report labels during client rollout", () => {
  assert.equal(reportReasonCodeOf("Spam or advertising"), "spam");
  assert.equal(reportReasonCodeOf("Harassment or bullying"), "harassment");
  assert.equal(reportReasonCodeOf("Adult or explicit content"), "sexual");
  assert.equal(reportReasonCodeOf("Illegal content"), "illegal");
  assert.equal(reportReasonCodeOf("Other"), "other");
});

test("rejects localized or unknown report reason values", () => {
  assert.throws(() => reportReasonCodeOf("スパムまたは広告"));
  assert.throws(() => reportReasonCodeOf("unknown"));
  assert.throws(() => reportReasonCodeOf(null));
});
