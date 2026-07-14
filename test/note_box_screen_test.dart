import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:world_notes/domain/entities/message_thread_item.dart';
import 'package:world_notes/domain/entities/place_entity.dart';
import 'package:world_notes/domain/entities/user_entity.dart';
import 'package:world_notes/presentation/providers/providers.dart';
import 'package:world_notes/presentation/screens/note/note_box_screen.dart';
import 'package:world_notes/presentation/widgets/map/static_note_mini_map.dart';

void main() {
  testWidgets(
    'does not subscribe to messages while the note is still loading',
    (tester) async {
      var messageSubscriptionCount = 0;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            isPremiumProvider.overrideWith((ref) => Stream.value(true)),
            authStateProvider.overrideWith(
              (ref) => Stream<UserEntity?>.value(null),
            ),
            placeProvider.overrideWith(
              (ref, String placeId) => const Stream<PlaceEntity?>.empty(),
            ),
            messagesProvider.overrideWith((ref, String placeId) {
              messageSubscriptionCount++;
              return Stream<List<MessageThreadItem>>.value(const []);
            }),
          ],
          child: const MaterialApp(
            home: NoteBoxScreen(
              placeId: 'private-note',
              placeTitle: 'Private note',
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(messageSubscriptionCount, 0);
    },
  );

  testWidgets('shows one mini map for a loaded note', (tester) async {
    final now = DateTime.now();
    final place = PlaceEntity(
      id: 'place-1',
      latitude: 35.6812,
      longitude: 139.7671,
      geohash: 'xn76u',
      title: 'Tokyo Station',
      colorHex: '#4CAF50',
      icon: 'place',
      createdByUserId: 'owner-1',
      creatorName: 'Owner',
      creatorPhotoVersion: 1,
      createdAt: now,
      publishAt: now.subtract(const Duration(days: 1)),
      expiresAt: now.add(const Duration(days: 7)),
      likeCount: 0,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          isPremiumProvider.overrideWith((ref) => Stream.value(true)),
          authStateProvider.overrideWith(
            (ref) => Stream<UserEntity?>.value(null),
          ),
          placeProvider.overrideWith(
            (ref, String placeId) => Stream.value(place),
          ),
          userProfileProvider.overrideWith(
            (ref, String userId) => Stream<UserEntity?>.value(
              const UserEntity(id: 'owner-1', name: 'Alice'),
            ),
          ),
          messagesProvider.overrideWith(
            (ref, String placeId) =>
                Stream<List<MessageThreadItem>>.value(const []),
          ),
        ],
        child: const MaterialApp(
          home: NoteBoxScreen(placeId: 'place-1', placeTitle: 'Tokyo Station'),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(StaticNoteMiniMap), findsOneWidget);
  });

  testWidgets('opens the creator profile from the mini map', (tester) async {
    final now = DateTime.now();
    final place = PlaceEntity(
      id: 'place-1',
      latitude: 35.6812,
      longitude: 139.7671,
      geohash: 'xn76u',
      title: 'Tokyo Station',
      colorHex: '#4CAF50',
      icon: 'place',
      createdByUserId: 'owner-1',
      creatorName: 'Owner',
      creatorPhotoVersion: 1,
      createdAt: now,
      publishAt: now.subtract(const Duration(days: 1)),
      expiresAt: now.add(const Duration(days: 7)),
      likeCount: 0,
    );
    final router = GoRouter(
      initialLocation: '/note',
      routes: [
        GoRoute(
          path: '/note',
          builder: (_, _) => const NoteBoxScreen(
            placeId: 'place-1',
            placeTitle: 'Tokyo Station',
          ),
        ),
        GoRoute(
          path: '/users/:userId',
          builder: (_, state) => Scaffold(
            body: Text('Profile: ${state.pathParameters['userId']}'),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          isPremiumProvider.overrideWith((ref) => Stream.value(true)),
          authStateProvider.overrideWith(
            (ref) => Stream<UserEntity?>.value(null),
          ),
          placeProvider.overrideWith(
            (ref, String placeId) => Stream.value(place),
          ),
          userProfileProvider.overrideWith(
            (ref, String userId) => Stream<UserEntity?>.value(
              const UserEntity(id: 'owner-1', name: 'Alice'),
            ),
          ),
          messagesProvider.overrideWith(
            (ref, String placeId) =>
                Stream<List<MessageThreadItem>>.value(const []),
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pump();

    tester
        .widget<InkWell>(find.byKey(const ValueKey('creator-map-overlay')))
        .onTap!();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Profile: owner-1'), findsOneWidget);
  });
}
