# Activation data inventory

This P21 read-only check compares count-level global data and activation gates
across all catalogued Firestore databases. It does not write cloud state.

It is not part of the app startup path, a deployed Cloud Function, or a
scheduled job. An operator runs it explicitly before and after a world
activation step. The mirror-only smoke command also applies the same readiness
evaluation to Asia and its target world before performing the transient smoke
write. Unit tests exercise the evaluator with synthetic counts during local or
CI test runs.

Run from `functions/`:

```bash
npm run inventory:activation-data -- \
  --project world-notes-prod \
  --report /tmp/world-notes-activation-data-inventory.json
```

The command checks:

- Asia has one private user, public profile, entitlement, usage document, and
  safety authority per `userHomes` marker;
- every mirror world has the same count of `userHomes`, public profiles,
  entitlements, safety projections, social edges, and directional blocks as
  Asia;
- private `users` remain absent from worlds that are closed to home assignment;
- `userUsage` and regional `places` remain absent from worlds that are closed
  to content access; content-enabled worlds may create both as local content is
  added;
- no world has a pending or failed global operation.

The output contains counts and stable check codes only. It contains no UID or
document content. A non-passing inventory exits with status 2. A count match is
an inventory gate, not proof of per-document revision equality; any nonzero
social/block count requires a revision-aware reconciliation before activation.

## Production result (2026-08-13)

The pre-content `world-notes-prod` inventory passed every check after account
and social-edge reconciliation:

- all three worlds contain 2 home markers, profiles, entitlements, and safety
  projections;
- Asia retains the 2 private account authorities, 2 usage authorities, and 46
  existing places;
- North America and Europe contain no private accounts, usage authorities, or
  places before content activation;
- the single Asia social edge is present in both mirror worlds;
- every world has zero pending and zero failed global operations.

The report was collected at `2026-08-13T11:00:33.738Z`. The P21 data gate is
complete. Later inventory runs derive the private-authority gate from home
assignment and the usage/place gates from content access. North America content
and its local usage counter therefore do not create a false failure during P22,
while Europe remains required to stay empty.
