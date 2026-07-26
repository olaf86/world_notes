import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:world_notes/config/app_config.dart';
import 'package:world_notes/domain/entities/message_entity.dart';
import 'package:world_notes/domain/entities/message_thread_item.dart';
import 'package:world_notes/domain/entities/user_entity.dart';
import 'package:world_notes/l10n/app_localizations.dart';
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
        isScheduled: true,
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
      expect(find.text('Scheduled'), findsOneWidget);
    });

    testWidgets('does not show a scheduled badge for immediate messages', (
      tester,
    ) async {
      final now = DateTime.now();
      final message = MessageEntity(
        id: 'message-1',
        placeId: 'place-1',
        author: const UserEntity(id: 'user-1', name: 'Aki'),
        content: 'Published now',
        createdAt: now,
        publishAt: now,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: MessageBubble(message: message, isOwn: false)),
        ),
      );

      expect(find.text('Scheduled'), findsNothing);
    });

    test('uses the recorded scheduling flag', () {
      final now = DateTime.now();
      final message = MessageEntity(
        id: 'message-1',
        placeId: 'place-1',
        author: const UserEntity(id: 'user-1', name: 'Aki'),
        content: 'Published now',
        createdAt: now,
        publishAt: now.add(const Duration(minutes: 1)),
        isScheduled: false,
      );

      expect(message.isScheduled, isFalse);
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
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MessageBubble(
              message: message,
              likeState: const MessageLikeState(count: 2),
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

      await tester.pump(
        AppConfig.likeDebounceDuration - const Duration(milliseconds: 1),
      );
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
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MessageBubble(
              message: message,
              likeState: const MessageLikeState(count: 2),
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
      await tester.pump(AppConfig.likeDebounceDuration);

      expect(requestCount, 0);
      expect(find.byIcon(Icons.favorite_border), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
    });

    testWidgets('offers blocking in another author message actions', (
      tester,
    ) async {
      var blocked = false;
      final now = DateTime.now();
      final message = MessageEntity(
        id: 'message-1',
        placeId: 'place-1',
        author: const UserEntity(id: 'user-1', name: 'Aki'),
        content: 'Message from another user',
        createdAt: now,
        publishAt: now,
      );

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: MessageBubble(
              message: message,
              isOwn: false,
              onBlock: () => blocked = true,
            ),
          ),
        ),
      );

      await tester.longPress(find.text(message.content));
      await tester.pumpAndSettle();
      expect(find.text('Block user'), findsOneWidget);

      await tester.tap(find.text('Block user'));
      await tester.pumpAndSettle();
      expect(blocked, isTrue);
    });
  });
}
