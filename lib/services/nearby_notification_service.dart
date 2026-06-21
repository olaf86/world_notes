import 'dart:async';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/foundation.dart';

import '../domain/entities/nearby_notification_entity.dart';

class NearbyNotificationService {
  static const _channelId = 'nearby_note_alerts';
  static const _channelName = 'Nearby Note Alerts';
  static const _channelDescription =
      'Notifications shown when followed notes nearby have new messages.';

  final FlutterLocalNotificationsPlugin _notifications;
  final _openedPlaceIds = StreamController<String>.broadcast();
  bool _initialized = false;

  NearbyNotificationService({
    required FlutterLocalNotificationsPlugin notifications,
  }) : _notifications = notifications;

  Stream<String> get openedPlaceIds => _openedPlaceIds.stream;

  Future<String?> initialPlaceIdFromLaunch() async {
    await initialize();
    final details = await _notifications.getNotificationAppLaunchDetails();
    if (details?.didNotificationLaunchApp != true) return null;
    final payload = details?.notificationResponse?.payload;
    return payload != null && payload.isNotEmpty ? payload : null;
  }

  Future<void> initialize() async {
    if (_initialized) return;
    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const darwinSettings = DarwinInitializationSettings();
    const settings = InitializationSettings(
      android: androidSettings,
      iOS: darwinSettings,
      macOS: darwinSettings,
    );

    await _notifications.initialize(
      settings: settings,
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload;
        if (payload != null && payload.isNotEmpty) {
          _openedPlaceIds.add(payload);
        }
      },
    );
    _initialized = true;
    debugPrint('[NearbyGeofence] Local notification service initialized.');
  }

  Future<bool> requestPermission() async {
    await initialize();
    final androidGranted =
        await _notifications
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >()
            ?.requestNotificationsPermission() ??
        true;
    final iosGranted =
        await _notifications
            .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin
            >()
            ?.requestPermissions(alert: true, badge: true, sound: true) ??
        true;
    final macosGranted =
        await _notifications
            .resolvePlatformSpecificImplementation<
              MacOSFlutterLocalNotificationsPlugin
            >()
            ?.requestPermissions(alert: true, badge: true, sound: true) ??
        true;
    debugPrint(
      '[NearbyGeofence] Notification permission result '
      '(android=$androidGranted, ios=$iosGranted, macos=$macosGranted).',
    );
    return androidGranted && iosGranted && macosGranted;
  }

  Future<void> showNearbyUnread(NearbyUnreadResult result) async {
    final placeId = result.placeId;
    if (!result.hasUnread || placeId == null || placeId.isEmpty) {
      debugPrint(
        '[NearbyGeofence] Local notification skipped because there is '
        'no unread message.',
      );
      return;
    }
    await initialize();
    final title = result.title?.trim().isNotEmpty == true
        ? result.title!.trim()
        : 'Nearby note';

    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDescription,
        importance: Importance.high,
        priority: Priority.high,
      ),
      iOS: DarwinNotificationDetails(presentSound: true),
      macOS: DarwinNotificationDetails(presentSound: true),
    );
    await _notifications.show(
      id: placeId.hashCode,
      title: 'World Notes',
      body: '$title has new messages nearby.',
      notificationDetails: details,
      payload: placeId,
    );
    debugPrint('[NearbyGeofence] Local nearby notification displayed.');
  }

  Future<void> dispose() async {
    await _openedPlaceIds.close();
  }
}
