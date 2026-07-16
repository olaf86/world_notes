# Moderation test data

The administrator Moderation screen can be exercised with disposable Firestore
fixtures. Run the commands from `functions/`.

## Emulator

```bash
FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 \
  npm run moderation:test-data -- seed --project world-notes-prod

FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 \
  npm run moderation:test-data -- list --project world-notes-prod
```

## Live Firebase project

Live access requires Application Default Credentials and two explicit safety
flags:

```bash
npm run moderation:test-data -- seed \
  --project world-notes-prod \
  --allow-live \
  --confirm-project world-notes-prod
```

`seed` prints its generated run ID and the exact cleanup command. Use `list`
to recover run IDs later, or inspect one run with `list --run-id <run-id>`.

```bash
npm run moderation:test-data -- cleanup \
  --project world-notes-prod \
  --run-id <run-id> \
  --allow-live \
  --confirm-project world-notes-prod
```

Delete every tracked moderation test data run with `cleanup --all`:

```bash
npm run moderation:test-data -- cleanup \
  --project world-notes-prod \
  --all \
  --allow-live \
  --confirm-project world-notes-prod
```

Each run creates a private archived place, four messages and reviews, two user
reports, and a server-only `moderationTestRuns` manifest. Cleanup also removes
moderation audit logs generated while the fixtures were reviewed.
