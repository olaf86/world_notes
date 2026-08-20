/* eslint-disable require-jsdoc, valid-jsdoc */

import {getAuth} from "firebase-admin/auth";
import {
  DocumentSnapshot,
  FieldValue,
  Firestore,
  Timestamp,
  Transaction,
} from "firebase-admin/firestore";

import {
  assertAccountSafetyAllows,
  assertAccountSafetyPreflight,
} from "./accountSafety";
import {REGION} from "./constants";
import {
  isNoteAdministratorInvitationExpired,
  newNoteAdministratorInvitationData,
  newNoteAdministratorInvitationNonce,
  NOTE_ADMINISTRATOR_AUDIT_RETENTION_MILLIS,
  NOTE_ADMINISTRATOR_INVITE_SIGNING_KEY,
  NOTE_ADMINISTRATOR_INVITE_OPERATION_RESULT,
  NOTE_ADMINISTRATOR_INVITE_STATUS,
  NOTE_ADMINISTRATOR_MAX_ACTIVE,
  NOTE_ADMINISTRATOR_MAX_PENDING_INVITES,
  NoteAdministratorInvitationData,
  noteAdministratorInvitationId,
  parseNoteAdministratorInvitation,
  signNoteAdministratorInvitationToken,
  terminalNoteAdministratorInvitation,
  verifyNoteAdministratorInvitationToken,
} from "./noteAdministratorInvitations";
import {
  enqueueNoteAdministratorInvitationExpiration,
} from "./noteAdministratorInviteCleanup";
import {
  enqueueNoteAdministratorInviteNotification,
} from "./noteAdministratorInviteNotifications";
import {
  isActiveNoteForAdministration,
  isNoteCreator,
  isNoteMaintainer,
} from "./noteMaintenance";
import {HttpsError, onCall} from "./platform/worldCallable";
import {WORLD_REGISTRY} from "./platform/worldRegistry";
import {hasUserBlockBetweenInTransaction} from "./userBlocks";

interface CreateInvitationData {
  placeId?: unknown;
  targetUid?: unknown;
}

interface InvitationTokenData {
  token?: unknown;
}

interface RevokeInvitationData {
  placeId?: unknown;
  targetUid?: unknown;
}

interface RemoveAdministratorData {
  placeId?: unknown;
  targetUid?: unknown;
}

interface AdministratorAccessData {
  placeId?: unknown;
}

type AdministratorInvitationAcceptanceResult =
  | Readonly<{
    status: typeof NOTE_ADMINISTRATOR_INVITE_STATUS.accepted;
    placeId: string;
    alreadyAccepted: boolean;
  }>
  | Readonly<{
    status: typeof NOTE_ADMINISTRATOR_INVITE_STATUS.expired;
  }>;

