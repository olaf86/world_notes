# Footprint Firestore Rules Findings

Firestore database: `projects/world-notes-prod/databases/(default)`,
Standard edition, Firestore Native.

Relevant paths:
- `places/{placeId}` stores note metadata and now includes
  `footprintEnabled: bool`, defaulting to true, and
  `visitorCount: int`, counting distinct users that left footprints.
- `places/{placeId}/visitors/{uid}` stores denormalized visitor display data:
  `userId: string`, `displayName: string?`, `photoUrl: string?`,
  `firstVisitedAt: timestamp`, `lastVisitedAt: timestamp`,
  `visitCount: int`, `isMaintainer: bool`.

Client queries added:
- `places/{placeId}/visitors.orderBy('lastVisitedAt', descending: true).limit(n)`
- `places/{placeId}/visitors.orderBy('lastVisitedAt', descending: true)`
- `places/{placeId}/visitors.orderBy('visitCount', descending: true)`

Access model:
- Users who can access the note content may read its visitor list.
- Visitor writes are denied in Security Rules and handled only by
  `recordNoteVisit` Cloud Function.
- Footprint settings are changed only by `setFootprintEnabled` Cloud Function.

Index notes:
- Visitor queries use a single `orderBy` field inside a subcollection, so
  Standard edition single-field indexes cover them.
