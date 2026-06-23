import 'dart:async';

import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:geolocator/geolocator.dart';

import '../config/app_config.dart';
import '../domain/entities/nearby_notification_entity.dart';
import '../domain/repositories/place_repository.dart';
import 'location_service.dart';
import 'native_geofence_service.dart';
import 'nearby_notification_service.dart';

/// Coordinates foreground proximity checks and background OS geofences for
/// notes whose nearby alerts are enabled.
///
/// [_inRangePlaceIds] tracks notes for which this device has reported an active
/// "inside the notification radius" state to the server. The server uses that
/// short-lived state to decide whether a new message should trigger an alert.
class NearbyProximityMonitor {
  final FirebaseCrashlytics crashlytics;
  final PlaceRepository placeRepository;
  final LocationService locationService;
  final NativeGeofenceService nativeGeofenceService;
  final NearbyNotificationService nearbyNotificationService;

  final Set<String> _inRangePlaceIds = {};
  final Map<String, DateTime> _lastCheckedAt = {};

  Position? _latestPosition;
  List<NearbyNotificationPlace> _latestPlaces = const [];
  StreamSubscription<Position>? _positionSubscription;
  StreamSubscription<NativeGeofenceEvent>? _nativeGeofenceSubscription;
  AppLifecycleListener? _lifecycleListener;

  NearbyProximityMonitor({
    required this.crashlytics,
    required this.placeRepository,
    required this.locationService,
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
      unawaited(_stopPositionMonitoringIfUnused());
    } else {
      unawaited(_ensurePositionMonitoring());
      unawaited(_syncNearbyAlertsForCurrentPosition());
    }
    unawaited(_syncOsGeofenceRegistrations());
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
        _inRangePlaceIds.add(event.placeId);
        await placeRepository.markNearbyNotificationInRange(
          placeId: event.placeId,
          inRange: true,
        );
        _logDiagnostic('Native enter state synced to the server.');
        await _checkAndNotifyNearbyUnread(event.placeId);
      case NativeGeofenceTransition.exit:
        _inRangePlaceIds.remove(event.placeId);
        await placeRepository.markNearbyNotificationInRange(
          placeId: event.placeId,
          inRange: false,
        );
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

  Future<void> _syncOsGeofenceRegistrations() async {
    try {
      if (_latestPlaces.isEmpty) {
        await nativeGeofenceService.clearGeofences();
        _logDiagnostic('Cleared OS geofences because no alerts are active.');
        return;
      }
      final permission = await Geolocator.checkPermission();
      if (permission != LocationPermission.always) {
        await nativeGeofenceService.clearGeofences();
        _logDiagnostic(
          'Cleared OS geofences because Always permission is unavailable '
          '(permission=${permission.name}).',
        );
        return;
      }
      await nativeGeofenceService.syncGeofences(_latestPlaces);
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
        final wasInRange = _inRangePlaceIds.contains(place.placeId);
        if (isInRange && !wasInRange) {
          _inRangePlaceIds.add(place.placeId);
          _logDiagnostic(
            'Foreground position entered an alert radius '
            '(distanceMeters=${distanceMeters.round()}, '
            'radiusMeters=${place.radiusMeters}).',
          );
          await placeRepository.markNearbyNotificationInRange(
            placeId: place.placeId,
            inRange: true,
          );
        } else if (!isInRange && wasInRange) {
          _inRangePlaceIds.remove(place.placeId);
          _logDiagnostic(
            'Foreground position exited an alert radius '
            '(distanceMeters=${distanceMeters.round()}, '
            'radiusMeters=${place.radiusMeters}).',
          );
          await placeRepository.markNearbyNotificationInRange(
            placeId: place.placeId,
            inRange: false,
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

  Future<void> _ensurePositionMonitoring() async {
    if (_positionSubscription != null || _latestPlaces.isEmpty) return;
    final permission = await Geolocator.checkPermission();
    if (permission != LocationPermission.always &&
        permission != LocationPermission.whileInUse) {
      _logDiagnostic(
        'Foreground position monitoring not started '
        '(permission=${permission.name}).',
      );
      return;
    }
    _positionSubscription = locationService.watchPosition().listen(
      (position) {
        _latestPosition = position;
        unawaited(_syncNearbyAlertsForCurrentPosition());
      },
      onError: (Object error, StackTrace stack) {
        unawaited(_reportError('watching foreground position', error, stack));
      },
    );
    _logDiagnostic('Foreground position monitoring started.');
  }

  Future<void> _stopForegroundPositionMonitoring({
    required bool clearInRangeState,
  }) async {
    await _positionSubscription?.cancel();
    _positionSubscription = null;
    _latestPosition = null;

    final reportedInRangePlaceIds = {
      ..._inRangePlaceIds,
      ..._latestPlaces
          .where((place) => place.inRange)
          .map((place) => place.placeId),
    };
    if (clearInRangeState && reportedInRangePlaceIds.isNotEmpty) {
      _inRangePlaceIds.clear();
      for (final placeId in reportedInRangePlaceIds) {
        try {
          await placeRepository.markNearbyNotificationInRange(
            placeId: placeId,
            inRange: false,
          );
        } catch (error, stack) {
          await _reportError(
            'clearing foreground in-range state',
            error,
            stack,
          );
        }
      }
    } else {
      _inRangePlaceIds.clear();
    }
    _logDiagnostic('Foreground position monitoring stopped.');
  }

  Future<void> _stopPositionMonitoringIfUnused() async {
    if (_latestPlaces.isNotEmpty) return;
    await _stopForegroundPositionMonitoring(clearInRangeState: false);
    _lastCheckedAt.clear();
  }

  Future<void> _handleLifecycleChange(AppLifecycleState state) async {
    if (state == AppLifecycleState.resumed) {
      await _ensurePositionMonitoring();
      await _syncNearbyAlertsForCurrentPosition();
      await _syncOsGeofenceRegistrations();
      return;
    }
    if (state != AppLifecycleState.paused &&
        state != AppLifecycleState.hidden &&
        state != AppLifecycleState.detached) {
      return;
    }

    final permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.whileInUse) {
      await _stopForegroundPositionMonitoring(clearInRangeState: true);
      _logDiagnostic(
        'Foreground-only in-range state cleared while app is backgrounded.',
      );
    }
  }

  void dispose() {
    _positionSubscription?.cancel();
    _nativeGeofenceSubscription?.cancel();
    _lifecycleListener?.dispose();
  }
}