/** Creates or returns the sole pending invitation for one target user. */
export const createNoteAdministratorInvitation =
  onCall<CreateInvitationData>(
    {
      enforceAppCheck: true,
      region: REGION,
      secrets: [NOTE_ADMINISTRATOR_INVITE_SIGNING_KEY],
    },
    async (request, world) => {
      const actorUid = requireAuthenticatedUid(request.auth?.uid);
      const placeId = requireValue(request.data?.placeId, "placeId");
      const targetUid = requireValue(request.data?.targetUid, "targetUid");
      if (actorUid === targetUid) {
        throw new HttpsError(
          "invalid-argument",
          "You cannot invite yourself as an administrator.",
        );
      }
      await assertAccountSafetyPreflight(
        world.firestore,
        actorUid,
        "participation",
        Timestamp.now(),
      );
      await requireExistingAuthUser(targetUid);

      const invitationRef = invitationReference(
        world.firestore,
        placeId,
        targetUid,
      );
      const placeRef = world.firestore.collection("places").doc(placeId);
      const auditRef = placeRef.collection("administratorAudits").doc();
      const candidateNonce = newNoteAdministratorInvitationNonce();
      const now = Timestamp.now();
      const invitation = await world.firestore.runTransaction(
        async (transaction) => {
          const [place, currentSnapshot, blocked] = await Promise.all([
            transaction.get(placeRef),
            transaction.get(invitationRef),
            hasUserBlockBetweenInTransaction(
              transaction,
              world.firestore,
              actorUid,
              targetUid,
            ),
            assertAccountSafetyAllows(
              transaction,
              world.firestore,
              actorUid,
              "participation",
              now,
            ),
            assertAccountSafetyAllows(
              transaction,
              world.firestore,
              targetUid,
              "participation",
              now,
            ),
          ]);
          requireActiveNote(place, actorUid, now);
          if (!isNoteMaintainer(place, actorUid)) {
            throw new HttpsError(
              "permission-denied",
              "Only a note administrator can invite another administrator.",
            );
          }
          if (blocked) {
            throw new HttpsError(
              "failed-precondition",
              "This user cannot be invited as an administrator.",
              {reason: "user_blocked"},
            );
          }
          const maintainers = requireMaintainerIds(place);
          if (maintainers.includes(targetUid) ||
              isNoteCreator(place, targetUid)) {
            throw new HttpsError(
              "already-exists",
              "This user is already a note administrator.",
            );
          }
          const current = currentSnapshot.exists ?
            parseNoteAdministratorInvitation(
              currentSnapshot.data(),
              invitationRef.id,
            ) : null;
          if (current !== null &&
              current.status === NOTE_ADMINISTRATOR_INVITE_STATUS.pending &&
              !isNoteAdministratorInvitationExpired(current, now)) {
            return current;
          }

          const pendingCount = requireCount(
            place,
            "pendingAdministratorInviteCount",
            NOTE_ADMINISTRATOR_MAX_PENDING_INVITES,
          );
          const replacesExpiredPending = current !== null &&
            current.status === NOTE_ADMINISTRATOR_INVITE_STATUS.pending;
          if (!replacesExpiredPending &&
              pendingCount >= NOTE_ADMINISTRATOR_MAX_PENDING_INVITES) {
            throw new HttpsError(
              "resource-exhausted",
              "This note has reached its pending administrator invite limit.",
            );
          }
          const next = newNoteAdministratorInvitationData({
            placeId,
            targetUid,
            invitedByUid: actorUid,
            nonce: candidateNonce,
            revision: (current?.revision ?? 0) + 1,
          }, now);
          transaction.set(invitationRef, {...next});
          enqueueNoteAdministratorInvitationExpiration(
            transaction,
            world.firestore,
            world.worldId,
            next,
          );
          enqueueNoteAdministratorInviteNotification(
            transaction,
            world.firestore,
            {
              sourceWorld: world.worldId,
              placeId,
              targetUid,
              invitationRevision: next.revision,
              token: tokenForInvitation(world.worldId, next),
              createdAt: now,
            },
          );
          if (!replacesExpiredPending) {
            transaction.update(placeRef, {
              pendingAdministratorInviteCount: pendingCount + 1,
            });
          }
          createAdministratorAudit(transaction, auditRef, {
            action: current === null ?
              "invitationCreated" : "invitationReissued",
            actorUid,
            targetUid,
            inviteId: next.inviteId,
            invitationRevision: next.revision,
            reason: current?.status ?? null,
            now,
          });
          return next;
        },
      );
      return {
        token: tokenForInvitation(world.worldId, invitation),
        placeId,
        targetUid,
        expiresAtMillis: invitation.expiresAt.toMillis(),
      };
    },
  );

