/* eslint-disable require-jsdoc */
import {
  detectAppModerationRiskSignals,
  type AppModerationRiskSignalCategory,
  type InternalModerationResult,
  type ModerationAction,
} from "./moderation";

export type ExpectedModerationAction = Exclude<ModerationAction, "pending">;

export interface ModerationEvaluationCase {
  id: string;
  description: string;
  content: string;
  expectedAction: ExpectedModerationAction;
  expectedRiskSignals: AppModerationRiskSignalCategory[];
}

export interface ModerationEvaluationDataset {
  schemaVersion: 1;
  cases: ModerationEvaluationCase[];
}

export interface ModerationEvaluationCaseResult {
  id: string;
  description: string;
  providerModel: string;
  policyVersion: string;
  expectedAction: ExpectedModerationAction;
  actualAction: ModerationAction;
  actionMatched: boolean;
  expectedRiskSignals: AppModerationRiskSignalCategory[];
  actualRiskSignals: AppModerationRiskSignalCategory[];
  riskSignalsMatched: boolean;
  expectedReviewQueue: boolean;
  actualReviewQueue: boolean;
  reviewQueueMatched: boolean;
  maxScore: number;
  matchedCategories: string[];
}

export interface ModerationEvaluationReport {
  schemaVersion: 1;
  evaluatedAt: string;
  caseCount: number;
  providerModels: string[];
  policyVersions: string[];
  actionAccuracy: number;
  riskSignalAccuracy: number;
  reviewQueueAccuracy: number;
  falseAllowCaseIds: string[];
  unexpectedModerationCaseIds: string[];
  missedReviewQueueCaseIds: string[];
  unexpectedReviewQueueCaseIds: string[];
  results: ModerationEvaluationCaseResult[];
}

const actions = new Set<ExpectedModerationAction>([
  "allow",
  "sensitive",
  "hidden",
  "review",
]);
const riskSignalCategories = new Set<AppModerationRiskSignalCategory>([
  "email",
  "phoneNumber",
]);

function record(value: unknown, field: string): Record<string, unknown> {
  if (value == null || typeof value !== "object" || Array.isArray(value)) {
    throw new Error(`${field} must be an object.`);
  }
  return value as Record<string, unknown>;
}

function requiredString(value: unknown, field: string): string {
  if (typeof value !== "string" || value.trim().length === 0) {
    throw new Error(`${field} must be a non-empty string.`);
  }
  return value;
}

function riskSignals(
  value: unknown,
  field: string,
): AppModerationRiskSignalCategory[] {
  if (!Array.isArray(value)) throw new Error(`${field} must be an array.`);
  const values = value.map((item, index) => {
    if (typeof item !== "string" ||
      !riskSignalCategories.has(item as AppModerationRiskSignalCategory)) {
      throw new Error(`${field}[${index}] must be email or phoneNumber.`);
    }
    return item as AppModerationRiskSignalCategory;
  });
  if (new Set(values).size !== values.length) {
    throw new Error(`${field} must not contain duplicates.`);
  }
  return values.sort();
}

export function parseModerationEvaluationDataset(
  value: unknown,
): ModerationEvaluationDataset {
  const dataset = record(value, "dataset");
  if (dataset.schemaVersion !== 1) {
    throw new Error("dataset.schemaVersion must be 1.");
  }
  if (!Array.isArray(dataset.cases) || dataset.cases.length === 0) {
    throw new Error("dataset.cases must be a non-empty array.");
  }
  const ids = new Set<string>();
  const cases = dataset.cases.map((item, index) => {
    const entry = record(item, `dataset.cases[${index}]`);
    const id = requiredString(entry.id, `dataset.cases[${index}].id`);
    if (ids.has(id)) throw new Error(`Duplicate evaluation case id: ${id}.`);
    ids.add(id);
    const expectedAction = requiredString(
      entry.expectedAction,
      `dataset.cases[${index}].expectedAction`,
    );
    if (!actions.has(expectedAction as ExpectedModerationAction)) {
      throw new Error(`Invalid expected action for ${id}: ${expectedAction}.`);
    }
    return {
      id,
      description: requiredString(
        entry.description,
        `dataset.cases[${index}].description`,
      ),
      content: requiredString(entry.content, `dataset.cases[${index}].content`),
      expectedAction: expectedAction as ExpectedModerationAction,
      expectedRiskSignals: riskSignals(
        entry.expectedRiskSignals,
        `dataset.cases[${index}].expectedRiskSignals`,
      ),
    };
  });
  return {schemaVersion: 1, cases};
}

function sameStrings(first: string[], second: string[]): boolean {
  return first.length === second.length &&
    first.every((value, index) => value === second[index]);
}

export function evaluateModerationCase(
  evaluationCase: ModerationEvaluationCase,
  result: InternalModerationResult,
): ModerationEvaluationCaseResult {
  const signals = detectAppModerationRiskSignals(evaluationCase.content);
  const actualRiskSignals = signals
    .map((signal) => signal.category)
    .sort();
  const expectedReviewQueue = evaluationCase.expectedAction !== "allow" ||
    evaluationCase.expectedRiskSignals.length > 0;
  const actualReviewQueue = (result.action !== "allow" &&
    result.action !== "pending") || actualRiskSignals.length > 0;
  return {
    id: evaluationCase.id,
    description: evaluationCase.description,
    providerModel: result.providerModel,
    policyVersion: result.policyVersion,
    expectedAction: evaluationCase.expectedAction,
    actualAction: result.action,
    actionMatched: evaluationCase.expectedAction === result.action,
    expectedRiskSignals: evaluationCase.expectedRiskSignals,
    actualRiskSignals,
    riskSignalsMatched: sameStrings(
      evaluationCase.expectedRiskSignals,
      actualRiskSignals,
    ),
    expectedReviewQueue,
    actualReviewQueue,
    reviewQueueMatched: expectedReviewQueue === actualReviewQueue,
    maxScore: result.maxScore,
    matchedCategories: result.categories
      .filter((category) => category.matched)
      .map((category) => category.category),
  };
}

function accuracy(matches: number, total: number): number {
  return total === 0 ? 0 : matches / total;
}

export function buildModerationEvaluationReport(
  results: ModerationEvaluationCaseResult[],
  evaluatedAt = new Date().toISOString(),
): ModerationEvaluationReport {
  return {
    schemaVersion: 1,
    evaluatedAt,
    caseCount: results.length,
    providerModels: [...new Set(results.map((result) => result.providerModel))]
      .sort(),
    policyVersions: [...new Set(results.map((result) => result.policyVersion))]
      .sort(),
    actionAccuracy: accuracy(
      results.filter((result) => result.actionMatched).length,
      results.length,
    ),
    riskSignalAccuracy: accuracy(
      results.filter((result) => result.riskSignalsMatched).length,
      results.length,
    ),
    reviewQueueAccuracy: accuracy(
      results.filter((result) => result.reviewQueueMatched).length,
      results.length,
    ),
    falseAllowCaseIds: results.filter((result) =>
      result.expectedAction !== "allow" && result.actualAction === "allow",
    ).map((result) => result.id),
    unexpectedModerationCaseIds: results.filter((result) =>
      result.expectedAction === "allow" && result.actualAction !== "allow",
    ).map((result) => result.id),
    missedReviewQueueCaseIds: results.filter((result) =>
      result.expectedReviewQueue && !result.actualReviewQueue,
    ).map((result) => result.id),
    unexpectedReviewQueueCaseIds: results.filter((result) =>
      !result.expectedReviewQueue && result.actualReviewQueue,
    ).map((result) => result.id),
    results,
  };
}
