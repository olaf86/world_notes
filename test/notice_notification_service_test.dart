import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:world_notes/services/notice_notification_service.dart';

void main() {
  test('notice notification resolves a world-routed identifier', () {
    final route = NoticeNotificationService.noticeRouteFromMessage(
      const RemoteMessage(
        data: {'type': 'notice', 'worldId': 'asia', 'noticeId': 'notice-1'},
      ),
    );

    expect(route?.notice.persistentId, 'asia:notice-1');
  });

  test('notice notification rejects a legacy ID without a world', () {
    final route = NoticeNotificationService.noticeRouteFromMessage(
      const RemoteMessage(data: {'type': 'notice', 'noticeId': 'notice-1'}),
    );

    expect(route, isNull);
  });
}