/** Previews one target-bound invite without requiring world readiness. */
export const previewNoteAdministratorInvitation =
  onCall<InvitationTokenData>(
    {
      enforceAppCheck: true,
      region: REGION,
      requireAccountReady: false,
      secrets: [NOTE_ADMINISTRATOR_INVITE_SIGNING_KEY],
    },
    async (request, world) => {
      const uid = requireAuthenticatedUid(request.auth?.uid);
      const token = verifiedToken(request.data?.token, world.worldId);
      const invitationSnapshot = await world.firestore
        .collection("noteAdministratorInvitations")
        .doc(token.inviteId)
        .get();
      const invitation = requireInvitationForToken(
        invitationSnapshot,
        token,
        uid,
      );
      const [place, homeAssignment] = await Promise.all([
        world.firestore.collection("places").doc(invitation.placeId).get(),
        world.firestore.collection("userHomes").doc(uid).get(),
      ]);
      requireActiveNote(place, invitation.invitedByUid, Timestamp.now());
      const now = Timestamp.now();
      const status = invitation.status ===
          NOTE_ADMINISTRATOR_INVITE_STATUS.pending &&
          isNoteAdministratorInvitationExpired(invitation, now) ?
        NOTE_ADMINISTRATOR_INVITE_STATUS.expired : invitation.status;
      const worldReady = isAccountReadyInWorld(homeAssignment);
      return {
        placeId: invitation.placeId,
        title: place.get("title"),
        invitedByUid: invitation.invitedByUid,
        status,
        expiresAtMillis: invitation.expiresAt.toMillis(),
        worldReady,
        canAccept: status === NOTE_ADMINISTRATOR_INVITE_STATUS.pending &&
          worldReady,
      };
    },
  );

/** Accepts a valid invitation and grants administrator authority atomically. */
export const acceptNoteAdministratorInvitation =
  onCall<InvitationTokenData>(
    {
      enforceAppCheck: true,
      region: REGION,
      secrets: [NOTE_ADMINISTRATOR_INVITE_SIGNING_KEY],
    },
    async (request, world) => {
      const uid = requireAuthenticatedUid(request.auth?.uid);
      const token = verifiedToken(request.data?.token, world.worldId);
      const invitationRef = world.firestore
        .collection("noteAdministratorInvitations")
        .doc(token.inviteId);
      const now = Timestamp.now();
      const acceptanceResult = await world.firestore.runTransaction(
        async (transaction):
          Promise<AdministratorInvitationAcceptanceResult> => {
          const invitationSnapshot = await transaction.get(invitationRef);
          const invitation = requireInvitationForToken(
            invitationSnapshot,
            token,
            uid,
          );
          const placeRef = world.firestore
            .collection("places")
            .doc(invitation.placeId);
          const administratorRef = placeRef
            .collection("administrators")
            .doc(uid);
          const auditRef = placeRef.collection("administratorAudits").doc();
          const [place, administrator, blocked] = await Promise.all([
            transaction.get(placeRef),
            transaction.get(administratorRef),
            hasUserBlockBetweenInTransaction(
              transaction,
              world.firestore,
              uid,
              invitation.invitedByUid,
            ),
            assertAccountSafetyAllows(
              transaction,
              world.firestore,
              uid,
              "participation",
              now,
            ),
          ]);
          requireActiveNote(place, invitation.invitedByUid, now);
          const creatorUid = requireCreatorUid(place);
          const creatorBlocked = creatorUid === invitation.invitedByUid ?
            blocked : await hasUserBlockBetweenInTransaction(
              transaction,
              world.firestore,
              uid,
              creatorUid,
            );
          const maintainers = requireMaintainerIds(place);
          if (invitation.status ===
              NOTE_ADMINISTRATOR_INVITE_STATUS.accepted &&
              administrator.exists && maintainers.includes(uid)) {
            return {
              status: NOTE_ADMINISTRATOR_INVITE_STATUS.accepted,
              placeId: invitation.placeId,
              alreadyAccepted: true,
            };
          }
          if (invitation.status !==
              NOTE_ADMINISTRATOR_INVITE_STATUS.pending) {
            throw invalidInvitation();
          }
          const pendingCount = requireCount(
            place,
            "pendingAdministratorInviteCount",
            NOTE_ADMINISTRATOR_MAX_PENDING_INVITES,
          );
          if (pendingCount <= 0) {
            throw new Error("Administrator invitation counter is invalid.");
          }
          if (isNoteAdministratorInvitationExpired(invitation, now)) {
            transaction.set(invitationRef, {
              ...terminalNoteAdministratorInvitation(
                invitation,
                NOTE_ADMINISTRATOR_INVITE_STATUS.expired,
                now,
              ),
            });
            transaction.update(placeRef, {
              pendingAdministratorInviteCount: pendingCount - 1,
            });
            createAdministratorAudit(transaction, auditRef, {
              action: "invitationExpired",
              actorUid: uid,
              targetUid: uid,
              inviteId: invitation.inviteId,
              invitationRevision: invitation.revision,
              reason: "acceptAfterExpiry",
              now,
            });
            return {status: NOTE_ADMINISTRATOR_INVITE_STATUS.expired};
          }
          if (blocked || creatorBlocked) {
            throw new HttpsError(
              "failed-precondition",
              "This invitation cannot be accepted.",
              {reason: "user_blocked"},
            );
          }
          if (administrator.exists || maintainers.includes(uid) ||
              isNoteCreator(place, uid)) {
            throw new Error("Administrator authority already exists.");
          }
          const administratorCount = requireCount(
            place,
            "administratorCount",
            NOTE_ADMINISTRATOR_MAX_ACTIVE,
          );
          if (administratorCount >= NOTE_ADMINISTRATOR_MAX_ACTIVE) {
            throw new HttpsError(
              "resource-exhausted",
              "This note has reached its administrator limit.",
            );
          }
          transaction.update(placeRef, {
            maintainerIds: FieldValue.arrayUnion(uid),
            administratorCount: administratorCount + 1,
            pendingAdministratorInviteCount: pendingCount - 1,
          });
          transaction.create(administratorRef, {
            userId: uid,
            invitedByUid: invitation.invitedByUid,
            inviteId: invitation.inviteId,
            grantedAt: now,
          });
          transaction.set(invitationRef, {
            ...terminalNoteAdministratorInvitation(
              invitation,
              NOTE_ADMINISTRATOR_INVITE_STATUS.accepted,
              now,
            ),
          });
          createAdministratorAudit(transaction, auditRef, {
            action: "invitationAccepted",
            actorUid: uid,
            targetUid: uid,
            inviteId: invitation.inviteId,
            invitationRevision: invitation.revision,
            reason: null,
            now,
          });
          return {
            status: NOTE_ADMINISTRATOR_INVITE_STATUS.accepted,
            placeId: invitation.placeId,
            alreadyAccepted: false,
          };
        },
      );
      if (acceptanceResult.status ===
          NOTE_ADMINISTRATOR_INVITE_STATUS.expired) {
        throw new HttpsError(
          "deadline-exceeded",
          "This administrator invitation has expired.",
        );
      }
      return acceptanceResult;
    },
  );

