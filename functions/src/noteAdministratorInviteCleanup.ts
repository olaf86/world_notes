/* eslint-disable require-jsdoc, valid-jsdoc */

import {
  DocumentSnapshot,
  Firestore,
  Timestamp,
  Transaction,
} from "firebase-admin/firestore";

import {
  cleanupJobId,
  cleanupJobPath,
  CleanupJobHandler,
  newCleanupJobData,
  NewCleanupJobInput,
} from "./cleanupJobs";
import {
  isNoteAdministratorInvitationExpired,
  NOTE_ADMINISTRATOR_AUDIT_RETENTION_MILLIS,
  NOTE_ADMINISTRATOR_INVITE_STATUS,
  NOTE_ADMINISTRATOR_MAX_PENDING_INVITES,
  NoteAdministratorInvitationData,
  parseNoteAdministratorInvitation,
  terminalNoteAdministratorInvitation,
} from "./noteAdministratorInvitations";

export const EXPIRE_NOTE_ADMINISTRATOR_INVITATION_JOB =
  "expireNoteAdministratorInvitation";
export const REVOKE_ARCHIVED_NOTE_ADMINISTRATOR_INVITATIONS_JOB =
  "revokeArchivedNoteAdministratorInvitations";

/** Adds a revision-bound expiration intent beside a pending invitation. */
export function enqueueNoteAdministratorInvitationExpiration(
  transaction: Transaction,
  firestore: FirebaseFirestore.Firestore,
  world: string,
  invitation: NoteAdministratorInvitationData,
): void {
  const sourceOperationId =
    `administratorInvite:${invitation.inviteId}:${invitation.revision}`;
  const input: NewCleanupJobInput = {
    sourceOperationId,
    entityType: "noteAdministratorInvitation",
    entityId: invitation.inviteId,
    revision: invitation.revision,
    world,
    queue: "firestore",
    jobType: EXPIRE_NOTE_ADMINISTRATOR_INVITATION_JOB,
    partition: String(invitation.revision),
  };
  const jobId = cleanupJobId(input);
  transaction.create(
    firestore.doc(cleanupJobPath("firestore", jobId)),
    {
      ...newCleanupJobData(input, invitation.createdAt),
      nextAttemptAt: invitation.expiresAt,
    },
  );
}

/** Adds one durable revocation intent to an archive transaction. */
export function enqueueArchivedNoteAdministratorInvitationRevocation(
  transaction: Transaction,
  firestore: Firestore,
  world: string,
  placeId: string,
  createdAt: Timestamp,
): void {
  const input: NewCleanupJobInput = {
    sourceOperationId: `archiveNote:${placeId}`,
    entityType: "note",
    entityId: placeId,
    revision: 1,
    world,
    queue: "firestore",
    jobType: REVOKE_ARCHIVED_NOTE_ADMINISTRATOR_INVITATIONS_JOB,
  };
  const jobId = cleanupJobId(input);
  transaction.create(
    firestore.doc(cleanupJobPath("firestore", jobId)),
    {...newCleanupJobData(input, createdAt)},
  );
}

