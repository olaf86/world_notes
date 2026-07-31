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
