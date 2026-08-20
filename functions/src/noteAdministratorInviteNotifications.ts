/* eslint-disable require-jsdoc, valid-jsdoc */

import {createHash} from "node:crypto";

import {
  Firestore,
  Timestamp,
  Transaction,
} from "firebase-admin/firestore";
import * as logger from "firebase-functions/logger";
import {onDocumentCreated} from "firebase-functions/v2/firestore";

import {GLOBAL_OPERATION_TERMINAL_RETENTION_MILLIS} from "./globalOperations";
import {createUserNotice} from "./notices";
import {
  WorldDatabaseConfig,
  WorldFirestoreDatabaseId,
  WorldFirestoreProvider,
} from "./platform/worldFirestoreProvider";
import {WORLD_CATALOG, WorldCatalogEntry} from "./platform/worldCatalog";

const INVITATION_NOTIFICATION_PATH =
  "noteAdministratorInviteNotifications/{eventId}";

interface NoteAdministratorInviteNotificationData {
  readonly eventId: string;
  readonly sourceWorld: string;
  readonly placeId: string;
  readonly targetUid: string;
  readonly invitationRevision: number;
  readonly token: string;
  readonly status: "pending" | "complete";
  readonly createdAt: Timestamp;
  readonly completedAt: Timestamp | null;
  readonly expireAt: Timestamp | null;
}

const productionFirestore = new WorldFirestoreProvider(
  WORLD_CATALOG.worlds.map((world) => ({
    worldId: world.worldId,
    databaseId: world.databaseId as WorldFirestoreDatabaseId,
  })) satisfies readonly WorldDatabaseConfig[],
);

/** Enqueues one idempotent home-routed notice beside the invitation write. */
export function enqueueNoteAdministratorInviteNotification(
  transaction: Transaction,
  firestore: Firestore,
  input: Readonly<{
    sourceWorld: string;
    placeId: string;
    targetUid: string;
    invitationRevision: number;
    token: string;
    createdAt: Timestamp;
  }>,
): string {
  const eventId = createHash("sha256")
    .update(JSON.stringify([
      input.sourceWorld,
      input.placeId,
      input.targetUid,
      input.invitationRevision,
    ]), "utf8")
    .digest("hex");
  transaction.create(
    firestore.collection("noteAdministratorInviteNotifications").doc(eventId),
    {
      eventId,
      sourceWorld: input.sourceWorld,
      placeId: input.placeId,
      targetUid: input.targetUid,
      invitationRevision: input.invitationRevision,
      token: input.token,
      status: "pending",
      createdAt: input.createdAt,
      completedAt: null,
      expireAt: null,
    } satisfies NoteAdministratorInviteNotificationData,
  );
  return eventId;
}

/** Routes one invitation notice to the target user's immutable home world. */
export async function deliverNoteAdministratorInviteNotification(
  firestore: Firestore,
  eventId: string,
): Promise<void> {
  const eventRef = firestore
    .collection("noteAdministratorInviteNotifications")
    .doc(eventId);
  const snapshot = await eventRef.get();
  if (!snapshot.exists) return;
  const event = parseEvent(snapshot.data(), eventId);
  if (event.status === "complete") return;

  await createUserNotice(firestore, event.targetUid, {
    noticeId: event.eventId,
    category: "system",
    severity: "info",
    title: "Note administrator invitation",
    body: "You have been invited to help administer a note.",
    action: {
      type: "route",
      route: `/worlds/${event.sourceWorld}/invites/${event.token}`,
    },
    sourceType: "noteAdministratorInvitation",
    sourceId: event.eventId,
    push: true,
  });
  const completedAt = Timestamp.now();
  await eventRef.update({
    status: "complete",
    completedAt,
    expireAt: Timestamp.fromMillis(
      completedAt.toMillis() + GLOBAL_OPERATION_TERMINAL_RETENTION_MILLIS,
    ),
  });
}

function notificationTrigger(worldId: string) {
  const world = requireWorld(worldId);
  return onDocumentCreated(
    {
      database: world.databaseId,
      document: INVITATION_NOTIFICATION_PATH,
      region: world.functionsRegion,
      retry: true,
    },
    async (event) => {
      await deliverNoteAdministratorInviteNotification(
        productionFirestore.forWorld(worldId),
        event.params.eventId,
      );
      logger.info("Administrator invitation notification routed.", {
        world: worldId,
        eventId: event.params.eventId,
      });
    },
  );
}

function parseEvent(
  value: unknown,
  expectedEventId: string,
): NoteAdministratorInviteNotificationData {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    throw new Error("Administrator invitation notification is invalid.");
  }
  const event = value as Record<string, unknown>;
  const status = event.status;
  if (event.eventId !== expectedEventId ||
      typeof event.sourceWorld !== "string" ||
      typeof event.placeId !== "string" ||
      typeof event.targetUid !== "string" ||
      typeof event.invitationRevision !== "number" ||
      !Number.isSafeInteger(event.invitationRevision) ||
      event.invitationRevision <= 0 ||
      typeof event.token !== "string" || event.token.length > 512 ||
      (status !== "pending" && status !== "complete") ||
      !(event.createdAt instanceof Timestamp) ||
      (event.completedAt !== null &&
       !(event.completedAt instanceof Timestamp)) ||
      (event.expireAt !== null && !(event.expireAt instanceof Timestamp)) ||
      (status === "pending" &&
       (event.completedAt !== null || event.expireAt !== null)) ||
      (status === "complete" &&
       (!(event.completedAt instanceof Timestamp) ||
        !(event.expireAt instanceof Timestamp)))) {
    throw new Error("Administrator invitation notification is invalid.");
  }
  return event as unknown as NoteAdministratorInviteNotificationData;
}

function requireWorld(worldId: string): WorldCatalogEntry {
  const world = WORLD_CATALOG.worlds.find(
    (candidate) => candidate.worldId === worldId,
  );
  if (world === undefined) throw new Error(`Unknown world: ${worldId}.`);
  return world;
}

export const routeAsiaNoteAdministratorInviteNotification =
  notificationTrigger("asia");
export const routeNorthAmericaNoteAdministratorInviteNotification =
  notificationTrigger("northAmerica");
export const routeEuropeNoteAdministratorInviteNotification =
  notificationTrigger("europe");