/** Expires one still-current invitation and releases its exact pending slot. */
export const noteAdministratorInvitationExpirationHandler:
CleanupJobHandler = {
  queue: "firestore",
  jobType: EXPIRE_NOTE_ADMINISTRATOR_INVITATION_JOB,
  processBatch: async ({firestore, job}) => {
    const invitationRef = firestore
      .collection("noteAdministratorInvitations")
      .doc(job.entityId);
    await firestore.runTransaction(async (transaction) => {
      const invitationSnapshot = await transaction.get(invitationRef);
      if (!invitationSnapshot.exists) return;
      const invitation = parseNoteAdministratorInvitation(
        invitationSnapshot.data(),
        invitationRef.id,
      );
      if (invitation.revision !== job.revision ||
          invitation.status !== NOTE_ADMINISTRATOR_INVITE_STATUS.pending) {
        return;
      }
      const now = Timestamp.now();
      if (!isNoteAdministratorInvitationExpired(invitation, now)) {
        throw new Error("Administrator invitation expiration ran early.");
      }
      const placeRef = firestore.collection("places").doc(invitation.placeId);
      const place = await transaction.get(placeRef);
      const pendingCount = pendingInvitationCount(place);
      if (pendingCount <= 0) {
        throw new Error("Administrator invitation counter is invalid.");
      }
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
      transaction.create(
        placeRef.collection("administratorAudits").doc(),
        {
          action: "invitationExpired",
          actorUid: null,
          targetUid: invitation.targetUid,
          inviteId: invitation.inviteId,
          invitationRevision: invitation.revision,
          reason: "deadlineReached",
          createdAt: now,
          expireAt: Timestamp.fromMillis(
            now.toMillis() + NOTE_ADMINISTRATOR_AUDIT_RETENTION_MILLIS,
          ),
        },
      );
    });
    return {complete: true};
  },
};

/** Revokes every pending invitation after its note becomes terminal. */
export const archivedNoteAdministratorInvitationRevocationHandler:
CleanupJobHandler = {
  queue: "firestore",
  jobType: REVOKE_ARCHIVED_NOTE_ADMINISTRATOR_INVITATIONS_JOB,
  processBatch: async ({firestore, job}) => {
    const placeRef = firestore.collection("places").doc(job.entityId);
    const pendingQuery = firestore
      .collection("noteAdministratorInvitations")
      .where("placeId", "==", job.entityId)
      .where("status", "==", NOTE_ADMINISTRATOR_INVITE_STATUS.pending)
      .limit(NOTE_ADMINISTRATOR_MAX_PENDING_INVITES + 1);
    await firestore.runTransaction(async (transaction) => {
      const [place, pending] = await Promise.all([
        transaction.get(placeRef),
        transaction.get(pendingQuery),
      ]);
      if (!place.exists || place.get("isArchived") !== true) {
        throw new Error("Invitation revocation requires an archived note.");
      }
      if (pending.size > NOTE_ADMINISTRATOR_MAX_PENDING_INVITES) {
        throw new Error("Administrator invitation limit is invalid.");
      }
      const pendingCount = pendingInvitationCount(place);
      if (pendingCount !== pending.size) {
        throw new Error("Administrator invitation counter has drifted.");
      }
      if (pending.empty) return;

      const now = Timestamp.now();
      for (const snapshot of pending.docs) {
        const invitation = parseNoteAdministratorInvitation(
          snapshot.data(),
          snapshot.id,
        );
        transaction.set(snapshot.ref, {
          ...terminalNoteAdministratorInvitation(
            invitation,
            NOTE_ADMINISTRATOR_INVITE_STATUS.revoked,
            now,
          ),
        });
        transaction.create(
          placeRef.collection("administratorAudits").doc(),
          {
            action: "invitationRevoked",
            actorUid: null,
            targetUid: invitation.targetUid,
            inviteId: invitation.inviteId,
            invitationRevision: invitation.revision,
            reason: "noteArchived",
            createdAt: now,
            expireAt: Timestamp.fromMillis(
              now.toMillis() + NOTE_ADMINISTRATOR_AUDIT_RETENTION_MILLIS,
            ),
          },
        );
      }
      transaction.update(placeRef, {
        pendingAdministratorInviteCount: 0,
      });
    });
    return {complete: true};
  },
};

function pendingInvitationCount(place: DocumentSnapshot): number {
  if (!place.exists) {
    throw new Error("Administrator invitation note is missing.");
  }
  const value = place.get("pendingAdministratorInviteCount");
  if (typeof value !== "number" || !Number.isSafeInteger(value) ||
      value < 0 || value > NOTE_ADMINISTRATOR_MAX_PENDING_INVITES) {
    throw new Error("Administrator invitation counter is invalid.");
  }
  return value;
}