/** Revokes the current pending invitation for one target user. */
export const revokeNoteAdministratorInvitation =
  onCall<RevokeInvitationData>(
    {enforceAppCheck: true, region: REGION},
    async (request, world) => {
      const actorUid = requireAuthenticatedUid(request.auth?.uid);
      const placeId = requireValue(request.data?.placeId, "placeId");
      const targetUid = requireValue(request.data?.targetUid, "targetUid");
      const invitationRef = invitationReference(
        world.firestore,
        placeId,
        targetUid,
      );
      const placeRef = world.firestore.collection("places").doc(placeId);
      const auditRef = placeRef.collection("administratorAudits").doc();
      const now = Timestamp.now();
      const status = await world.firestore.runTransaction(
        async (transaction) => {
          const [place, invitationSnapshot] = await Promise.all([
            transaction.get(placeRef),
            transaction.get(invitationRef),
          ]);
          requireActiveNote(place, actorUid, now);
          if (!isNoteMaintainer(place, actorUid)) {
            throw new HttpsError(
              "permission-denied",
              "Only a note administrator can revoke this invitation.",
            );
          }
          if (!invitationSnapshot.exists) {
            return NOTE_ADMINISTRATOR_INVITE_OPERATION_RESULT.missing;
          }
          const invitation = parseNoteAdministratorInvitation(
            invitationSnapshot.data(),
            invitationRef.id,
          );
          if (invitation.placeId !== placeId ||
              invitation.targetUid !== targetUid) {
            throw new Error("Administrator invitation route is invalid.");
          }
          if (invitation.status !==
              NOTE_ADMINISTRATOR_INVITE_STATUS.pending) {
            return invitation.status;
          }
          const pendingCount = requireCount(
            place,
            "pendingAdministratorInviteCount",
            NOTE_ADMINISTRATOR_MAX_PENDING_INVITES,
          );
          if (pendingCount <= 0) {
            throw new Error("Administrator invitation counter is invalid.");
          }
          const terminalStatus = isNoteAdministratorInvitationExpired(
            invitation,
            now,
          ) ? NOTE_ADMINISTRATOR_INVITE_STATUS.expired :
            NOTE_ADMINISTRATOR_INVITE_STATUS.revoked;
          transaction.set(invitationRef, {
            ...terminalNoteAdministratorInvitation(
              invitation,
              terminalStatus,
              now,
            ),
          });
          transaction.update(placeRef, {
            pendingAdministratorInviteCount: pendingCount - 1,
          });
          createAdministratorAudit(transaction, auditRef, {
            action: terminalStatus ===
                NOTE_ADMINISTRATOR_INVITE_STATUS.expired ?
              "invitationExpired" : "invitationRevoked",
            actorUid,
            targetUid,
            inviteId: invitation.inviteId,
            invitationRevision: invitation.revision,
            reason: null,
            now,
          });
          return terminalStatus;
        },
      );
      return {status};
    },
  );

