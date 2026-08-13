# Social edge backfill

This P21 command republishes existing Asia social-edge authority through the
normal global-operation path. It does not write destination edges directly.
The deployed replication handler applies each missing edge and both derived
profile-counter transitions in one destination transaction.

The command defaults to dry-run, requires explicit source/target projects,
uses bounded document-ID pages and a local checkpoint, derives one stable
operation ID per edge, captures the highest edge ID reached by its bounded
first pass as the high-water boundary, performs a second reconciliation pass
to that same boundary, emits no UIDs, and performs no deletes. Edge IDs and
cursors remain only in the local checkpoint; they are omitted from logs and
the report. Both passes use the built-in ascending document-ID order and need
no migration-only Firestore index.

Before apply, every destination profile must have valid non-negative
`followerCount` and `followingCount` fields. This is deliberately fail-closed
to avoid applying a transition to an unknown aggregate baseline. An edge that
is already converged in every destination is left untouched. If any
destination is behind, the command republishes the edge once; the resulting
authority revision is then applied to every destination. The first command
also upgrades the exact legacy active-edge shape (`followerUid`, `followeeUid`,
`createdAt`) atomically with its global operation; unknown shapes fail closed.

Run the bounded dry-run from `functions/`:

```bash
npm run backfill:social-edges -- \
  --source-project world-notes-prod \
  --target-project world-notes-prod \
  --checkpoint /tmp/world-notes-social-dry-run.checkpoint.json \
  --report /tmp/world-notes-social-dry-run.report.json \
  --page-size 50 \
  --max-pages 1
```

Use a separate checkpoint for apply and require
`--apply --confirm-project world-notes-prod`. After apply, wait for the normal
global replication workers, rerun activation inventory, and require zero
pending/failed operations plus matching social-edge counts before activation.
