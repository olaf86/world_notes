import {Timestamp} from "firebase-admin/firestore";

import {onCall, HttpsError} from "./platform/worldCallable";
import {
  CURRENT_PRIVACY_POLICY_VERSION,
  CURRENT_SERVICE_TERMS_VERSION,
  legalAcceptanceFields,
  legalAcceptanceFrom,
} from "./legalPolicy";

/** Records the current Terms acceptance in the account's authority world. */
export const acceptServiceTerms = onCall<{
  serviceTermsVersion?: unknown;
  privacyPolicyVersion?: unknown;
  locale?: unknown;
}>(
  {
    auditAction: "account.legal.accept",
    enforceAppCheck: true,
    requireHomeWorld: true,
  },
  async (request, world) => {
    const uid = request.auth?.uid;
    if (uid === undefined) {
      throw new HttpsError("unauthenticated", "Sign in required.");
    }
    const acceptance = legalAcceptanceFrom(request.data);
    if (acceptance === null) {
      throw new HttpsError(
        "failed-precondition",
        "The current legal documents must be acknowledged.",
      );
    }
    const userRef = world.firestore.collection("users").doc(uid);
    await world.firestore.runTransaction(async (transaction) => {
      const user = await transaction.get(userRef);
      if (!user.exists) {
        throw new HttpsError("failed-precondition", "User profile missing.");
      }
      const isCurrent =
        user.get("serviceTermsAcceptedVersion") ===
          CURRENT_SERVICE_TERMS_VERSION &&
        user.get("privacyPolicyAcknowledgedVersion") ===
          CURRENT_PRIVACY_POLICY_VERSION;
      if (isCurrent) return;
      const acceptedAt = Timestamp.now();
      transaction.update(userRef, {
        ...legalAcceptanceFields(acceptance, acceptedAt),
        updatedAt: acceptedAt,
      });
    });
    return {
      serviceTermsVersion: CURRENT_SERVICE_TERMS_VERSION,
      privacyPolicyVersion: CURRENT_PRIVACY_POLICY_VERSION,
    };
  },
);
