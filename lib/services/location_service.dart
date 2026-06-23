import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:geolocator/geolocator.dart';

class LocationPermissionDeniedException implements Exception {
  final bool permanentlyDenied;
  const LocationPermissionDeniedException({this.permanentlyDenied = false});

  @override
  String toString() =>
      'LocationPermissionDeniedException('
      'permanentlyDenied: $permanentlyDenied)';
}

class LocationService {
  /// Checks the current permission and requests it if not yet determined.
  /// Returns the final [LocationPermission] after any request dialog.
  Future<LocationPermission> ensurePermission() async {
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    return permission;
  }

  /// Live position stream. Yields the cached last-known position first (if
  /// available) so callers can render instantly, then continues with live
  /// GPS updates. Throws [LocationPermissionDeniedException] when permission
  /// is denied so [StreamProvider]s can surface the denial as an error state.
  Stream<Position> watchPosition() {
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
        final permission = await ensurePermission();
        if (disposed || !isForeground) return;
        if (permission == LocationPermission.denied) {
          controller.addError(const LocationPermissionDeniedException());
          return;
        }
        if (permission == LocationPermission.deniedForever) {
          controller.addError(
            const LocationPermissionDeniedException(permanentlyDenied: true),
          );
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
