import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:geolocator/geolocator.dart';

import '../config/runtime_mode.dart';

class LocationPermissionDeniedException implements Exception {
  final bool permanentlyDenied;
  const LocationPermissionDeniedException({this.permanentlyDenied = false});

  @override
  String toString() =>
      'LocationPermissionDeniedException('
      'permanentlyDenied: $permanentlyDenied)';
}

enum LocationAvailabilityIssue {
  permissionDenied,
  permissionPermanentlyDenied,
  serviceDisabled,
}

LocationAvailabilityIssue? locationAvailabilityIssueFromPermission(
  LocationPermission permission,
) {
  return switch (permission) {
    LocationPermission.denied || LocationPermission.unableToDetermine =>
      LocationAvailabilityIssue.permissionDenied,
    LocationPermission.deniedForever =>
      LocationAvailabilityIssue.permissionPermanentlyDenied,
    LocationPermission.whileInUse || LocationPermission.always => null,
  };
}

LocationAvailabilityIssue? locationAvailabilityIssueFromError(Object? error) {
  if (error is LocationPermissionDeniedException) {
    return error.permanentlyDenied
        ? LocationAvailabilityIssue.permissionPermanentlyDenied
        : LocationAvailabilityIssue.permissionDenied;
  }
  if (error is LocationServiceDisabledException) {
    return LocationAvailabilityIssue.serviceDisabled;
  }
  return null;
}

extension LocationAvailabilityIssueException on LocationAvailabilityIssue {
  Exception toException() {
    return switch (this) {
      LocationAvailabilityIssue.permissionDenied =>
        const LocationPermissionDeniedException(),
      LocationAvailabilityIssue.permissionPermanentlyDenied =>
        const LocationPermissionDeniedException(permanentlyDenied: true),
      LocationAvailabilityIssue.serviceDisabled =>
        const LocationServiceDisabledException(),
    };
  }
}

class LocationService {
  LocationService({
    Future<LocationPermission> Function()? permissionChecker,
    Future<LocationPermission> Function()? permissionRequester,
  }) : _permissionChecker = permissionChecker ?? Geolocator.checkPermission,
       _permissionRequester =
           permissionRequester ?? Geolocator.requestPermission;

  final Future<LocationPermission> Function() _permissionChecker;
  final Future<LocationPermission> Function() _permissionRequester;

  Position _screenshotPosition() {
    return Position(
      latitude: screenshotLatitude,
      longitude: screenshotLongitude,
      timestamp: DateTime.now(),
      accuracy: 5,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );
  }

  /// Checks the current permission and requests it if not yet determined.
  /// Returns the final [LocationPermission] after any request dialog.
  Future<LocationPermission> ensurePermission() async {
    if (screenshotMode) return LocationPermission.whileInUse;
    var permission = await _permissionChecker();
    if (permission == LocationPermission.denied) {
      permission = await _permissionRequester();
    }
    return permission;
  }

  Future<LocationAvailabilityIssue?> ensureLocationAvailable() async {
    if (screenshotMode) return null;
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return LocationAvailabilityIssue.serviceDisabled;

    final permission = await ensurePermission();
    return locationAvailabilityIssueFromPermission(permission);
  }

  /// Retrieves the user's current GPS position for actions that need a final
  /// point-in-time location, such as confirming note creation.
  Future<Position> getCurrentPosition() async {
    if (screenshotMode) return _screenshotPosition();

    final issue = await ensureLocationAvailable();
    if (issue != null) throw issue.toException();

    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    );
  }

  /// Live position stream. Yields the cached last-known position first (if
  /// available) so callers can render instantly, then continues with live
  /// GPS updates. Throws [LocationPermissionDeniedException] when permission
  /// is denied so [StreamProvider]s can surface the denial as an error state.
  Stream<Position> watchPosition() {
    if (screenshotMode) {
      return Stream<Position>.value(_screenshotPosition());
    }

    StreamSubscription<Position>? positionSubscription;
    AppLifecycleListener? lifecycleListener;
    var isForeground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    var startInProgress = false;
    var disposed = false;

    late final StreamController<Position> controller;

    Future<void> stopPositionUpdates() async {
      await positionSubscription?.cancel();
      positionSubscription = null;
    }

    Future<void> startPositionUpdates() async {
      if (disposed ||
          !isForeground ||
          startInProgress ||
          positionSubscription != null) {
        return;
      }
      startInProgress = true;
      try {
        final issue = await ensureLocationAvailable();
        if (disposed || !isForeground) return;
        if (issue != null) {
          controller.addError(issue.toException());
          return;
        }

        final lastKnown = await Geolocator.getLastKnownPosition();
        if (disposed || !isForeground) return;
        if (lastKnown != null) controller.add(lastKnown);

        positionSubscription = Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 20,
          ),
        ).listen(controller.add, onError: controller.addError);
      } catch (error, stack) {
        if (!disposed) controller.addError(error, stack);
      } finally {
        startInProgress = false;
      }
    }

    controller = StreamController<Position>(
      onListen: () {
        lifecycleListener = AppLifecycleListener(
          onStateChange: (state) {
            if (state == AppLifecycleState.resumed) {
              isForeground = true;
              unawaited(startPositionUpdates());
            } else if (state == AppLifecycleState.paused ||
                state == AppLifecycleState.hidden ||
                state == AppLifecycleState.detached) {
              isForeground = false;
              unawaited(stopPositionUpdates());
            }
          },
        );
        unawaited(startPositionUpdates());
      },
      onCancel: () async {
        disposed = true;
        lifecycleListener?.dispose();
        await stopPositionUpdates();
      },
    );
    return controller.stream;
  }
}
