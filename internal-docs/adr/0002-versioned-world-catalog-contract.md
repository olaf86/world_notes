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

North America and Europe already have protected Firestore databases, but their
regional Storage buckets and remaining workers do not exist yet.

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
- duplicate world, database, or non-null bucket routes;
- an absent `(default)` database;
- unsupported schema or lifecycle states;
- activation flags that are ahead of lifecycle provisioning.

Dart implements the same strict wire parser in `lib/config/world_catalog.dart`.
It deliberately treats `worldId` as a validated string rather than a
three-value enum. A future `getWorldCatalog` callable can therefore return a
new world to a compatible installed client without changing the Dart type.

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
- `bucketName` may be `null` only while `provisioning`.

Allowing a null bucket during provisioning records real incomplete state
without inventing a globally unique bucket name. Moving a world to
`mirrorOnly` requires its bucket and the rest of its routing bundle to exist.

## Initial catalog

| World | State | Content access | Home assignment | Bucket |
| --- | --- | --- | --- | --- |
| Asia | `contentEnabled` | enabled | disabled | existing default bucket |
| North America | `provisioning` | disabled | disabled | not provisioned |
| Europe | `provisioning` | disabled | disabled | not provisioned |

Asia is not marked `homeEnabled` until the home-directory authority and legacy
assignment migration exist.

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
