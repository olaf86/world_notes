# My Notes Read-Only Design

## Goal

Allow users to view their own notes from anywhere, regardless of current location.

For this phase, My Notes is a read-back-only entry point. We will not add distance-based write restrictions, but normal message creation will require a server-created write session so message creation is also denied server-side when the note is opened from My Notes.

## Why We Changed Direction

The earlier proposal allowed remote reading but only allowed writing near the note location. That required changes across distance checks, posting UI, Cloud Functions, Firestore Rules, and image upload ordering.

The idea matches the product concept, but it increases implementation complexity and makes authorization harder to reason about. Firestore Rules cannot verify a user's physical location, and even if a Cloud Function receives GPS coordinates, it still cannot prove those coordinates represent the device's real location.

Instead of adding a distance rule now, this design uses a simpler write-session boundary: normal note access can write; My Notes can only read.

## Product Rules

- Nearby access: Notes opened from nearby Map/List can write as before when a write session exists and `canAcceptMessages` is true.
- Invite/private access: Notes opened through invite links or pattern unlocks can also write as before when a write session exists.
- My Notes access: The user can view their own notes from anywhere, but My Notes does not request a write session and does not show writing UI.
- My Notes scope: The first version focuses on reading messages. It does not add owner management actions or remote editing.
- Archived notes: The first version shows only active owned notes. Archived history is deferred.

This preserves the intended mental model:

> Normal note access through nearby discovery or invitations can write. My Notes is for reading back.

## Server-Side Read-Only

Use a write session as the server-side gate.

Message creation may stay as a direct Firestore write, but Firestore Rules must additionally require a valid write session.

Session document:

```text
places/{placeId}/writeSessions/{uid}
  uid: string
  placeId: string
  createdAt: timestamp
  expiresAt: timestamp
```

Rules concept:

```rules
function hasWriteSession(placeId) {
  let path = /databases/$(database)/documents/places/$(placeId)/writeSessions/$(request.auth.uid);
  return exists(path) && get(path).data.expiresAt > request.time;
}

match /places/{placeId}/messages/{messageId} {
  allow read: if canAccessNote(placeId);
  allow create: if canAccessNote(placeId)
                && hasWriteSession(placeId)
                && ...
}
```

Session writes are server-only:

```rules
match /places/{placeId}/writeSessions/{uid} {
  allow read: if request.auth != null && request.auth.uid == uid;
  allow write: if false;
}
```

Cloud Function:

```ts
createWriteSession({ placeId })
```

Function checks:

- The caller is authenticated.
- The caller can access the note.
- The place is open.
- The place is not archived.
- The place is not expired.
- `messageCount < MAX_MESSAGES_PER_THREAD`.
- App Check is enforced when practical.

The function then writes `places/{placeId}/writeSessions/{uid}` with a short TTL, for example 15 minutes.

Client behavior:

- Normal `/note/:placeId` access requests a write session before showing or enabling compose.
- My Notes opens the same screen with `readOnly=true`, does not request a write session, and hides compose UI.
- If a normal session expires while the note screen is open, the client can request a fresh one before sending.

Important boundary:

This is a server-side write gate because Firestore rejects message creation without a server-created session. It does not prove physical proximity. If proximity enforcement becomes necessary later, add that validation inside `createWriteSession` rather than redesigning message writes again.

## Current Code Shape

Relevant existing pieces:

- `MapScreen` shows nearby notes on the map.
- `PlaceListScreen` shows nearby notes as a list.
- `PlaceRepository.watchPlacesNearby(...)` reads nearby notes by geohash cells.
- `PlaceRepository.getPlace/watchPlace(...)` can read any signed-in accessible place by id.
- `MessageRepository.sendMessage(...)` writes directly to `places/{placeId}/messages/{messageId}`.
- `firestore.rules` allows message creation when `canAccessNote(placeId)` and note state checks pass.
- `PlaceEntity.canAcceptMessages` checks open/archive/expiry/message-count state.
- `firestore.indexes.json` already contains `createdByUserId ASC, isArchived ASC`, which can support a basic owner note query.

This phase requires a small Firestore Rules change and one callable Function for write sessions, but it does not require moving message creation itself to a Function.

## Proposed Architecture

### 1. Reframe Bottom Navigation

The current `Map` tab and `List` tab are two views of the same nearby-note access feature. My Notes is a different feature: owned-note recall.

Recommended bottom navigation:

```text
Map
My Notes
Profile
```

`Map` branch:

- Contains the nearby-note experience.
- Adds a top segmented control or tabs for `Map` / `List`.
- Both views use the same nearby anchor and `placesNearbyProvider`.
- Opening a note from either view uses normal `/note/:placeId` behavior.
- Normal note access can request a write session.

`My Notes` branch:

- Shows active notes created by the current user.
- Opens notes in read-only mode.
- Does not depend on current location.
- Does not request write sessions.

This keeps the information architecture cleaner:

- Bottom navigation separates major user intents.
- Top tabs inside Map switch representation of the same nearby data.
- My Notes no longer feels like a variant of nearby List.

### 2. Add Owner Note Query

Add repository methods:

```dart
Stream<List<PlaceEntity>> watchMyPlaces(String userId);
Future<List<PlaceEntity>> getMyPlaces(String userId);
```

Implementation query:

```dart
places
  .where('createdByUserId', isEqualTo: userId)
  .where('isArchived', isEqualTo: false)
```

Performance:

