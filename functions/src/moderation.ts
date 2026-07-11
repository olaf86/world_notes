/* eslint-disable require-jsdoc */
import {defineSecret} from "firebase-functions/params";
import {HttpsError} from "firebase-functions/v2/https";
import {
  DocumentReference,
  FieldValue,
  Timestamp,
  Transaction,
} from "firebase-admin/firestore";

import {
  CreateUserNoticeInput,
  createUserNotice,
  timestampFromFutureHours,
} from "./notices";

// Set with: firebase functions:secrets:set OPENAI_API_KEY
export const OPENAI_API_KEY = defineSecret("OPENAI_API_KEY");

type ModerationProviderId = "openai";
type ModerationAction =
  "allow" |
  "sensitive" |
  "hidden" |
  "review" |
  "pending";
type InternalCategory =
  "harassment" |
  "hate" |
  "sexual" |
  "sexualMinors" |
  "violence" |
  "selfHarm" |
  "illicit" |
  "profanity" |
  "weapons" |
  "sensitiveTopic";
type ModerationSeverity = "low" | "medium" | "high" | "critical";
type AppModerationRiskSignalCategory = "email" | "phoneNumber";
type AppModerationRiskSignalSeverity = "medium" | "high";

interface ModerationCategoryScore {
  category: InternalCategory;
  score: number;
  matched: boolean;
  severity: ModerationSeverity;
}

export interface InternalModerationResult {
  provider: ModerationProviderId;
  providerModel: string;
  policyVersion: string;
  flagged: boolean;
  action: ModerationAction;
  maxScore: number;
  categories: ModerationCategoryScore[];
  providerResultId?: string;
}

export interface AppModerationRiskSignal {
  category: AppModerationRiskSignalCategory;
  severity: AppModerationRiskSignalSeverity;
  reviewRecommended: boolean;
}

export interface OpenAiModerationResponse {
  id?: string;
  model?: string;
  results?: Array<{
    flagged?: boolean;
    categories?: Record<string, boolean>;
    category_scores?: Record<string, number>;
  }>;
}

const POLICY_VERSION = "2026-07-moderation-v1";
const OPENAI_MODERATION_MODEL = "omni-moderation-latest";
const OPENAI_MODERATION_URL = "https://api.openai.com/v1/moderations";
const SENSITIVE_SCORE_THRESHOLD = 0.70;
const HIDDEN_SCORE_THRESHOLD = 0.90;
const REVIEW_SCORE_THRESHOLD = 0.82;
const WARNING_POINTS_THRESHOLD = 3;
const RESTRICTION_POINTS_THRESHOLD = 10;
const BAN_POINTS_THRESHOLD = 16;
const POSTING_RESTRICTION_DURATION_HOURS = 24;
const TEMPORARY_BAN_DURATION_HOURS = 24 * 7;

const OPENAI_CATEGORY_MAP: Record<string, InternalCategory> = {
  "harassment": "harassment",
  "harassment/threatening": "harassment",
  "hate": "hate",
  "hate/threatening": "hate",
  "sexual": "sexual",
  "sexual/minors": "sexualMinors",
  "violence": "violence",
  "violence/graphic": "violence",
  "self-harm": "selfHarm",
  "self-harm/intent": "selfHarm",
  "self-harm/instructions": "selfHarm",
  "illicit": "illicit",
  "illicit/violent": "illicit",
};

const CRITICAL_CATEGORIES = new Set<InternalCategory>([
  "sexualMinors",
  "hate",
  "violence",
  "illicit",
]);

const USER_CONTENT_BLOCKED_MESSAGE =
  "Your account is temporarily restricted from posting.";

const EMAIL_PATTERN = /[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}/i;
const SEPARATED_PHONE_PATTERN =
  /(?:\+81[-\s]?)?0?\d{1,4}[-\s]\d{1,4}[-\s]\d{3,4}/;
const MOBILE_PHONE_PATTERN = /\b(?:070|080|090)\d{8}\b/;

function scoreOf(value: unknown): number {
  return typeof value === "number" && isFinite(value) ?
    Math.max(0, Math.min(1, value)) :
    0;
}

function severityFor(
  category: InternalCategory,
  score: number,
  matched: boolean,
): ModerationSeverity {
  if (category === "sexualMinors") return matched ? "critical" : "high";
  if (CRITICAL_CATEGORIES.has(category) && score >= HIDDEN_SCORE_THRESHOLD) {
    return "critical";
  }
  if (score >= HIDDEN_SCORE_THRESHOLD) return "high";
  if (score >= SENSITIVE_SCORE_THRESHOLD) return "medium";
  return "low";
}

