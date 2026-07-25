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

test("rejects localized or unknown report reason values", () => {
  assert.throws(() => reportReasonCodeOf("スパムまたは広告"));
  assert.throws(() => reportReasonCodeOf("Spam or advertising"));
  assert.throws(() => reportReasonCodeOf("unknown"));
  assert.throws(() => reportReasonCodeOf(null));
});
