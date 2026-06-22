import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:world_notes/domain/entities/message_entity.dart';
import 'package:world_notes/domain/entities/place_entity.dart';
import 'package:world_notes/domain/entities/user_entity.dart';
import 'package:world_notes/presentation/providers/providers.dart';
import 'package:world_notes/presentation/screens/note/note_box_screen.dart';

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
              return Stream<List<MessageEntity>>.value(const []);
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
}
