/* eslint-disable require-jsdoc */
import {HttpsError} from "firebase-functions/v2/https";
import {
  DocumentSnapshot,
  Timestamp,
} from "firebase-admin/firestore";

export type ReportReasonCode =
  "spam" |
  "harassment" |
  "sexual" |
  "illegal" |
  "other";

const REPORT_REASON_CODES = new Set<ReportReasonCode>([
  "spam",
  "harassment",
  "sexual",
  "illegal",
  "other",
]);

const MAX_REPORT_DOCUMENT_ID_LENGTH = 200;
export const REPORT_COOLDOWN_MILLIS = 30_000;

export function requiredReportDocumentId(
  value: unknown,
  fieldName: string,
): string {
  if (typeof value !== "string" || value.trim().length === 0) {
    throw new HttpsError("invalid-argument", `${fieldName} is required.`);
  }
  const id = value.trim();
  if (id.length > MAX_REPORT_DOCUMENT_ID_LENGTH || id.includes("/")) {
    throw new HttpsError("invalid-argument", `Invalid ${fieldName}.`);
  }
  return id;
}

export function reportReasonCodeOf(value: unknown): ReportReasonCode {
  if (
    typeof value !== "string" ||
    !REPORT_REASON_CODES.has(value as ReportReasonCode)
  ) {
    throw new HttpsError("invalid-argument", "Invalid report reason.");
  }
  return value as ReportReasonCode;
}

export function assertReportCooldown(
  rateLimitSnap: DocumentSnapshot,
  now: Timestamp,
): void {
  if (!rateLimitSnap.exists) return;
  const lastCreatedAt =
    rateLimitSnap.get("lastCreatedAt") as Timestamp | undefined;
  if (
    lastCreatedAt &&
    now.toMillis() - lastCreatedAt.toMillis() < REPORT_COOLDOWN_MILLIS
  ) {
    throw new HttpsError(
      "resource-exhausted",
      "Please wait before submitting another report.",
      {reason: "report_cooldown"},
    );
  }
}
