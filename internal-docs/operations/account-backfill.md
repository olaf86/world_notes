# Account authority and mirror backfill

This runbook covers the P21 migration that assigns every existing Firebase
Auth account to the Asia home world and creates the account projections needed
by North America and Europe. It does not move notes, messages, images, or any
other regional content.

## Safety contract

The command:

- requires explicit source and target project IDs;
- currently refuses cross-project execution;
- defaults to read-only dry-run;
- requires an exact project confirmation before `--apply`;
- processes at most 200 Auth users per page;
- stores an opaque Auth cursor in a local checkpoint after a whole page
  succeeds;
- retries a partially written page safely because document IDs and bootstrap
  operation IDs are deterministic;
- preserves existing document fields and destination social counters;
- rejects a destination projection whose revision is ahead of or conflicts
  with its Asia authority;
- performs a second full pass up to the initial high-water time;
- can explicitly preserve Auth-only accounts that have no Asia authority
  document by using `--skip-auth-only`;
- emits counts only and never logs a UID or account content;
- performs no deletes.

The Asia authority bundle is `userHomes`, `users`, `publicProfiles`,
`userEntitlements`, `userUsage`, and `accountSafety`. The two mirror worlds
receive `userHomes`, `publicProfiles`, `userEntitlements`, and `accountSafety`.
The command also repairs the `homeWorld=asia` and `homeEpoch=1` Auth claims.

`userUsage.activeNoteCount` is recomputed from unarchived Asia notes that still
hold an active-note slot. Each account query is capped at 1,000 unarchived
notes and aborts rather than silently truncating an abnormal account.

## 1. Bounded dry-run

Run from `functions/` using Application Default Credentials that can read Auth
and all three Firestore databases:

```bash
npm run backfill:accounts -- \
  --source-project world-notes-prod \
  --target-project world-notes-prod \
  --checkpoint /tmp/world-notes-account-backfill-dry-run.checkpoint.json \
  --report /tmp/world-notes-account-backfill-dry-run.report.json \
  --skip-auth-only \
  --page-size 50 \
  --max-pages 1
```

This reads one page and saves its next cursor. Inspect the report, then resume
with the same command after removing only `--max-pages 1`. Do not delete or
edit the checkpoint between runs.

The first pass records the fixed high-water time. When it reaches the end of
Auth, the command automatically starts the reconciliation pass. Completion is
reported only after the second pass reaches the end. Aggregate totals include
both passes by design.

`--skip-auth-only` skips an Auth account only when all six Asia authority
documents are absent. It is intended for accounts that deliberately remain
outside the normal app bootstrap flow, such as an App Store review account.
An account with any authority document is still reconciled so that partial
initialization cannot be hidden by this option. The selected behavior is part
of checkpoint compatibility; do not resume a checkpoint with different skip
semantics.

## 2. Full dry-run acceptance

The dry-run is acceptable when:

- the command exits successfully;
- the report has `complete: true` and `phase: "complete"`;
- there are no revision conflicts;
- the planned write counts are plausible for the current Auth user count;
- the source and target in both report and checkpoint are
  `world-notes-prod`.

Keep the dry-run report as the migration review artifact. The checkpoint
contains an opaque page token, so keep it internal and do not publish it.

## 3. Apply

Use separate apply checkpoint and report files. This prevents a completed
dry-run checkpoint from skipping the write pass.

```bash
npm run backfill:accounts -- \
  --source-project world-notes-prod \
  --target-project world-notes-prod \
  --checkpoint /tmp/world-notes-account-backfill-apply.checkpoint.json \
  --report /tmp/world-notes-account-backfill-apply.report.json \
  --skip-auth-only \
  --page-size 50 \
  --max-pages 1 \
  --apply \
  --confirm-project world-notes-prod
```

Review the first applied page, then resume with the same command after
removing only `--max-pages 1`. A failure does not advance the current page;
accounts already processed within that page are safe to process again.

## 4. Post-apply verification

Run a new dry-run with new file names. A clean reconciliation should report no
planned mirror or Auth-claim writes:

```bash
npm run backfill:accounts -- \
  --source-project world-notes-prod \
  --target-project world-notes-prod \
  --checkpoint /tmp/world-notes-account-backfill-verify.checkpoint.json \
  --report /tmp/world-notes-account-backfill-verify.report.json \
  --skip-auth-only \
  --page-size 50
```

The `authorityWrites`, four `*MirrorWrites`, and `authClaimWrites` counters are
the convergence signals and should all be zero after a successful apply.
`skippedAuthOnly` should equal the deliberately excluded account count on each
pass.

Do not activate a new content or home world from this command. Catalog
activation remains a separate reviewed P22 change after the post-apply report,
synthetic traffic, and operational checks pass.

## Production execution record — 2026-08-13

The migration completed against `world-notes-prod`:

- the initial dry-run examined two eligible Auth accounts over two passes;
- no account was created after the fixed high-water time;
- the apply pass wrote 12 Asia authority documents, four copies of each
  regional mirror type, and two Auth home-claim caches;
- the apply reconciliation pass planned and performed zero further writes;
- a separate two-pass post-apply dry-run reported zero authority, mirror, and
  Auth-claim writes in both passes;
- no revision conflict or invalid account bundle was observed;
- no regional content was moved or deleted.

The account authority and mirror migration is therefore converged at the
recorded high-water mark. Keep North America and Europe out of content/home
activation until the remaining P21 inventory and activation gates pass.

## Notification-locale reconciliation record — 2026-09-16

The notification inbox rollout added the selected-language `noticeLocale`
field to the Asia `users` authority document. The account backfill checkpoint
format was advanced to version 2 so that a checkpoint completed before this
field existed cannot silently skip the new reconciliation.

The migration completed against `world-notes-prod` with `--skip-auth-only`:

- five Auth accounts were listed on each pass;
- four normal accounts were eligible and one intentional App Store review
  account with no Asia authority documents was skipped unchanged;
- the initial dry-run planned four Asia authority writes and no regional
  mirror or Auth-claim writes;
- the apply pass added `noticeLocale` to those four authority documents;
- the apply reconciliation pass planned and performed zero further writes;
- a separate two-pass post-apply dry-run reported zero authority, mirror, and
  Auth-claim writes while consistently skipping the one Auth-only account;
- no revision conflict or invalid account bundle was observed.

The normal accounts are therefore converged for notification locale. Keep the
backfill available through the notification-inbox release verification window,
then remove the one-time command and this operational runbook in a dedicated
cleanup change. The notice-template deployment command remains permanent.
