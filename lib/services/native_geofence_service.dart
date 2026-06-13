import 'dart:async';

import 'package:flutter/services.dart';

import '../domain/entities/nearby_notification_entity.dart';

enum NativeGeofenceTransition { enter, exit }

class NativeGeofenceEvent {
  final String placeId;
  final NativeGeofenceTransition transition;
  final DateTime occurredAt;

  const NativeGeofenceEvent({
    required this.placeId,
    required this.transition,
    required this.occurredAt,
  });

  static NativeGeofenceEvent? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final placeId = raw['placeId'] as String?;
    final transitionValue = raw['transition'] as String?;
    final timestampMillis = raw['timestampMillis'] as int?;
    if (placeId == null || placeId.isEmpty || transitionValue == null) {
      return null;
    }
    final transition = switch (transitionValue) {
      'enter' => NativeGeofenceTransition.enter,
      'exit' => NativeGeofenceTransition.exit,
      _ => null,
    };
    if (transition == null) return null;
    return NativeGeofenceEvent(
      placeId: placeId,
      transition: transition,
      occurredAt: DateTime.fromMillisecondsSinceEpoch(
        timestampMillis ?? DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }
}

class NativeGeofenceService {
  static const MethodChannel _channel = MethodChannel('world_notes/geofence');

  final _events = StreamController<NativeGeofenceEvent>.broadcast();

  NativeGeofenceService() {
    _channel.setMethodCallHandler(_handleMethodCall);
  }

  Stream<NativeGeofenceEvent> get events => _events.stream;

  Future<void> syncGeofences(List<NearbyNotificationPlace> places) async {
    final geofences = places
        .where((place) => place.isActive)
        .map(
          (place) => {
            'placeId': place.placeId,
            'latitude': place.latitude,
            'longitude': place.longitude,
            'radiusMeters': place.radiusMeters,
          },
        )
        .toList(growable: false);
    await _channel.invokeMethod<void>('syncGeofences', {
      'geofences': geofences,
    });
  }

  Future<void> clearGeofences() async {
    await _channel.invokeMethod<void>('clearGeofences');
  }

  Future<List<NativeGeofenceEvent>> takePendingEvents() async {
    final raw = await _channel.invokeMethod<List<dynamic>>('takePendingEvents');
    return (raw ?? const [])
        .map(NativeGeofenceEvent.fromMap)
        .nonNulls
        .toList(growable: false);
  }

  Future<void> _handleMethodCall(MethodCall call) async {
    if (call.method != 'geofenceEvent') return;
    final event = NativeGeofenceEvent.fromMap(call.arguments);
    if (event != null) _events.add(event);
  }

  Future<void> dispose() async {
    _channel.setMethodCallHandler(null);
    await _events.close();
  }
}
