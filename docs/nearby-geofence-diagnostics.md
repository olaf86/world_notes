# Nearby geofence diagnostics

Nearby notification diagnostics use the `NearbyGeofence` label across the
native and Flutter layers. No coordinates, note titles, user IDs, or FCM tokens
are written to client diagnostics.

## Expected event sequence

When a nearby alert is enabled and Always location permission is available:

1. The alert list is loaded in Flutter.
2. Active alerts are registered with the OS geofence service.
3. iOS or Android reports an `enter` transition.
4. Flutter syncs the in-range state through
   `markNearbyNotificationInRange`.
5. Flutter calls `checkNearbyUnread`.
6. A local notification is displayed when an unread message exists.

Background transitions received before Dart is ready are queued by the native
layer and processed after the app starts.

## iOS/TestFlight device logs

Connect the device to a Mac, open Console, select the iPhone, and filter for:

```text
NearbyGeofence
```

Useful messages include:

```text
Sync requested for ... geofence(s).
Region monitoring started.
Received enter transition.
Delivering enter event to Dart.
Queueing enter event until Dart is ready.
```

## Android device logs

Filter Logcat by the `NearbyGeofence` tag:

```bash
adb logcat -s NearbyGeofence
```

## Cloud Functions logs

The server logs successful in-range updates and unread checks:

```bash
npx -y firebase-tools@latest functions:log \
  --project world-notes-prod \
  --only markNearbyNotificationInRange,checkNearbyUnread \
  --lines 100
```

## Crashlytics

Successful steps are written as Crashlytics breadcrumbs. Failures are reported
as non-fatal issues with these custom keys:

```text
nearby_geofence_operation
nearby_geofence_platform
```

Crashlytics breadcrumbs are supporting context for an issue rather than a
standalone event stream. Use the device logs and Functions logs to inspect a
fully successful run.
