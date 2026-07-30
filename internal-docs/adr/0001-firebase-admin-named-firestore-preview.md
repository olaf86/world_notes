# ADR 0001: Use the Firebase Admin named Firestore Preview boundary

- Status: Accepted
- Date: 2026-07-30
- Scope: Server selection of a Firestore database inside one Firebase project

## Context

World Notes will initially map three worlds to three Firestore databases in
one Firebase project:

| World | Database |
| --- | --- |
| `asia` | `(default)` |
| `northAmerica` | `north-america` |
| `europe` | `europe` |

Firebase Admin Node exposes `getFirestore(app, databaseId)` for selecting a
named database. The current reference labels this overload Public Preview and
advises against production use:
<https://firebase.google.com/docs/reference/admin/node/firebase-admin.firestore>

The stable `@google-cloud/firestore` server client can select the same database
with `new Firestore({projectId, databaseId})`. It remains a viable replacement,
but using Firebase Admin preserves one Firebase initialization and dependency
surface while the application is built around Firebase Auth, App Check,
Messaging, Storage, Functions, and Firestore.

## Decision

Use the Firebase Admin named-database overload in production with explicit
risk acceptance.

Only `createAdminWorldFirestoreClient` in
`functions/src/platform/worldFirestoreProvider.ts` may call the named overload.
Business handlers receive a `Firestore` instance from
`WorldFirestoreProvider`; they must not accept a raw client-supplied database
ID or call the overload directly.

The Asia `(default)` database continues to use the stable
`getFirestore(app)` overload. The Preview overload is used only for named
databases.

## Required controls

1. Pin `firebase-admin` to the exact reviewed version in `package.json` and
   `package-lock.json`.
2. Construct the provider only from trusted, allowlisted world database
   configs.
3. Reject duplicate world and database mappings.
4. Cache exactly one Firestore client per database.
5. Compare the returned client's `databaseId` with the requested descriptor
   before returning it to a handler.
6. Run unit contracts on every change and emulator/staging contracts before
   upgrading Firebase Admin or activating a world.
7. Label production route failures by world and database ID when the world
   kernel adds observability.
8. Retain per-world read/write activation switches before non-Asia production
   traffic is enabled.

## Contract coverage

P00 establishes automated checks for:

- default and named database resolution;
- allowlist rejection and database-route mismatch detection;
- one-client-per-database caching;
- Firestore read/write isolation;
- transaction and batch behavior;
- collection-group queries;
- explicit cross-database copying;
- Functions v2 named-database event-filter generation.

The emulator contract is skipped by the normal unit test command when
`FIRESTORE_EMULATOR_HOST` is absent. Run it through the Firestore emulator
before accepting P00.

```bash
npx -y firebase-tools@latest emulators:exec \
  --only firestore \
  --project demo-world-notes-p00 \
  "npm --prefix functions run test:firestore-contract"
```

Cloud execution additionally requires two matching, explicit project values.
The contract uses unique document IDs and deletes those documents before
closing its clients:

```bash
P00_FIRESTORE_PROJECT_ID=world-notes-prod \
P00_CONFIRM_PROJECT_ID=world-notes-prod \
npm --prefix functions run test:firestore-contract:cloud
```

The cloud contract intentionally queries the production `messageLikes`
collection-group index rather than creating a test-only index. This verifies
that the same checked-in index definition is usable in a named database.

The Firestore emulator currently warns that multiple configured databases are
not fully supported and does not enforce composite-index readiness. The cloud
contract is therefore a required complement to the emulator contract, not an
optional duplicate.

Verification on 2026-07-30:

- Functions lint, TypeScript build, and unit contracts passed;
- the emulator contract passed for all three database IDs;
- the cloud contract passed against `world-notes-prod` after the named
  databases' composite indexes reached `READY`;
- cloud coverage included isolated reads/writes, a transaction, a batch, the
  production `messageLikes` collection-group index, and an explicit
  Asia-to-Europe copy;
- all contract documents use unique IDs and are deleted in `finally`.

## Provisioned development environment

The Firebase project is still pre-production, so the user approved using
`world-notes-prod` as the development verification environment. On
2026-07-30, P00/P02 foundation work provisioned:

| World | Database | Location | Delete protection | PITR |
| --- | --- | --- | --- | --- |
| Asia | `(default)` | `asia-northeast1` | enabled | enabled |
| North America | `north-america` | `us-central1` | enabled | enabled |
| Europe | `europe` | `europe-west1` | enabled | enabled |

`firebase.json` maps Rules and indexes explicitly for all three databases.
The existing Rules remain attached to `(default)`. Until their client routes
and authorization tests are implemented, the two named databases use
`firestore.named.locked.rules`, which denies every client read and write while
still allowing trusted Admin SDK contract tests. All three databases use the
same checked-in production composite-index definitions.

## Consequences

The application accepts a source-compatibility and support risk at one
construction boundary. Named-database behavior may change before GA, and an
SDK upgrade cannot be treated as routine dependency maintenance.

This decision does not relax consistency, idempotency, retry, monitoring, or
Security Rules requirements. It also does not make the database ID a
client-controlled route.

P00 does not migrate existing handlers or activate client traffic in the named
databases. The database resources and the Rules/index deployment mapping were
created early with user approval, advancing a limited part of P02. Remaining
repeatable infrastructure, IAM, Storage, Rules tests, and CI work stays in
later implementation units.

## Replacement and rollback

If the Firebase Admin overload regresses:

1. stop the affected world's new writes through the world catalog;
2. keep Asia and unaffected background repair paths available;
3. replace only `createAdminWorldFirestoreClient` with an
   `@google-cloud/firestore` constructor using Application Default
   Credentials;
4. run the same provider and emulator/staging contract suite;
5. restore world traffic after route, transaction, query, and replication
   checks pass.

Because Firebase Admin re-exports the Google Cloud Firestore data types,
business-handler signatures do not need to change when the construction
adapter is replaced.
