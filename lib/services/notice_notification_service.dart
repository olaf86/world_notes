import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';

class NoticeNotificationService {
  final FirebaseMessaging _messaging;

  StreamSubscription<String>? _noticeOpenSubscription;
  final _openedNoticeIds = StreamController<String>.broadcast();

  NoticeNotificationService({required FirebaseMessaging messaging})
    : _messaging = messaging {
    _startNotificationOpenHandling();
  }

  Future<String?> initialNoticeIdFromLaunch() async {
    final message = await _messaging.getInitialMessage();
    return noticeIdFromMessage(message);
  }

  Stream<String> get openedNoticeIds => _openedNoticeIds.stream;

  Future<void> dispose() async {
    await _noticeOpenSubscription?.cancel();
    await _openedNoticeIds.close();
  }

  void _startNotificationOpenHandling() {
    _noticeOpenSubscription ??= FirebaseMessaging.onMessageOpenedApp
        .map(noticeIdFromMessage)
        .where((noticeId) => noticeId != null)
        .cast<String>()
        .listen(_openedNoticeIds.add);
  }

  static String? noticeIdFromMessage(RemoteMessage? message) {
    final data = message?.data;
    if (data?['type'] != 'notice') return null;
    final noticeId = data?['noticeId'];
    return noticeId is String && noticeId.isNotEmpty ? noticeId : null;
  }
}
