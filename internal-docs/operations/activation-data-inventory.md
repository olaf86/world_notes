# Activation data inventory

This P21 read-only check compares count-level global data and activation gates
across all catalogued Firestore databases. It does not write cloud state.

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
- private `users`, `userUsage`, and regional `places` remain absent from
  mirror-only worlds;
- no world has a pending or failed global operation.

The output contains counts and stable check codes only. It contains no UID or
document content. A non-passing inventory exits with status 2. A count match is
an inventory gate, not proof of per-document revision equality; any nonzero
social/block count requires a revision-aware reconciliation before activation.
