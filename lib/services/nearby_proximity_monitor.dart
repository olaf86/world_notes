import 'dart:async';

import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:geolocator/geolocator.dart';

import '../config/app_config.dart';
import '../domain/entities/nearby_notification_entity.dart';
import '../domain/repositories/place_repository.dart';
import 'in_range_state_synchronizer.dart';
import 'native_geofence_service.dart';
import 'nearby_notification_service.dart';

/// Coordinates foreground proximity checks and background OS geofences for
/// notes whose nearby alerts are enabled.
///
/// The in-range synchronizer tracks states reported by this process. The server
/// uses that short-lived state to decide whether a new message should trigger
/// an alert.
class NearbyProximityMonitor {
  final FirebaseCrashlytics crashlytics;
  final PlaceRepository placeRepository;
  final NativeGeofenceService nativeGeofenceService;
  final NearbyNotificationService nearbyNotificationService;

  late final InRangeStateSynchronizer _inRangeStateSynchronizer =
      InRangeStateSynchronizer(
        ({required placeId, required inRange}) => placeRepository
            .markNearbyNotificationInRange(placeId: placeId, inRange: inRange),
      );
  final Map<String, DateTime> _lastCheckedAt = {};

  Position? _latestPosition;
  List<NearbyNotificationPlace> _latestPlaces = const [];
  StreamSubscription<NativeGeofenceEvent>? _nativeGeofenceSubscription;
  AppLifecycleListener? _lifecycleListener;
  String? _appliedGeofenceSignature;
  bool _geofenceSyncRunning = false;
  bool _geofenceSyncRequested = false;

  NearbyProximityMonitor({
    required this.crashlytics,
    required this.placeRepository,
    required this.nativeGeofenceService,
    required this.nearbyNotificationService,
  });

  void start() {
    _nativeGeofenceSubscription = nativeGeofenceService.events.listen((event) {
      unawaited(_handleNativeGeofenceEventSafely(event));
    });
    _lifecycleListener = AppLifecycleListener(
      onStateChange: (state) {
        unawaited(_handleLifecycleChange(state));
      },
    );
    unawaited(_processQueuedNativeGeofenceEvents());
  }

  void updatePlaces(List<NearbyNotificationPlace> places) {
    _latestPlaces = places;
    _logDiagnostic(
      'Nearby alert list updated '
      '(total=${places.length}, '
      'active=${places.where((place) => place.isActive).length}).',
    );
    if (places.isEmpty) {
      _latestPosition = null;
      _lastCheckedAt.clear();
    } else {
      unawaited(_syncNearbyAlertsForCurrentPosition());
    }
    unawaited(_requestOsGeofenceSync());
  }

  void updatePosition(Position position) {
    _latestPosition = position;
    if (_latestPlaces.isNotEmpty) {
      unawaited(_syncNearbyAlertsForCurrentPosition());
    }
  }

  Future<void> _writeDiagnostic(String message) async {
    final logMessage = '[NearbyGeofence] $message';
    debugPrint(logMessage);
    try {
      await crashlytics.log(logMessage);
    } catch (error, stack) {
      debugPrint(
        '[NearbyGeofence] Could not write Crashlytics breadcrumb: '
        '$error\n$stack',
      );
    }
  }

  void _logDiagnostic(String message) {
    unawaited(_writeDiagnostic(message));
  }

  Future<void> _reportError(
    String operation,
    Object error,
    StackTrace stack,
  ) async {
    debugPrint('[NearbyGeofence] Failed during $operation: $error\n$stack');
    try {
      await crashlytics.setCustomKey('nearby_geofence_operation', operation);
      await crashlytics.setCustomKey(
        'nearby_geofence_platform',
        defaultTargetPlatform.name,
      );
      await crashlytics.recordError(
        error,
        stack,
        reason: 'Nearby geofence failure: $operation',
        fatal: false,
      );
    } catch (crashlyticsError, crashlyticsStack) {
      debugPrint(
        '[NearbyGeofence] Could not report failure to Crashlytics: '
        '$crashlyticsError\n$crashlyticsStack',
      );
    }
  }

