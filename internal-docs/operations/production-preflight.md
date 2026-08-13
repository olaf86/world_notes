# Production readiness preflight

P21 starts with a read-only comparison between the checked-in multi-world
contract and one explicitly named Firebase project. The command reads resource
metadata only. It does not read application documents, deploy code, change IAM,
or enable APIs.

## Prerequisites

- Node.js 24 and the repository dependencies are installed.
- Firebase CLI authentication can read the target project:

  ```bash
  npx -y firebase-tools@latest login
  ```

- Google Cloud CLI authentication uses the intended operator account:

  ```bash
  gcloud auth login
  ```

- The operator has `roles/firebaserules.viewer` on the project. This is the
  minimum predefined role used to compare deployed Firestore and Storage Rules.
- `policytroubleshooter.googleapis.com` is enabled when runtime IAM permission
  verification is required. The command remains read-only; enabling the API is
  a one-time project configuration change.

## Run

From the repository root:

```bash
npm --prefix functions run preflight:production -- \
  --project world-notes-prod
```

The explicit project argument is mandatory and must equal the checked-in
`.firebaserc` default. This prevents an ambient CLI project from selecting a
different environment.

To write a content-free JSON result to a new file:

```bash
npm --prefix functions run preflight:production -- \
  --project world-notes-prod \
  --report /tmp/world-notes-production-preflight.json
```

The report path must not already exist. The report contains check identifiers,
statuses, and summaries; it contains no Firebase document data, rules source,
access tokens, or credentials.

Use `--skip-iam` only for parser diagnostics. It deliberately leaves the IAM
gate as a warning and is not sufficient for production activation.

## Checked contract

- all catalog databases exist in their declared regions;
- Standard edition, Native mode, delete protection, PITR, and backup schedules;
- deployed Firestore and Storage Rules equal the checked-in source;
- composite indexes equal `firestore.indexes.json`;
- every checked-in TTL policy is active;
- buckets are colocated, use uniform bucket-level access, enforce public access
  prevention, and have no public IAM principals;
- every exported Function is deployed in every source-declared region and is
  active;
- runtime service accounts can perform required Firestore, Storage, and V4 URL
  signing operations.

Warnings still require review, but only failed checks make the command return a
nonzero exit status.

## Current P21 result (2026-08-13)

The production preflight now passes every required check for
`world-notes-prod`:

- all three Standard/Native databases have the expected location, delete
  protection, PITR, and one backup schedule;
- Firestore and Storage Rules, composite indexes, and TTL policies match the
  checked-in contract in every world;
- all three buckets use uniform bucket-level access, enforce public access
  prevention, and have no public IAM principal;
- the deployed Function inventory matches the current exports and every
  expected Function is active;
- the runtime service account can read objects from all three regional buckets
  and can sign V4 URLs through `iam.serviceAccounts.signBlob`.

The infrastructure preflight gate is open. P21 may proceed to dry-run backfill,
high-water reconciliation, and activation tooling. Passing preflight does not
itself enable North America or Europe for content or home assignment.
