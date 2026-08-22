# One-world activation

P22 activates one already provisioned world at a time. North America was first;
Europe follows only after the North America content stage completed.

## Mirror-only smoke

Before changing the catalog, run the target-only smoke command from
`functions/`. It requires exact project and world confirmation because it
performs one transient Admin SDK write:

```bash
npm run smoke:mirror-only-world -- \
  --project world-notes-prod \
  --world northAmerica \
  --report /tmp/world-notes-north-america-mirror-smoke.json \
  --confirm-project world-notes-prod \
  --confirm-world northAmerica
```

The command fails unless the checked-in target remains `mirrorOnly` with both
content and home assignment closed. It then:

- compares target account/global counts with Asia and requires empty target
  content authorities;
- requires zero pending and failed global operations;
- executes a production composite-index query;
- creates, transactionally updates, reads, and deletes the reserved
  `activationSmokeRuns/{worldId}` document in the target database;
- verifies that the temporary document no longer exists;
- emits stable check codes without UIDs or document contents.

The temporary collection has no client Rules grant. Admin SDK access is used
only to prove the regional database route and transaction path before content
is opened. The preceding P21 social-edge apply already proved the deployed
North America replication worker with a real converged operation. Production
preflight separately proves Rules, Functions, IAM, bucket, TTL, backup, and
delete-protection configuration.

The fixed target-bound path makes an interrupted run recoverable: a later run
replaces only that reserved smoke document and again verifies its deletion. Do
not run two smoke commands for the same world concurrently.

Do not change `catalogState` or `contentAccessEnabled` unless the report has
`pass: true`, no temporary document remains, and the P21 inventory is still
passing. Catalog changes, deployment, observation, minimum-version enforcement,
and home assignment are separate reviewed steps.

Production result (2026-08-13): the North America smoke report passed all 23
checks. The production composite index was available, the Admin transaction
round trip succeeded, and the reserved transient document was confirmed
deleted. The report was collected at `2026-08-13T10:33:14.906Z`.

## North America content access

Catalog version 2 advances only North America to `contentEnabled`. It keeps
`homeAssignmentEnabled: false`, so Asia remains the authority world for all
existing accounts and no new account can acquire North America as an immutable
home. At catalog version 2, Europe remained `mirrorOnly` with deny-all client
Rules.

The North America Firestore database and Storage bucket use the same reviewed
Rules files as Asia. Deploy the Rules before Functions and before distributing
the catalog-version-2 client. From the repository root:

```bash
npx -y firebase-tools@latest deploy \
  --project world-notes-prod \
  --only firestore:north-america,storage:north-america

npx -y firebase-tools@latest deploy \
  --project world-notes-prod \
  --only functions
```

After those deployments, run the production preflight again. Distribute the
catalog-version-2 client only after preflight passes. Observe internal-user
North America traffic before any minimum-version or home-assignment change.

Production result (2026-08-13): the North America Rules and all Functions were
deployed successfully. The post-deploy preflight collected at
`2026-08-13T10:58:57.308Z` passed with zero failures and zero warnings. The
follow-up activation inventory collected at `2026-08-13T11:00:33.738Z` passed
all checks with zero pending/failed global operations. North America remained
free of private account and usage authorities, and Europe remained empty and
closed to content.

### Internal content observation

Start the app normally with an internal account, open Settings, select
**Content world**, and choose **North America**. The selector lists only worlds
whose catalog has `contentAccessEnabled: true`. Switching uses the ordinary
`selectedWorldProvider`, which still requires an authenticated, bootstrapped
account and ready account mirrors in the destination. It does not change the
account's permanent home world. Register the device's App Check debug token
when testing with a debug build.

Use one internal account to:

1. create a clearly labelled disposable note in North America;
2. confirm the created note opens and appears on the map/list;
3. post a message and exercise its like state;
4. upload a pin or message image to cover the regional Storage route;
5. archive the disposable note after the checks.

Then rerun production preflight and activation inventory with new report paths.
The inventory permits places and local usage counters in a catalogued
content-access world, but still requires Europe to have neither and requires
North America and Europe to have zero private account authorities while home
assignment is closed. Require every world to have zero pending and failed
global operations before advancing to minimum-version enforcement.

Before `homeEnabled`, rollback is still reversible: restore North America to
`mirrorOnly`, set `contentAccessEnabled: false`, remap its Firestore and Storage
targets to the locked Rules, deploy those gates, and let regional workers drain
already accepted work. Do not delete regional data as part of rollback.

## Europe content access

Catalog version 3 advances Europe to `contentEnabled` while keeping
`homeAssignmentEnabled: false`. Europe uses the same reviewed Firestore and
Storage Rules as Asia and North America, so this change opens the existing
regional client route without introducing a Europe-specific authorization
policy.

The pre-activation inventory collected at `2026-08-22T01:22:09.658Z` passed:
Europe had zero places, zero local usage authorities, zero private account
authorities, and zero pending or failed global operations. The target-bound
mirror-only smoke collected at `2026-08-22T01:22:23.683Z` then passed all 23
checks, including the production composite index, Admin transaction round
trip, and transient-document cleanup.

Deploy the Europe Firestore and Storage Rules before Functions and before
distributing the catalog-version-3 app. After deployment, rerun production
preflight and activation inventory. Internal content observation should cover
the same note, message, image, and archive flows listed for North America.

Before Europe becomes `homeEnabled`, rollback remains reversible: restore it
to `mirrorOnly`, set `contentAccessEnabled: false`, remap Europe Firestore and
Storage to the locked Rules, deploy those gates, and drain already accepted
regional work. Do not delete regional data during rollback.

Production result (2026-08-22): the Europe Firestore and Storage targets were
mapped to the shared Rules, and catalog-version-3 Functions were deployed in
all three regions. The post-deploy preflight collected at
`2026-08-22T01:40:31.724Z` passed with zero failures and zero warnings. The
activation inventory collected at `2026-08-22T01:39:07.348Z` also passed with
zero pending or failed global operations; Europe remained ready for its first
local content with zero private account authorities.