function mergeCategoryScore(
  byCategory: Map<InternalCategory, ModerationCategoryScore>,
  category: InternalCategory,
  score: number,
  matched: boolean,
): void {
  const current = byCategory.get(category);
  const nextMatched = (current?.matched ?? false) || matched;
  const nextScore = Math.max(current?.score ?? 0, score);
  byCategory.set(category, {
    category,
    score: nextScore,
    matched: nextMatched,
    severity: severityFor(category, nextScore, nextMatched),
  });
}

function actionFor(categories: ModerationCategoryScore[]): ModerationAction {
  const maxScore = Math.max(0, ...categories.map((entry) => entry.score));
  const hasCritical = categories.some((entry) =>
    entry.matched && entry.severity === "critical",
  );
  if (hasCritical || maxScore >= HIDDEN_SCORE_THRESHOLD) return "hidden";
  const hasReview = categories.some((entry) =>
    entry.matched && entry.severity === "high",
  );
  if (hasReview || maxScore >= REVIEW_SCORE_THRESHOLD) return "review";
  if (maxScore >= SENSITIVE_SCORE_THRESHOLD) return "sensitive";
  return "allow";
}

function pendingModerationResult(): InternalModerationResult {
  return {
    provider: "openai",
    providerModel: OPENAI_MODERATION_MODEL,
    policyVersion: POLICY_VERSION,
    flagged: false,
    action: "pending",
    maxScore: 0,
    categories: [],
  };
}

function canDeferModeration(status: number): boolean {
  return status === 429 || status >= 500;
}

export function normalizeOpenAiModeration(
  response: OpenAiModerationResponse,
): InternalModerationResult {
  const result = response.results?.[0] ?? {};
  const byCategory = new Map<InternalCategory, ModerationCategoryScore>();
  for (const [providerCategory, internalCategory] of Object.entries(
    OPENAI_CATEGORY_MAP,
  )) {
    mergeCategoryScore(
      byCategory,
      internalCategory,
      scoreOf(result.category_scores?.[providerCategory]),
      result.categories?.[providerCategory] === true,
    );
  }
  const categories = [...byCategory.values()];
  const action = actionFor(categories);
  return {
    provider: "openai",
    providerModel: response.model ?? OPENAI_MODERATION_MODEL,
    policyVersion: POLICY_VERSION,
    flagged: result.flagged === true,
    action,
    maxScore: Math.max(0, ...categories.map((entry) => entry.score)),
    categories,
    providerResultId: response.id,
  };
}

export async function moderateTextContent(
  content: string,
): Promise<InternalModerationResult> {
  const trimmed = content.replace(/\s+/g, " ").trim();
  if (trimmed.length === 0) {
    return {
      provider: "openai",
      providerModel: OPENAI_MODERATION_MODEL,
      policyVersion: POLICY_VERSION,
      flagged: false,
      action: "allow",
      maxScore: 0,
      categories: [],
    };
  }

  let response: Response;
  try {
    response = await fetch(OPENAI_MODERATION_URL, {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${OPENAI_API_KEY.value()}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model: OPENAI_MODERATION_MODEL,
        input: trimmed,
      }),
    });
  } catch {
    return pendingModerationResult();
  }
  if (!response.ok) {
    if (canDeferModeration(response.status)) {
      return pendingModerationResult();
    }
    throw new HttpsError(
      "unavailable",
      "Could not check message safety.",
      {status: response.status},
    );
  }
  return normalizeOpenAiModeration(
    await response.json() as OpenAiModerationResponse,
  );
}

function riskSignal(
  category: AppModerationRiskSignalCategory,
  severity: AppModerationRiskSignalSeverity = "high",
): AppModerationRiskSignal {
  return {
    category,
    severity,
    reviewRecommended: true,
  };
}

export function detectAppModerationRiskSignals(
  content: string,
): AppModerationRiskSignal[] {
  const normalized = content.replace(/\s+/g, " ").trim();
  if (normalized.length === 0) return [];

  const signals: AppModerationRiskSignal[] = [];
  if (EMAIL_PATTERN.test(normalized)) {
    signals.push(riskSignal("email"));
  }
  if (
    SEPARATED_PHONE_PATTERN.test(normalized) ||
    MOBILE_PHONE_PATTERN.test(normalized)
  ) {
    signals.push(riskSignal("phoneNumber"));
  }
  return signals;
}

export function hasReviewRecommendedRiskSignal(
  signals: AppModerationRiskSignal[],
): boolean {
  return signals.some((signal) => signal.reviewRecommended);
}

export function moderationFields(
  result: InternalModerationResult,
): Record<string, unknown> {
  return {
    moderationAction: result.action,
    moderationProvider: result.provider,
    moderationPolicyVersion: result.policyVersion,
    isSensitive: result.action === "sensitive" ||
      result.action === "review",
    isVisible: true,
    reviewRequired: result.action === "review" ||
      result.action === "hidden",
  };
}

