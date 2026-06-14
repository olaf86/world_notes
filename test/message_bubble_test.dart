import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:world_notes/core/theme/app_theme.dart';
import 'package:world_notes/domain/entities/message_entity.dart';
import 'package:world_notes/domain/entities/user_entity.dart';
import 'package:world_notes/presentation/widgets/note/message_bubble.dart';

void main() {
  group('MessageBubble', () {
    testWidgets('shows publish time for published scheduled messages', (
      tester,
    ) async {
      final createdAt = DateTime.utc(2026, 6, 10, 1, 15);
      final publishAt = DateTime.utc(2026, 6, 10, 3, 45);
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
          theme: AppTheme.light,
          home: Scaffold(body: MessageBubble(message: message, isOwn: false)),
        ),
      );

      expect(
        find.text(DateFormat('MMM d, HH:mm').format(publishAt.toLocal())),
        findsOneWidget,
      );
      expect(
        find.text(DateFormat('MMM d, HH:mm').format(createdAt.toLocal())),
        findsNothing,
      );
    });

    testWidgets('uses native emoji font fallback for message content', (
      tester,
    ) async {
      final createdAt = DateTime.utc(2026, 6, 10, 1, 15);
      final message = MessageEntity(
        id: 'message-emoji',
        placeId: 'place-1',
        author: const UserEntity(id: 'user-1', name: 'Aki'),
        content: 'Hello 🌍',
        createdAt: createdAt,
        publishAt: createdAt,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(body: MessageBubble(message: message, isOwn: false)),
        ),
      );

      final contentText = tester.widget<Text>(find.text('Hello 🌍'));
      expect(
        contentText.style?.fontFamilyFallback,
        containsAll(<String>[
          'Apple Color Emoji',
          'Noto Color Emoji',
          'Segoe UI Emoji',
        ]),
      );
    });
  });
}
