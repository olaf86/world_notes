import {HttpsError} from "firebase-functions/v2/https";

import {notificationLocale} from "./noticeTemplateCatalog";

export const CURRENT_SERVICE_TERMS_VERSION = "2026-09-22";
export const CURRENT_PRIVACY_POLICY_VERSION = "2026-09-24";

export interface LegalAcceptanceInput {
  readonly locale: string;
}

/**
 * Validates a client acknowledgement against the server's current documents.
 * Older clients may omit every field during bootstrap; partial or stale
 * acknowledgements are never recorded.
 *
 * @param {object | undefined} data Untrusted callable request data.
 * @param {boolean} optional Whether complete omission is accepted.
 * @return {LegalAcceptanceInput | null} A validated acknowledgement.
 */
export function legalAcceptanceFrom(
  data: object | undefined,
  optional = false,
): LegalAcceptanceInput | null {
  const fields = data as Readonly<Record<string, unknown>> | undefined;
  const termsVersion = fields?.serviceTermsVersion;
  const privacyVersion = fields?.privacyPolicyVersion;
  const rawLocale = fields?.legalAcceptanceLocale ?? fields?.locale;
  if (optional &&
      termsVersion === undefined &&
      privacyVersion === undefined &&
      rawLocale === undefined) {
    return null;
  }
  if (termsVersion !== CURRENT_SERVICE_TERMS_VERSION ||
      privacyVersion !== CURRENT_PRIVACY_POLICY_VERSION) {
    throw new HttpsError(
      "failed-precondition",
      "The current legal documents must be acknowledged.",
    );
  }
  let locale;
  try {
    locale = notificationLocale(rawLocale);
  } catch {
    throw new HttpsError(
      "invalid-argument",
      "A supported legal acceptance locale is required.",
    );
  }
  return {locale};
}

/**
 * Builds the private account fields that prove one explicit acceptance.
 *
 * @param {LegalAcceptanceInput} acceptance Validated acknowledgement data.
 * @param {unknown} acceptedAt Trusted server acceptance time.
 * @return {Readonly<Record<string, unknown>>} Private user fields.
 */
export function legalAcceptanceFields(
  acceptance: LegalAcceptanceInput,
  acceptedAt: unknown,
): Readonly<Record<string, unknown>> {
  return {
    serviceTermsAcceptedVersion: CURRENT_SERVICE_TERMS_VERSION,
    serviceTermsAcceptedAt: acceptedAt,
    privacyPolicyAcknowledgedVersion: CURRENT_PRIVACY_POLICY_VERSION,
    privacyPolicyAcknowledgedAt: acceptedAt,
    legalAcceptanceLocale: acceptance.locale,
  };
}