export function moderationAuditFields(
  result: InternalModerationResult,
): Record<string, unknown> {
  return {
    provider: result.provider,
    providerModel: result.providerModel,
    policyVersion: result.policyVersion,
    flagged: result.flagged,
    action: result.action,
    maxScore: result.maxScore,
    categories: result.categories.map((entry) => ({
      category: entry.category,
      score: entry.score,
      matched: entry.matched,
      severity: entry.severity,
    })),
    providerResultId: result.providerResultId ?? null,
    checkedAt: FieldValue.serverTimestamp(),
  };
}

function violationPointsFor(result: InternalModerationResult): number {
  const policyMatchedCategories = result.categories.filter((entry) =>
    entry.matched || entry.score >= SENSITIVE_SCORE_THRESHOLD,
  );
  const isSelfHarmOnly = policyMatchedCategories.length > 0 &&
    policyMatchedCategories.every((entry) => entry.category === "selfHarm");
  if (isSelfHarmOnly) return 0;

  switch (result.action) {
  case "hidden":
    return 4;
  case "review":
    return 3;
  case "sensitive":
    return 1;
  case "allow":
    return 0;
  case "pending":
    return 0;
  }
}

function userNoticeForPoints(
  result: InternalModerationResult,
  nextPoints: number,
): CreateUserNoticeInput | null {
  if (result.action === "allow" || result.action === "pending") return null;
  if (nextPoints >= BAN_POINTS_THRESHOLD) {
    return {
      category: "ban",
      severity: "critical",
      title: "Account temporarily banned",
      body: "Your account has been temporarily banned because recent posts " +
        "violated the community safety policy.",
      push: true,
    };
  }
  if (nextPoints >= RESTRICTION_POINTS_THRESHOLD) {
    return {
      category: "moderation",
      severity: "critical",
      title: "Posting temporarily restricted",
      body: "Your account is temporarily restricted from posting because " +
        "recent posts violated the community safety policy.",
      push: true,
    };
  }
  if (nextPoints >= WARNING_POINTS_THRESHOLD || result.action === "hidden") {
    return {
      category: "moderation",
      severity: "warning",
      title: "Please review the community safety policy",
      body: "One of your posts was hidden or sent to review because it may " +
        "violate the community safety policy. Repeated violations can lead " +
        "to posting restrictions or a ban.",
      push: true,
    };
  }
  return {
    category: "moderation",
    severity: "info",
    title: "Post marked as sensitive",
    body: "One of your posts may contain sensitive content. It remains " +
      "available with additional safety handling.",
  };
}

export async function createModerationNoticeIfNeeded(
  uid: string,
  result: InternalModerationResult,
  nextPoints: number,
): Promise<void> {
  const notice = userNoticeForPoints(result, nextPoints);
  if (notice == null) return;
  await createUserNotice(uid, notice);
}

export async function assertUserCanCreateContent(
  tx: Transaction,
  userRef: DocumentReference,
  nowMs: number,
): Promise<void> {
  const userSnap = await tx.get(userRef);
  const bannedUntil = userSnap.get("bannedUntil") as Timestamp | null;
  if (bannedUntil !== null && bannedUntil.toMillis() > nowMs) {
    throw new HttpsError(
      "permission-denied",
      "Your account is temporarily banned.",
    );
  }
  const restrictedUntil =
    userSnap.get("restrictedUntil") as Timestamp | null;
  if (restrictedUntil !== null && restrictedUntil.toMillis() > nowMs) {
    throw new HttpsError("permission-denied", USER_CONTENT_BLOCKED_MESSAGE);
  }
}

export async function applyModerationToUser(
  tx: Transaction,
  userRef: DocumentReference,
  result: InternalModerationResult,
): Promise<number> {
  const points = violationPointsFor(result);
  if (points === 0) return 0;

  const userSnap = await tx.get(userRef);
  const currentPoints = userSnap.get("violationPoints") as number;
  const nextPoints = currentPoints + points;
  const update: Record<string, unknown> = {
    violationPoints: nextPoints,
    lastViolationAt: FieldValue.serverTimestamp(),
    moderationStatus: "warned",
  };
  if (nextPoints >= BAN_POINTS_THRESHOLD) {
    update.moderationStatus = "banned";
    update.bannedUntil = timestampFromFutureHours(
      TEMPORARY_BAN_DURATION_HOURS,
    );
  } else if (nextPoints >= RESTRICTION_POINTS_THRESHOLD) {
    update.moderationStatus = "restricted";
    update.restrictedUntil = timestampFromFutureHours(
      POSTING_RESTRICTION_DURATION_HOURS,
    );
  }
  tx.set(userRef, update, {merge: true});
  return nextPoints;
}
