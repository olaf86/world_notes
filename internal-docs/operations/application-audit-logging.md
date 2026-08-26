# Application audit logging operations

## Purpose

World Notes emits bounded, structured application-audit events from trusted
callable Cloud Functions. These events support abuse investigations, account
safety decisions, and correlation with Firebase Authentication activity.

Important administrator decisions remain transactionally audited in Firestore.
Cloud Logging is the broader activity timeline; it does not replace those
Firestore records.

## Application event contract

Events use `jsonPayload.eventType="worldNotesApplicationAudit"` and include:

- server time, duration, action, and outcome;
- authenticated Firebase UID, App Check app ID, and sign-in provider;
- trusted world, request ID, trace context, and safe entity identifiers;
- stable failure and denial reason codes;
- bounded state parameters such as `liked`, `blocked`, or administrator action
  type.

The event intentionally excludes submitted content, passwords, invitation
tokens, email addresses, administrator reason text, image paths, and location
coordinates.

High-volume read-only map queries and ordinary visit recording are not
application-audit events. Their inclusion would add substantial noise without
materially improving abuse investigations.

## Production project

The repository default is `world-notes-prod`. Confirm the active project before
running every command:

```bash
gcloud config get-value project
gcloud projects describe world-notes-prod --format='value(projectId)'
```

## Build the application event producer

From the repository root:

```bash
cd functions
npm ci
npm run build
```

Create and verify the 365-day bucket and sink below before deploying. Logging
sinks do not backfill entries that were received before the sink existed.

## Create a dedicated 365-day forensic log bucket

A dedicated bucket limits extended retention to forensic events instead of
retaining every routine Functions log for a year. The `_Default` bucket may
continue to keep the same events for its normal 30-day period.

The operator needs permission to configure Cloud Logging, such as Logging
Config Writer.

```bash
gcloud logging buckets create world-notes-forensics \
  --project=world-notes-prod \
  --location=global \
  --retention-days=365 \
  --enable-analytics \
  --description='World Notes application and authentication forensic logs'
```

Create a sink that routes only application-audit events and Identity Platform
user-activity events:

```bash
gcloud logging sinks create world-notes-forensics \
  logging.googleapis.com/projects/world-notes-prod/locations/global/buckets/world-notes-forensics \
  --project=world-notes-prod \
  --description='Retain World Notes forensic events for 365 days' \
  --log-filter='jsonPayload.eventType="worldNotesApplicationAudit" OR LOG_ID("identitytoolkit.googleapis.com/requests")'
```

Verify both resources:

```bash
gcloud logging buckets describe world-notes-forensics \
  --project=world-notes-prod \
  --location=global
gcloud logging sinks describe world-notes-forensics \
  --project=world-notes-prod
```

Deploy the Functions revision only after the sink is ready:

```bash
cd ..
firebase deploy --only functions --project world-notes-prod
```

The application begins producing events only for requests received after the
new Functions revision becomes active.

Do not add a `_Default` exclusion initially. The additional 30-day copy makes
deployment verification and ordinary troubleshooting easier. Revisit the
duplication only if measured Logging volume approaches the project's free
allotment.

## Enable Firebase Authentication with Identity Platform

This is an external project and billing change and must be completed by a
project owner or Firebase administrator:

1. Open Firebase Console for `world-notes-prod`.
2. Open **Authentication**, then **Settings**.
3. If the project is not upgraded, select the upgrade to
   **Firebase Authentication with Identity Platform**.
4. Review the active-user pricing and confirm the upgrade.

On the Blaze plan, Identity Platform currently includes a no-cost tier for the
first 50,000 monthly active users for email, social, anonymous, and custom
authentication. Recheck the official Firebase pricing at the time of the
upgrade.

## Enable Identity Platform user-activity logging

Activity logging is disabled by default even after the Identity Platform
upgrade:

1. Open Google Cloud Console for `world-notes-prod`.
2. Open **Identity Platform**, then **Settings**.
3. Under **User activity logging**, select **Enable** and save.
4. Sign out and sign in once with a controlled test account.
5. In Logs Explorer, run:

```text
LOG_ID("identitytoolkit.googleapis.com/requests")
```

Confirm that the test sign-in produced an Authentication activity event. The
365-day sink created above automatically routes subsequent activity entries to
the forensic bucket.

Official references:

- <https://docs.cloud.google.com/identity-platform/docs/activity-logging>
- <https://firebase.google.com/docs/auth#identity-platform>

## Verify application audit events

After deploying, perform a controlled action such as following and then
unfollowing a test account. In Logs Explorer, select the
`world-notes-forensics` bucket and run:

```text
jsonPayload.eventType="worldNotesApplicationAudit"
jsonPayload.actorUid="TEST_FIREBASE_UID"
```

The two events should show `action="user.follow.set"`, a successful outcome,
the target UID, and opposite `following` values.

Useful investigation filters:

```text
# Every audited action for one account
jsonPayload.eventType="worldNotesApplicationAudit"
jsonPayload.actorUid="FIREBASE_UID"

# BAN or restriction denials
jsonPayload.eventType="worldNotesApplicationAudit"
jsonPayload.outcome="denied"
jsonPayload.reasonCode=("account-banned" OR "posting-restricted")

# Administrator account-safety actions
jsonPayload.eventType="worldNotesApplicationAudit"
jsonPayload.action="admin.accountSafety.update"
```

## Access and privacy controls

- Restrict access to the forensic bucket to designated operators.
- Do not grant application service accounts permission to change the bucket,
  sink, or retention setting.
- Treat Firebase UIDs and authentication activity as personal data.
- Document the 365-day purpose and retention period in the internal data
  inventory and, where applicable, the user-facing privacy disclosure.
- Preserve an incident-specific export before the 365-day expiry when a case
  must remain open longer.

For stronger separation, route the forensic sink to a dedicated security
project controlled by a different administrator group. The initial same-project
bucket is sufficient for ordinary abuse investigations and manual BAN
decisions, but it does not protect evidence from every project owner.