/** Removes a delegated administrator or lets one resign. */
export const removeNoteAdministrator = onCall<RemoveAdministratorData>(
  {enforceAppCheck: true, region: REGION},
  async (request, world) => {
    const actorUid = requireAuthenticatedUid(request.auth?.uid);
    const placeId = requireValue(request.data?.placeId, "placeId");
    const targetUid = requireValue(request.data?.targetUid, "targetUid");
    const placeRef = world.firestore.collection("places").doc(placeId);
    const administratorRef = placeRef
      .collection("administrators")
      .doc(targetUid);
    const auditRef = placeRef.collection("administratorAudits").doc();
    const now = Timestamp.now();
    await world.firestore.runTransaction(async (transaction) => {
      const [place, administrator] = await Promise.all([
        transaction.get(placeRef),
        transaction.get(administratorRef),
      ]);
      requireActiveNote(place, actorUid, now);
      if (!isNoteMaintainer(place, actorUid)) {
        throw new HttpsError(
          "permission-denied",
          "Only a note administrator can remove administrator access.",
        );
      }
      if (isNoteCreator(place, targetUid)) {
        throw new HttpsError(
          "failed-precondition",
          "The note creator cannot be removed.",
        );
      }
      const maintainers = requireMaintainerIds(place);
      if (!administrator.exists || !maintainers.includes(targetUid)) {
        return;
      }
      const administratorCount = requireCount(
        place,
        "administratorCount",
        NOTE_ADMINISTRATOR_MAX_ACTIVE,
      );
      if (administratorCount <= 0) {
        throw new Error("Note administrator count is invalid.");
      }
      transaction.update(placeRef, {
        maintainerIds: FieldValue.arrayRemove(targetUid),
        administratorCount: administratorCount - 1,
      });
      transaction.delete(administratorRef);
      createAdministratorAudit(transaction, auditRef, {
        action: actorUid === targetUid ?
          "administratorResigned" : "administratorRemoved",
        actorUid,
        targetUid,
        inviteId: administrator.get("inviteId") ?? null,
        invitationRevision: null,
        reason: actorUid === targetUid ?
          "selfResignation" : "administratorRemoval",
        now,
      });
    });
    return {ok: true};
  },
);

