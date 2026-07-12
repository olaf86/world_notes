import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:world_notes/domain/entities/message_entity.dart';
import 'package:world_notes/domain/entities/user_entity.dart';
import 'package:world_notes/presentation/widgets/note/message_bubble.dart';

void main() {
  group('MessageBubble', () {
    testWidgets('shows publish time for published scheduled messages', (
      tester,
    ) async {
      final publishAt = DateTime.now().subtract(const Duration(hours: 1));
      final createdAt = publishAt.subtract(const Duration(hours: 2));
      final message = MessageEntity(
        id: 'message-1',
        placeId: 'place-1',
        author: const UserEntity(id: 'user-1', name: 'Aki'),
        content: 'Published later',
        createdAt: createdAt,
        publishAt: publishAt,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: MessageBubble(message: message, isOwn: false)),
        ),
      );

      expect(
        find.text(DateFormat('HH:mm').format(publishAt.toLocal())),
        findsOneWidget,
      );
      expect(
        find.text(DateFormat('HH:mm').format(createdAt.toLocal())),
        findsNothing,
      );
    });

    testWidgets('debounces optimistic message likes', (tester) async {
      bool? requestedLiked;
      final now = DateTime.now();
      final message = MessageEntity(
        id: 'message-1',
        placeId: 'place-1',
        author: const UserEntity(id: 'user-1', name: 'Aki'),
        content: 'Likeable note',
        createdAt: now,
        publishAt: now,
        likeCount: 2,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MessageBubble(
              message: message,
              isOwn: false,
              canLike: true,
              onLikeChanged: (liked) async {
                requestedLiked = liked;
              },
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.favorite_border), findsOneWidget);
      expect(find.text('2'), findsOneWidget);

      await tester.tap(find.byTooltip('Like message'));
      await tester.pump();

      expect(requestedLiked, isNull);
      expect(find.byIcon(Icons.favorite), findsOneWidget);
      expect(find.text('3'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 799));
      expect(requestedLiked, isNull);

      await tester.pump(const Duration(milliseconds: 1));
      expect(requestedLiked, isTrue);
    });

    testWidgets('does not send when rapid toggles return to server state', (
      tester,
    ) async {
      var requestCount = 0;
      final now = DateTime.now();
      final message = MessageEntity(
        id: 'message-1',
        placeId: 'place-1',
        author: const UserEntity(id: 'user-1', name: 'Aki'),
        content: 'Likeable note',
        createdAt: now,
        publishAt: now,
        likeCount: 2,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MessageBubble(
              message: message,
              isOwn: false,
              canLike: true,
              onLikeChanged: (_) async {
                requestCount++;
              },
            ),
          ),
        ),
      );

      await tester.tap(find.byTooltip('Like message'));
      await tester.pump();
      await tester.tap(find.byTooltip('Unlike message'));
      await tester.pump(const Duration(milliseconds: 800));

      expect(requestCount, 0);
      expect(find.byIcon(Icons.favorite_border), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
    });
  });
}