- Firestore uses indexes for this query. Cost and latency are based on matching documents returned, not the total number of `places` documents in the project.
- Even if `places` grows to hundreds of thousands or more, this query remains small because it targets one user's active notes.
- The app already has active-note limits (`freeNoteLimit = 20`, `proNoteLimit = 200`), so the first My Notes phase should return a small bounded set per user.
- Add a `limit`, for example 50 or 100, if we want defensive pagination from day one.

Sort options:

- Phase 1: sort client-side by `lastMessageAt ?? createdAt` descending. This is fine while active notes are capped at 20/200 and works with the existing index.
- Later: add `orderBy('lastMessageAt', descending: true)` and a composite index with `createdByUserId ASC, isArchived ASC, lastMessageAt DESC` if we add archived history, higher limits, or server-side pagination.

Provider:

```dart
final myPlacesProvider = StreamProvider<List<PlaceEntity>>((ref) {
  final user = ref.watch(authStateProvider).valueOrNull;
  if (user == null) return Stream.value(const []);
  return ref.watch(placeRepositoryProvider).watchMyPlaces(user.id);
});
```

### 3. Use Query Parameter Read-Only Mode

Use the existing note route with a read-only query parameter:

```dart
/note/:placeId?title=...&readOnly=true
```

This is preferable to a separate `/my-notes/:placeId` route for the first implementation:

- It reuses the existing route and transition setup.
- It keeps deep-link and title handling simple.
- It makes `readOnly` an explicit mode of `NoteBoxScreen`, not a separate screen concept.
- The query parameter is not the security boundary; the write session is.

`NoteBoxScreen` constructor:

```dart
const NoteBoxScreen({
  required String placeId,
  required String placeTitle,
  bool readOnly = false,
});
```

Route behavior:

- `/note/:placeId` passes `readOnly: false`.
- My Notes opens `/note/:placeId?title=...&readOnly=true`.

Read-only mode behavior:

- Messages are visible if the user has read access.
- Compose FAB is hidden.
- Message creation overlay cannot be opened.
- Owner thread controls are hidden in phase 1 to keep My Notes strictly read-only.
- No write session is requested.
- Show a compact banner: `Read-only from My Notes.`

### 4. Add My Notes UI

Create a dedicated My Notes screen for the second bottom-nav branch.

`My Notes` screen:

- Uses `myPlacesProvider`.
- Opens `/note/:placeId?readOnly=true`.
- Labels the list clearly as owned notes.
- Shows note title, subtitle, visibility/closed state, message count, and last activity.
- Does not show distance as a primary signal, because location is irrelevant here.
- Empty state: encourages creating notes from the Map tab.

### 5. Add Write Session Repository Support

Add a small repository method, likely on `PlaceRepository` or a dedicated service:

```dart
Future<void> createWriteSession(String placeId);
```

Normal note detail flow:

- If `readOnly == false` and `place.canAcceptMessages`, call `createWriteSession(placeId)`.
- Enable compose only after the session exists or the callable succeeds.
- On send failure caused by an expired or missing session, request a fresh session and retry once or show a clear error.

My Notes flow:

- If `readOnly == true`, never call `createWriteSession`.
- Compose stays hidden regardless of `place.canAcceptMessages`.

## Implementation Plan

1. Write session backend
   - Add `createWriteSession` callable.
   - Add a server-only rule block for `places/{placeId}/writeSessions/{uid}`.
   - Add `hasWriteSession(placeId)` to message create rules.
   - Keep message creation itself as a direct Firestore write.

2. Repository/providers
   - Add `watchMyPlaces` / `getMyPlaces`.
   - Add `myPlacesProvider`.
   - Add `createWriteSession(placeId)` client method.
   - Sort active owned notes by `lastMessageAt ?? createdAt` descending.

3. Navigation
   - Change bottom navigation branches to `Map`, `My Notes`, `Profile`.
   - Move nearby List into the Map branch as a top `Map` / `List` toggle.
   - Parse `readOnly=true` on `/note/:placeId`.

4. Nearby Map/List UI
   - Introduce a container screen for the Map branch, for example `NearbyScreen`.
   - Reuse existing `MapScreen` and `PlaceListScreen` internals as the two top-tab views.
   - Ensure both views keep sharing `anchorPositionProvider` and `placesNearbyProvider`.

5. My Notes UI
   - Add a dedicated My Notes list screen.
   - Use `myPlacesProvider`.
   - Open notes through `/note/:placeId?readOnly=true`.

6. Note detail UI
   - Add `readOnly` field to `NoteBoxScreen`.
   - Hide compose FAB when `readOnly` is true.
   - Prevent compose overlay from opening when `readOnly` is true.
   - Hide owner mutation menu in read-only mode for phase 1.
   - Add a small read-only banner.
   - Request write session only when `readOnly == false`.

7. Tests
   - Rules test: message create without write session is denied.
   - Rules test: message create with valid write session is allowed.
   - Function test: `createWriteSession` rejects closed/expired/archived/full notes.
   - Repository/provider test: signed-out user gets an empty My Notes stream.
   - Repository/provider test: signed-in user queries only their active notes.
   - Widget test: My Notes row opens `/note/:placeId?readOnly=true`.
   - Widget test: `NoteBoxScreen(readOnly: true)` does not show the compose FAB and does not request a write session.
   - Widget test: Map branch top toggle switches between nearby map and nearby list.

## Deferred

- Distance-based write session validation.
- Moving message creation fully to a Cloud Function.
- Remote owner management from My Notes.
- Archived note history.
- Server-side ordering for My Notes with a new composite index.