/** Lists current administrators and pending invitations in one note world. */
export const getNoteAdministratorAccess = onCall<AdministratorAccessData>(
  {enforceAppCheck: true, region: REGION},
  async (request, world) => {
    const actorUid = requireAuthenticatedUid(request.auth?.uid);
    const placeId = requireValue(request.data?.placeId, "placeId");
    const placeRef = world.firestore.collection("places").doc(placeId);
    const place = await placeRef.get();
    requireActiveNote(place, actorUid, Timestamp.now());
    if (!isNoteMaintainer(place, actorUid)) {
      throw new HttpsError(
        "permission-denied",
        "Only a note administrator can view administrator access.",
      );
    }
    const maintainers = requireMaintainerIds(place);
    const delegated = await placeRef.collection("administrators")
      .limit(NOTE_ADMINISTRATOR_MAX_ACTIVE + 1)
      .get();
    if (delegated.size > NOTE_ADMINISTRATOR_MAX_ACTIVE) {
      throw new Error("Note administrator limit is invalid.");
    }
    const pending = await world.firestore
      .collection("noteAdministratorInvitations")
      .where("placeId", "==", placeId)
      .where("status", "==", NOTE_ADMINISTRATOR_INVITE_STATUS.pending)
      .limit(NOTE_ADMINISTRATOR_MAX_PENDING_INVITES + 1)
      .get();
    if (pending.size > NOTE_ADMINISTRATOR_MAX_PENDING_INVITES) {
      throw new Error("Administrator invitation limit is invalid.");
    }
    const profileUids = [...new Set([
      ...maintainers,
      ...pending.docs.map((document) => document.get("targetUid"))
        .filter((uid): uid is string => typeof uid === "string"),
    ])];
    const profiles = profileUids.length === 0 ? [] :
      await world.firestore.getAll(...profileUids.map((uid) =>
        world.firestore.collection("publicProfiles").doc(uid)));
    const profileData = new Map(profiles.map((profile) => [
      profile.id,
      {
        displayName: profile.get("displayName") ?? null,
        photoUrl: profile.get("photoUrl") ?? null,
      },
    ]));
    const grants = new Map(delegated.docs.map((document) => [
      document.id,
      document,
    ]));
    const now = Timestamp.now();
    return {
      creatorUid: place.get("createdByUserId"),
      administrators: maintainers.map((uid) => ({
        userId: uid,
        isCreator: isNoteCreator(place, uid),
        invitedByUid: grants.get(uid)?.get("invitedByUid") ?? null,
        grantedAtMillis: timestampMillis(grants.get(uid)?.get("grantedAt")),
        ...profileData.get(uid),
      })),
      pendingInvitations: pending.docs.map((document) => {
        const invitation = parseNoteAdministratorInvitation(
          document.data(),
          document.id,
        );
        return {
          targetUid: invitation.targetUid,
          invitedByUid: invitation.invitedByUid,
          revision: invitation.revision,
          expiresAtMillis: invitation.expiresAt.toMillis(),
          expired: isNoteAdministratorInvitationExpired(invitation, now),
          ...profileData.get(invitation.targetUid),
        };
      }),
    };
  },
);

function invitationReference(
  firestore: Firestore,
  placeId: string,
  targetUid: string,
) {
  return firestore.collection("noteAdministratorInvitations")
    .doc(noteAdministratorInvitationId(placeId, targetUid));
}

function tokenForInvitation(
  worldId: string,
  invitation: NoteAdministratorInvitationData,
): string {
  return signNoteAdministratorInvitationToken({
    version: 1,
    worldId,
    inviteId: invitation.inviteId,
    revision: invitation.revision,
    nonce: invitation.nonce,
  }, NOTE_ADMINISTRATOR_INVITE_SIGNING_KEY.value());
}

function verifiedToken(value: unknown, expectedWorld: string) {
  try {
    const token = verifyNoteAdministratorInvitationToken(
      value,
      NOTE_ADMINISTRATOR_INVITE_SIGNING_KEY.value(),
    );
    if (token.worldId !== expectedWorld) throw new Error("Wrong world.");
    return token;
  } catch {
    throw invalidInvitation();
  }
}

function requireInvitationForToken(
  snapshot: DocumentSnapshot,
  token: Readonly<{
    inviteId: string;
    revision: number;
    nonce: string;
  }>,
  targetUid: string,
): NoteAdministratorInvitationData {
  try {
    const invitation = parseNoteAdministratorInvitation(
      snapshot.data(),
      token.inviteId,
    );
    if (!snapshot.exists || invitation.targetUid !== targetUid ||
        invitation.revision !== token.revision ||
        invitation.nonce !== token.nonce) {
      throw new Error("Invitation binding mismatch.");
    }
    return invitation;
  } catch {
    throw invalidInvitation();
  }
}