  Future<void> _checkAndNotifyNearbyUnread(String placeId) async {
    final last = _lastCheckedAt[placeId];
    if (last != null &&
        DateTime.now().difference(last).inMinutes <
            AppConfig.nearbyNotificationCheckCooldownMinutes) {
      return;
    }
    _lastCheckedAt[placeId] = DateTime.now();
    _logDiagnostic('Checking for unread nearby messages.');
    final result = await placeRepository.checkNearbyUnread(placeId);
    await nearbyNotificationService.showNearbyUnread(result);
    _logDiagnostic(
      result.hasUnread
          ? 'Unread nearby message found; local notification requested.'
          : 'No unread nearby message found.',
    );
  }

  Future<void> _handleNativeGeofenceEvent(NativeGeofenceEvent event) async {
    final eventAgeSeconds = DateTime.now()
        .difference(event.occurredAt)
        .inSeconds
        .clamp(0, 86400);
    _logDiagnostic(
      'Native ${event.transition.name} event received '
      '(ageSeconds=$eventAgeSeconds).',
    );
    final place = _latestPlaces
        .where((candidate) => candidate.placeId == event.placeId)
        .firstOrNull;
    if (place == null || !place.isActive) {
      _logDiagnostic('Native event ignored for an inactive alert.');
      return;
    }
    switch (event.transition) {
      case NativeGeofenceTransition.enter:
        final changed = await _inRangeStateSynchronizer.setState(
          placeId: event.placeId,
          inRange: true,
        );
        if (!changed) {
          _logDiagnostic('Duplicate native enter event ignored.');
          return;
        }
        _logDiagnostic('Native enter state synced to the server.');
        await _checkAndNotifyNearbyUnread(event.placeId);
      case NativeGeofenceTransition.exit:
        final changed = await _inRangeStateSynchronizer.setState(
          placeId: event.placeId,
          inRange: false,
        );
        if (!changed) {
          _logDiagnostic('Duplicate native exit event ignored.');
          return;
        }
        _logDiagnostic('Native exit state synced to the server.');
    }
  }

  Future<void> _handleNativeGeofenceEventSafely(
    NativeGeofenceEvent event,
  ) async {
    try {
      await _handleNativeGeofenceEvent(event);
    } catch (error, stack) {
      await _reportError(
        'handling native ${event.transition.name} event',
        error,
        stack,
      );
    }
  }

  Future<void> _processQueuedNativeGeofenceEvents() async {
    try {
      final events = await nativeGeofenceService.takePendingEvents();
      _logDiagnostic(
        'Loaded ${events.length} queued native geofence event(s).',
      );
      for (final event in events) {
        await _handleNativeGeofenceEventSafely(event);
      }
    } catch (error, stack) {
      await _reportError(
        'processing queued native geofence events',
        error,
        stack,
      );
    }
  }

  String _geofenceSignature(
    List<NearbyNotificationPlace> places,
    LocationPermission permission,
  ) {
    if (permission != LocationPermission.always) {
      return 'cleared:${permission.name}';
    }
    final activePlaces = places.where((place) => place.isActive).toList()
      ..sort((a, b) => a.placeId.compareTo(b.placeId));
    return activePlaces
        .map(
          (place) =>
              '${place.placeId}|${place.latitude}|${place.longitude}|'
              '${place.radiusMeters}',
        )
        .join(';');
  }

  Future<void> _requestOsGeofenceSync() async {
    _geofenceSyncRequested = true;
    if (_geofenceSyncRunning) return;

    _geofenceSyncRunning = true;
    try {
      while (_geofenceSyncRequested) {
        _geofenceSyncRequested = false;
        await _syncOsGeofenceRegistrationsOnce();
      }
    } finally {
      _geofenceSyncRunning = false;
    }
  }

