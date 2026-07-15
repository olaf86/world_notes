/* eslint-disable require-jsdoc, no-console */
import {initializeApp} from "firebase-admin/app";
import {FieldPath, getFirestore} from "firebase-admin/firestore";

const projectId = process.env.GCLOUD_PROJECT || "world-notes-prod";
const validThemeIds = new Set([
  "standard",
  "aurora",
  "citrus",
  "botanical",
  "neon",
  "editorial",
]);
const batchSize = 400;

initializeApp({projectId});
const db = getFirestore();

async function main(): Promise<void> {
  let scanned = 0;
  let changed = 0;
  let invalid = 0;
  let cursor: FirebaseFirestore.QueryDocumentSnapshot | undefined;

  for (;;) {
    let query = db
      .collection("places")
      .orderBy(FieldPath.documentId())
      .limit(batchSize);
    if (cursor != null) query = query.startAfter(cursor);
    const snapshot = await query.get();
    if (snapshot.empty) break;

    const batch = db.batch();
    for (const place of snapshot.docs) {
      scanned++;
      const themeId = place.get("themeId");
      if (themeId == null) {
        batch.update(place.ref, {themeId: "standard"});
        changed++;
      } else if (typeof themeId !== "string" || !validThemeIds.has(themeId)) {
        invalid++;
        console.error(`Invalid themeId on places/${place.id}:`, themeId);
      }
    }
    await batch.commit();
    cursor = snapshot.docs[snapshot.docs.length - 1];
  }

  console.log(JSON.stringify({scanned, changed, invalid}));
  if (invalid > 0) process.exitCode = 1;
}

void main();
