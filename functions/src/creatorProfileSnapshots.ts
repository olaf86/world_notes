import {onDocumentWritten} from "firebase-functions/v2/firestore";
import * as logger from "firebase-functions/logger";

import {REGION} from "./constants";
import {asiaWorldContext} from "./platform/worldContext";
import {ASIA_WORLD} from "./platform/worldRegistry";

const BATCH_WRITE_LIMIT = 450;

/**
 * Keeps the creator photo snapshot on active places in sync with the public
 * profile. Map-pin reads can then stay a single collection query.
 */
export const syncCreatorPhotoSnapshot = onDocumentWritten(
  {
    database: ASIA_WORLD.databaseId,
    document: "publicProfiles/{userId}",
    region: REGION,
  },
  async (event) => {
    const before = event.data?.before;
    const after = event.data?.after;
    if (!after?.exists) return;

    const previousPhotoUrl = before?.get("photoUrl") as string | null;
    const previousPhotoVersion = before?.get("photoVersion") as number;
    const photoUrl = after.get("photoUrl") as string | null;
    const photoVersion = after.get("photoVersion") as number;
    if (
      before?.exists &&
      previousPhotoUrl === photoUrl &&
      previousPhotoVersion === photoVersion
    ) return;

    const db = asiaWorldContext().firestore;
    const places = await db
      .collection("places")
      .where("createdByUserId", "==", event.params.userId)
      .where("isArchived", "==", false)
      .get();

    for (
      let index = 0;
      index < places.docs.length;
      index += BATCH_WRITE_LIMIT
    ) {
      const batch = db.batch();
      for (const place of places.docs.slice(index, index + BATCH_WRITE_LIMIT)) {
        batch.update(place.ref, {
          creatorPhotoUrl: photoUrl,
          creatorPhotoVersion: photoVersion,
        });
      }
      await batch.commit();
    }

    logger.info("Synchronized creator photo snapshots.", {
      userId: event.params.userId,
      updatedPlaceCount: places.size,
    });
  },
);
