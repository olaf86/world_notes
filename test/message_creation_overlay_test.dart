import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:world_notes/domain/entities/message_entity.dart';
import 'package:world_notes/domain/entities/mention_target.dart';
import 'package:world_notes/domain/entities/user_entity.dart';
import 'package:world_notes/domain/repositories/message_repository.dart';
import 'package:world_notes/l10n/app_localizations.dart';
import 'package:world_notes/presentation/providers/providers.dart';
import 'package:world_notes/presentation/widgets/note/message_creation_overlay.dart';

void main() {
  testWidgets('selects a participant and sends a structured mention', (
    tester,
  ) async {
    final repository = _MentionMessageRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authStateProvider.overrideWith(
            (ref) => Stream.value(const UserEntity(id: 'sender', name: 'Kai')),
          ),
          messageRepositoryProvider.overrideWithValue(repository),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Consumer(
            builder: (context, ref, _) {
              ref.watch(authStateProvider);
              return Scaffold(
                body: MessageCreationOverlay(
                  placeId: 'place-1',
                  onClose: () {},
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.alternate_email));
    await tester.pump();
    await tester.pump();

    expect(repository.candidateRequests, 1);
    expect(find.text('Mina'), findsOneWidget);
    await tester.tap(find.text('Mina'));
    await tester.pump();
    expect(
      tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
      isTrue,
    );
    await tester.tap(find.text('Done'));
    await tester.pump();

    expect(find.text('Mina'), findsOneWidget);
    final scheduleButton = tester.widget<TextButton>(
      find.widgetWithIcon(TextButton, Icons.schedule),
    );
    expect(scheduleButton.onPressed, isNull);

    await tester.enterText(find.byType(TextField), 'Hello Mina');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Send'));
    await tester.pump();

    expect(repository.sentContent, 'Hello Mina');
    expect(repository.sentMentions, const [
      MentionTarget(userId: 'mina', displayName: 'Mina'),
    ]);
    expect(repository.sentPublishAt, isNull);
  });
}

class _MentionMessageRepository implements MessageRepository {
  var candidateRequests = 0;
  List<MentionTarget> sentMentions = const [];
  String? sentContent;
  DateTime? sentPublishAt;

  @override
  Future<List<MentionTarget>> listMentionCandidates({
    required String placeId,
    String query = '',
    int limit = 20,
  }) async {
    candidateRequests += 1;
    return const [MentionTarget(userId: 'mina', displayName: 'Mina')];
  }

  @override
  Future<MessageEntity> sendMessage({
    String? id,
    required String placeId,
    required String content,
    required String userId,
    required String userName,
    String? userPhotoUrl,
    List<List<int>> imageBytesList = const [],
    DateTime? publishAt,
    List<MentionTarget> mentions = const [],
  }) async {
    sentMentions = List.unmodifiable(mentions);
    sentContent = content;
    sentPublishAt = publishAt;
    final now = DateTime.now();
    return MessageEntity(
      id: id ?? 'message-1',
      placeId: placeId,
      author: UserEntity(id: userId, name: userName),
      content: content,
      mentions: mentions,
      createdAt: now,
      publishAt: now,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