function requireActiveNote(
  place: DocumentSnapshot,
  actorUid: string,
  now: Timestamp,
): void {
  if (!isActiveNoteForAdministration(place, now.toMillis())) {
    throw new HttpsError("not-found", "Note not found.");
  }
  const creatorUid = place.get("createdByUserId");
  if (typeof creatorUid !== "string" || creatorUid.length === 0 ||
      typeof actorUid !== "string" || actorUid.length === 0) {
    throw new Error("Note authority is invalid.");
  }
}

function requireMaintainerIds(place: DocumentSnapshot): string[] {
  const value = place.get("maintainerIds");
  const creatorUid = requireCreatorUid(place);
  if (!Array.isArray(value) || value.length === 0 ||
      value.length > NOTE_ADMINISTRATOR_MAX_ACTIVE + 1 ||
      value.some((uid) => typeof uid !== "string" || uid.length === 0) ||
      new Set(value).size !== value.length ||
      !value.includes(creatorUid)) {
    throw new Error("Note administrator authority is invalid.");
  }
  return value as string[];
}

function requireCreatorUid(place: DocumentSnapshot): string {
  const value = place.get("createdByUserId");
  if (typeof value !== "string" || value.length === 0) {
    throw new Error("Note creator authority is invalid.");
  }
  return value;
}

function requireCount(
  place: DocumentSnapshot,
  field: string,
  maximum: number,
): number {
  const value = place.get(field);
  if (typeof value !== "number" || !Number.isSafeInteger(value) ||
      value < 0 || value > maximum) {
    throw new Error(`Note ${field} is invalid.`);
  }
  return value;
}

function timestampMillis(value: unknown): number | null {
  return value instanceof Timestamp ? value.toMillis() : null;
}

function isAccountReadyInWorld(homeAssignment: DocumentSnapshot): boolean {
  const homeWorld = homeAssignment.get("world");
  const epoch = homeAssignment.get("epoch");
  if (!homeAssignment.exists || typeof homeWorld !== "string" ||
      !Number.isSafeInteger(epoch) || (epoch as number) <= 0) {
    return false;
  }
  try {
    WORLD_REGISTRY.requireWorld(homeWorld);
    return true;
  } catch {
    return false;
  }
}

function createAdministratorAudit(
  transaction: Transaction,
  reference: FirebaseFirestore.DocumentReference,
  input: Readonly<{
    action: string;
    actorUid: string;
    targetUid: string;
    inviteId: unknown;
    invitationRevision: number | null;
    reason: string | null;
    now: Timestamp;
  }>,
): void {
  transaction.create(reference, {
    action: input.action,
    actorUid: input.actorUid,
    targetUid: input.targetUid,
    inviteId: input.inviteId,
    invitationRevision: input.invitationRevision,
    reason: input.reason,
    createdAt: input.now,
    expireAt: Timestamp.fromMillis(
      input.now.toMillis() + NOTE_ADMINISTRATOR_AUDIT_RETENTION_MILLIS,
    ),
  });
}

async function requireExistingAuthUser(uid: string): Promise<void> {
  try {
    await getAuth().getUser(uid);
  } catch (error) {
    if (typeof error === "object" && error !== null && "code" in error &&
        (error as {code: unknown}).code === "auth/user-not-found") {
      throw new HttpsError("not-found", "User not found.");
    }
    throw error;
  }
}

function requireAuthenticatedUid(value: unknown): string {
  if (typeof value !== "string" || value.length === 0) {
    throw new HttpsError("unauthenticated", "Sign in required.");
  }
  return value;
}

function requireValue(value: unknown, field: string): string {
  if (typeof value !== "string" || value.length === 0 ||
      value.length > 256 || value.includes("/") || /\s/.test(value)) {
    throw new HttpsError("invalid-argument", `${field} is invalid.`);
  }
  return value;
}

function invalidInvitation(): HttpsError {
  return new HttpsError(
    "not-found",
    "This administrator invitation is invalid or no longer available.",
  );
}
