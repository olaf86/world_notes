/* eslint-disable require-jsdoc, no-console */
import {readFile, writeFile} from "node:fs/promises";
import {resolve} from "node:path";

import {
  buildModerationEvaluationReport,
  evaluateModerationCase,
  parseModerationEvaluationDataset,
} from "../moderationEvaluation";
import {
  normalizeOpenAiModeration,
  OPENAI_MODERATION_MODEL,
  OPENAI_MODERATION_URL,
  type OpenAiModerationResponse,
} from "../moderation";

interface ParsedArgs {
  datasetPath: string;
  outputPath?: string;
  failOnMismatch: boolean;
}

function usage(): string {
  return [
    "Usage:",
    "  OPENAI_API_KEY=... npm run evaluate:moderation",
    "  OPENAI_API_KEY=... npm run evaluate:moderation -- --dataset <path>",
    "  OPENAI_API_KEY=... npm run evaluate:moderation -- --json <path>",
    "  OPENAI_API_KEY=... npm run evaluate:moderation -- --fail-on-mismatch",
  ].join("\n");
}

function parseArgs(argv: string[]): ParsedArgs {
  const args: ParsedArgs = {
    datasetPath: resolve(process.cwd(), "evaluation/moderation-cases.json"),
    failOnMismatch: false,
  };
  for (let index = 0; index < argv.length; index++) {
    const arg = argv[index];
    if (arg === "--dataset") {
      const path = argv[++index];
      if (path == null) {
        throw new Error(`--dataset requires a path.\n\n${usage()}`);
      }
      args.datasetPath = resolve(process.cwd(), path);
    } else if (arg === "--json") {
      const path = argv[++index];
      if (path == null) {
        throw new Error(`--json requires a path.\n\n${usage()}`);
      }
      args.outputPath = resolve(process.cwd(), path);
    } else if (arg === "--fail-on-mismatch") {
      args.failOnMismatch = true;
    } else {
      throw new Error(`Unknown argument: ${arg}\n\n${usage()}`);
    }
  }
  return args;
}

async function requestModeration(
  content: string,
  apiKey: string,
): Promise<OpenAiModerationResponse> {
  const response = await fetch(OPENAI_MODERATION_URL, {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${apiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({model: OPENAI_MODERATION_MODEL, input: content}),
  });
  if (!response.ok) {
    throw new Error(
      "Moderation request failed with HTTP " +
        `${response.status}: ${await response.text()}`,
    );
  }
  return await response.json() as OpenAiModerationResponse;
}

function printReport(
  report: ReturnType<typeof buildModerationEvaluationReport>,
) {
  console.table(report.results.map((result) => ({
    id: result.id,
    expected: result.expectedAction,
    actual: result.actualAction,
    actionMatch: result.actionMatched,
    expectedReview: result.expectedReviewQueue,
    actualReview: result.actualReviewQueue,
    reviewMatch: result.reviewQueueMatched,
    maxScore: result.maxScore.toFixed(3),
    categories: result.matchedCategories.join(", "),
  })));
  console.log(`Action accuracy: ${(report.actionAccuracy * 100).toFixed(1)}%`);
  console.log(
    `Risk-signal accuracy: ${(report.riskSignalAccuracy * 100).toFixed(1)}%`,
  );
  console.log(
    `Review-queue accuracy: ${(report.reviewQueueAccuracy * 100).toFixed(1)}%`,
  );
  if (report.falseAllowCaseIds.length > 0) {
    console.warn(`False allows: ${report.falseAllowCaseIds.join(", ")}`);
  }
  if (report.unexpectedModerationCaseIds.length > 0) {
    console.warn(
      `Unexpected moderation: ${report.unexpectedModerationCaseIds.join(", ")}`,
    );
  }
  if (report.missedReviewQueueCaseIds.length > 0) {
    console.warn(
      `Missed review queues: ${report.missedReviewQueueCaseIds.join(", ")}`,
    );
  }
}

async function main(): Promise<void> {
  const args = parseArgs(process.argv.slice(2));
  const apiKey = process.env.OPENAI_API_KEY?.trim();
  if (apiKey == null || apiKey.length === 0) {
    throw new Error("OPENAI_API_KEY must be set.\n\n" + usage());
  }
  const dataset = parseModerationEvaluationDataset(
    JSON.parse(await readFile(args.datasetPath, "utf8")) as unknown,
  );
  const results = [];
  for (const evaluationCase of dataset.cases) {
    const response = await requestModeration(evaluationCase.content, apiKey);
    results.push(evaluateModerationCase(
      evaluationCase,
      normalizeOpenAiModeration(response, evaluationCase.content),
    ));
  }
  const report = buildModerationEvaluationReport(results);
  printReport(report);
  if (args.outputPath != null) {
    await writeFile(args.outputPath, `${JSON.stringify(report, null, 2)}\n`);
    console.log(`Wrote JSON report to ${args.outputPath}`);
  }
  if (args.failOnMismatch && (report.actionAccuracy !== 1 ||
    report.riskSignalAccuracy !== 1 || report.reviewQueueAccuracy !== 1)) {
    process.exitCode = 1;
  }
}

main().catch((error: unknown) => {
  console.error(error);
  process.exitCode = 1;
});