  Future<void> _syncOsGeofenceRegistrationsOnce() async {
    try {
      final permission = await Geolocator.checkPermission();
      final signature = _geofenceSignature(_latestPlaces, permission);
      if (signature == _appliedGeofenceSignature) {
        _logDiagnostic(
          'Skipped OS geofence sync because its configuration is unchanged.',
        );
        return;
      }

      if (_latestPlaces.isEmpty || permission != LocationPermission.always) {
        await nativeGeofenceService.clearGeofences();
        _appliedGeofenceSignature = signature;
        _logDiagnostic(
          _latestPlaces.isEmpty
              ? 'Cleared OS geofences because no alerts are active.'
              : 'Cleared OS geofences because Always permission is '
                    'unavailable (permission=${permission.name}).',
        );
        return;
      }
      await nativeGeofenceService.syncGeofences(_latestPlaces);
      _appliedGeofenceSignature = signature;
      _logDiagnostic(
        'Synced ${_latestPlaces.where((place) => place.isActive).length} '
        'active alert(s) with the OS geofence service.',
      );
      await _processQueuedNativeGeofenceEvents();
    } catch (error, stack) {
      await _reportError('syncing OS geofence registrations', error, stack);
    }
  }

  Future<void> _syncNearbyAlertsForCurrentPosition() async {
    try {
      final position = _latestPosition;
      if (position == null || _latestPlaces.isEmpty) return;

      for (final place in _latestPlaces.where((place) => place.isActive)) {
        final distanceMeters = Geolocator.distanceBetween(
          position.latitude,
          position.longitude,
          place.latitude,
          place.longitude,
        );
        final isInRange = distanceMeters <= place.radiusMeters;
        final changed = await _inRangeStateSynchronizer.setState(
          placeId: place.placeId,
          inRange: isInRange,
          // An unknown initial state outside the radius does not need a
          // server write. Native exits remain authoritative and are written.
          assumeIfUnknown: !isInRange,
        );
        if (changed && isInRange) {
          _logDiagnostic(
            'Foreground position entered an alert radius '
            '(distanceMeters=${distanceMeters.round()}, '
            'radiusMeters=${place.radiusMeters}).',
          );
        } else if (changed) {
          _logDiagnostic(
            'Foreground position exited an alert radius '
            '(distanceMeters=${distanceMeters.round()}, '
            'radiusMeters=${place.radiusMeters}).',
          );
          continue;
        }

        if (isInRange) {
          await _checkAndNotifyNearbyUnread(place.placeId);
        }
      }
    } catch (error, stack) {
      await _reportError(
        'syncing nearby alerts for current position',
        error,
        stack,
      );
    }
  }

  Future<void> _clearForegroundPosition({
    required bool clearInRangeState,
  }) async {
    _latestPosition = null;

    final reportedInRangePlaceIds = {
      ..._inRangeStateSynchronizer.inRangePlaceIds,
      ..._latestPlaces
          .where((place) => place.inRange)
          .map((place) => place.placeId),
    };
    if (clearInRangeState && reportedInRangePlaceIds.isNotEmpty) {
      for (final placeId in reportedInRangePlaceIds) {
        try {
          await _inRangeStateSynchronizer.setState(
            placeId: placeId,
            inRange: false,
            // The Firestore snapshot may know about an in-range state that
            // predates this process's local synchronizer.
            confirmIfAssumed: _latestPlaces.any(
              (place) => place.placeId == placeId && place.inRange,
            ),
          );
        } catch (error, stack) {
          await _reportError(
            'clearing foreground in-range state',
            error,
            stack,
          );
        }
      }
    }
    _inRangeStateSynchronizer.forgetAll();
    _logDiagnostic('Foreground position state cleared.');
  }

  Future<void> _handleLifecycleChange(AppLifecycleState state) async {
    if (state == AppLifecycleState.resumed) {
      await _requestOsGeofenceSync();
      return;
    }
    if (state != AppLifecycleState.paused &&
        state != AppLifecycleState.hidden &&
        state != AppLifecycleState.detached) {
      return;
    }

    final permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.whileInUse) {
      await _clearForegroundPosition(clearInRangeState: true);
      _logDiagnostic(
        'Foreground-only in-range state cleared while app is backgrounded.',
      );
    } else {
      await _clearForegroundPosition(clearInRangeState: false);
    }
  }

  void dispose() {
    _nativeGeofenceSubscription?.cancel();
    _lifecycleListener?.dispose();
  }
}
