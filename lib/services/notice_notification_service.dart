import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';

import '../config/world_catalog.dart';
import '../config/world_routes.dart';

final class NotificationNoticeRoute {
  const NotificationNoticeRoute(this.notice);

  final WorldRoute notice;
}

class NoticeNotificationService {
  final FirebaseMessaging _messaging;

  StreamSubscription<NotificationNoticeRoute>? _noticeOpenSubscription;
  final _openedNoticeRoutes =
      StreamController<NotificationNoticeRoute>.broadcast();

  NoticeNotificationService({required FirebaseMessaging messaging})
    : _messaging = messaging {
    _startNotificationOpenHandling();
  }

  Future<NotificationNoticeRoute?> initialNoticeRouteFromLaunch() async {
    final message = await _messaging.getInitialMessage();
    return noticeRouteFromMessage(message);
  }

  Stream<NotificationNoticeRoute> get openedNoticeRoutes =>
      _openedNoticeRoutes.stream;

  Future<void> dispose() async {
    await _noticeOpenSubscription?.cancel();
    await _openedNoticeRoutes.close();
  }

  void _startNotificationOpenHandling() {
    _noticeOpenSubscription ??= FirebaseMessaging.onMessageOpenedApp
        .map(noticeRouteFromMessage)
        .where((route) => route != null)
        .cast<NotificationNoticeRoute>()
        .listen(_openedNoticeRoutes.add);
  }

  static NotificationNoticeRoute? noticeRouteFromMessage(
    RemoteMessage? message,
  ) {
    final data = message?.data;
    if (data?['type'] != 'notice') return null;
    final worldId = data?['worldId'];
    final noticeId = data?['noticeId'];
    if (worldId is! String ||
        worldId.isEmpty ||
        noticeId is! String ||
        noticeId.isEmpty) {
      return null;
    }
    return NotificationNoticeRoute(
      WorldRoute(worldId: WorldId(worldId), entityId: noticeId),
    );
  }
}
