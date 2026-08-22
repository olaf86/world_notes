/* eslint-disable require-jsdoc, valid-jsdoc */

import {REGION} from "./constants";
import {
  canMaintainNote,
  isActiveNoteForAdministration,
  isNoteMaintainer,
} from "./noteMaintenance";
import {HttpsError, onCall} from "./platform/worldCallable";
import {hasUserBlockBetween} from "./userBlocks";

/** Removes one ordinary password-derived private-note access grant. */
export const revokeNoteAccess = onCall<{
  placeId?: unknown;
  userId?: unknown;
}>(
  {enforceAppCheck: true, region: REGION},
  async (request, world) => {
    const actorUid = request.auth?.uid;
    if (!actorUid) {
      throw new HttpsError("unauthenticated", "Sign in required.");
    }
    const placeId = requireValue(request.data?.placeId, "placeId");
    const userId = requireValue(request.data?.userId, "userId");
    const placeRef = world.firestore.collection("places").doc(placeId);
    const actorAdministratorRef = placeRef
      .collection("administrators")
      .doc(actorUid);
    const targetAdministratorRef = placeRef
      .collection("administrators")
      .doc(userId);
    const [place, actorAdministrator, targetAdministrator] = await Promise.all([
      placeRef.get(),
      actorAdministratorRef.get(),
      targetAdministratorRef.get(),
    ]);
    if (!isActiveNoteForAdministration(place, Date.now())) {
      throw new HttpsError("not-found", "Note not found.");
    }
    if (!canMaintainNote(place, actorAdministrator, actorUid)) {
      throw new HttpsError(
        "permission-denied",
        "Only a note administrator can remove access.",
      );
    }
    const creatorUid = place.get("createdByUserId");
    if (typeof creatorUid !== "string" ||
        await hasUserBlockBetween(
          world.firestore,
          actorUid,
          creatorUid,
        )) {
      throw new HttpsError(
        "permission-denied",
        "You cannot access this note.",
        {reason: "user_blocked"},
      );
    }
    if (isNoteMaintainer(place, targetAdministrator, userId)) {
      throw new HttpsError(
        "failed-precondition",
        "Remove administrator authority before ordinary access.",
      );
    }
    await placeRef.collection("members").doc(userId).delete();
    return {ok: true};
  },
);

function requireValue(value: unknown, field: string): string {
  if (typeof value !== "string" || value.length === 0 ||
      value.length > 256 || value.includes("/") || /\s/.test(value)) {
    throw new HttpsError("invalid-argument", `${field} is invalid.`);
  }
  return value;
}
