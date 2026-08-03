# ADR 0002: Use a versioned, server-authoritative world catalog contract

- Status: Accepted
- Date: 2026-07-30
- Scope: World membership, Firebase resource routing, and activation gates

## Context

World Notes must route a stable `worldId` to its Firestore database, Firestore
location, Functions region, and Storage bucket. Clients need enough public
metadata to construct regional Firebase clients, but a client-supplied
`databaseId`, region, or bucket must never become routing authority.

The catalog must also remain extensible. Encoding `asia`, `northAmerica`, and
`europe` as a Dart enum would require an app release before any new world could
appear. Conversely, accepting arbitrary JSON without strict validation could
activate incomplete resources or route trusted server work incorrectly.

North America and Europe have protected Firestore databases and regional
Storage buckets, but their remaining workers do not exist yet.

## Decision

Use `functions/src/platform/worldCatalog.config.json` as the source-controlled
server catalog. It contains:

```text
schemaVersion
catalogVersion
worlds[]
  worldId
  databaseId
  firestoreLocation
  functionsRegion
  bucketName
  displayNameKey
  catalogState
  homeAssignmentEnabled
  contentAccessEnabled
```

`schemaVersion` identifies the wire shape understood by code.
`catalogVersion` identifies one published set of worlds and activation flags.
Changing fields requires a schema-version decision; changing membership or
gates increments only the catalog version.

Functions parses the checked-in JSON at module initialization through
`parseWorldCatalog`. It rejects:

- missing or unknown fields;
- malformed identifiers, regions, and bucket names;
- duplicate world, database, or bucket routes;
- an absent `(default)` database;
- unsupported schema or lifecycle states;
- activation flags that are ahead of lifecycle provisioning.

Dart implements the same strict wire parser in `lib/config/world_catalog.dart`.
It deliberately treats `worldId` as a validated string rather than a
three-value enum. A future `getWorldCatalog` callable can therefore return a
new world to a compatible deployed client without changing the Dart type.

The server remains authoritative. Clients may submit only `worldId`; the
server resolves all Firebase resource identifiers from its validated catalog.

## Lifecycle invariants

The ordered lifecycle remains:

```text
provisioning -> mirrorOnly -> contentEnabled -> homeEnabled
```

The activation booleans are separate emergency/product gates, but they cannot
get ahead of that lifecycle:

- `contentAccessEnabled` is allowed only for `contentEnabled` or
  `homeEnabled`;
- `homeAssignmentEnabled` is allowed only for `homeEnabled` and requires
  content access;
- every catalog entry has a non-null, globally unique `bucketName`.

The two additional buckets are provisioned before their worlds leave
`provisioning`. Their Firebase Security Rules remain deny-all until the
corresponding client routes and authorization tests are ready.

## Initial catalog

| World | State | Content access | Home assignment | Bucket |
| --- | --- | --- | --- | --- |
| Asia | `contentEnabled` | enabled | disabled | existing default bucket |
| North America | `provisioning` | disabled | disabled | `world-notes-prod-north-america` |
| Europe | `provisioning` | disabled | disabled | `world-notes-prod-europe` |

Asia is not marked `homeEnabled` until the home-directory authority and legacy
assignment migration exist.

The current checked-in contract remains `schemaVersion: 1` and
`catalogVersion: 1`. The contract has not been released to external clients or
persisted in global operations, so the development-time bucket nullability
change is folded into the initial version. Every version 1 entry requires a
bucket route.

All three buckets use the same physical settings, differing only by immutable
regional location:

| Setting | Value |
| --- | --- |
| Storage class | `REGIONAL` |
| Uniform bucket-level access | disabled |
| Public Access Prevention | inherited |
| Soft delete | 7 days |
| Object versioning | disabled |
| CORS / lifecycle | none |

All three are linked to Firebase Storage and have independent Firebase CLI
deploy targets. Asia retains `storage.rules`; North America and Europe use
`storage.named.locked.rules` until activation.

## Contract verification

Functions and Flutter tests parse the same checked-in server JSON. Both suites
cover strict fields, route uniqueness, lifecycle gates, and schema-version
rejection. The Functions suite additionally asserts that the temporary
Firestore adapter allowlist contains exactly the catalog's current database
IDs; this prevents drift until the later `WorldRegistry` becomes the provider's
only construction path.

```bash
npm --prefix functions test
flutter test test/world_catalog_test.dart
```

No code generator is introduced for the three initial world IDs. Generating a
fixed Dart world list would work against dynamic catalog expansion, while
generating two full validators would add a maintenance layer without removing
the need to test their runtime behavior. The shared wire document plus strict
parsers keeps the boundary explicit and small.

## Consequences

Adding a world is a server deployment and infrastructure operation, not a new
Dart enum case. It still requires all provisioning and activation gates before
the catalog entry can advance.

The TypeScript and Dart validators intentionally duplicate a small amount of
wire validation. Their shared source document and mirrored contract tests are
the drift detector. If the contract grows substantially, schema-based
generation can be reconsidered without changing the wire format.
