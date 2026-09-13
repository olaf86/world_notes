import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:world_notes/config/notification_navigation.dart';
import 'package:world_notes/config/world_catalog.dart';
import 'package:world_notes/config/world_routes.dart';
import 'package:world_notes/services/my_notes_notification_service.dart';

void main() {
  test('FCM message data maps My Notes notifications to read-only routes', () {
    final route = MyNotesNotificationService.placeRouteFromMessageData({
      'type': 'my_note_message',
      'worldId': 'asia',
      'placeId': 'place-1',
    });

    expect(route?.placeId, 'place-1');
    expect(route?.readOnly, isTrue);
    expect(route?.note.worldId, const WorldId('asia'));
    expect(route?.location, '/worlds/asia/notes/place-1?readOnly=true');
  });

  test('FCM message data rejects a legacy place ID without a world', () {
    expect(
      MyNotesNotificationService.placeRouteFromMessageData({
        'type': 'my_note_message',
        'placeId': 'place-1',
      }),
      isNull,
    );
  });

  test('map mention action parses the target location and message', () {
    final target = notificationMapNoteTargetFromAction('mapNote', {
      'worldId': 'asia',
      'placeId': 'place-1',
      'messageId': 'message-1',
      'latitude': 35.6812,
      'longitude': 139.7671,
    });

    expect(target?.worldId, const WorldId('asia'));
    expect(target?.placeId, 'place-1');
    expect(target?.messageId, 'message-1');
    expect(target?.latitude, 35.6812);
    expect(target?.longitude, 139.7671);
  });

  test('user profile action accepts only a non-empty user id', () {
    expect(
      notificationUserIdFromAction('userProfile', {'userId': 'alice'}),
      'alice',
    );
    expect(notificationUserIdFromAction('userProfile', const {}), isNull);
    expect(
      notificationUserIdFromAction('unknown', {'userId': 'alice'}),
      isNull,
    );
  });

  test('administrator invitation action builds its allowlisted route', () {
    final target = notificationAdministratorInvitationTargetFromAction(
      'administratorInvitation',
      {'worldId': 'europe', 'token': 'invite-token'},
    );

    expect(target?.worldId, const WorldId('europe'));
    expect(target?.token, 'invite-token');
    expect(target?.location, '/worlds/europe/invites/invite-token');
  });

  test('subscription action rejects unexpected parameters', () {
    expect(notificationOpensSubscription('subscription', const {}), isTrue);
    expect(
      notificationOpensSubscription('subscription', {'path': '/settings'}),
      isFalse,
    );
  });

  testWidgets('notification navigation pushes note over map', (tester) async {
    final router = GoRouter(
      initialLocation: '/map',
      routes: [
        GoRoute(
          path: '/map',
          builder: (context, state) => const Scaffold(body: Text('Map')),
        ),
        GoRoute(
          path: '/worlds/:worldId/notes/:placeId',
          builder: (context, state) => Scaffold(
            body: Text(
              'Note ${state.pathParameters['placeId']} '
              'readOnly=${state.uri.queryParameters['readOnly']}',
            ),
          ),
        ),
      ],
    );

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    expect(find.text('Map'), findsOneWidget);

    openNotificationPlace(
      router,
      NotificationPlaceRoute(
        note: WorldRoute(worldId: const WorldId('asia'), entityId: 'place-1'),
        readOnly: true,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Note place-1 readOnly=true'), findsOneWidget);
    expect(router.canPop(), isTrue);

    router.pop();
    await tester.pumpAndSettle();

    expect(find.text('Map'), findsOneWidget);
  });

  testWidgets('notification navigation ignores missing place id', (
    tester,
  ) async {
    final router = GoRouter(
      initialLocation: '/map',
      routes: [
        GoRoute(
          path: '/map',
          builder: (context, state) => const Scaffold(body: Text('Map')),
        ),
        GoRoute(
          path: '/worlds/:worldId/notes/:placeId',
          builder: (context, state) =>
              Scaffold(body: Text('Note ${state.pathParameters['placeId']}')),
        ),
      ],
    );

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    openNotificationPlace(router, null);
    await tester.pumpAndSettle();

    expect(find.text('Map'), findsOneWidget);
    expect(router.canPop(), isFalse);
  });
}
