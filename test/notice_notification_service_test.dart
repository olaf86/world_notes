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

  test('mention notice carries a map target without opening the note', () {
    final route = NoticeNotificationService.noticeRouteFromMessage(
      const RemoteMessage(
        data: {
          'type': 'notice',
          'worldId': 'asia',
          'noticeId': 'notice-1',
          'actionRoute': 'mapNote',
          'actionWorldId': 'europe',
          'actionPlaceId': 'place-1',
          'actionMessageId': 'message-1',
          'actionLatitude': '35.6812',
          'actionLongitude': '139.7671',
        },
      ),
    );

    expect(route?.notice.persistentId, 'asia:notice-1');
    expect(route?.mapTarget?.worldId.value, 'europe');
    expect(route?.mapTarget?.placeId, 'place-1');
    expect(route?.mapTarget?.messageId, 'message-1');
    expect(route?.mapTarget?.latitude, 35.6812);
    expect(route?.mapTarget?.longitude, 139.7671);
  });
}
