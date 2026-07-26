import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:world_notes/domain/entities/content_report.dart';
import 'package:world_notes/domain/entities/user_entity.dart';
import 'package:world_notes/l10n/app_localizations.dart';
import 'package:world_notes/presentation/providers/providers.dart';
import 'package:world_notes/presentation/screens/report/report_message_screen.dart';

void main() {
  testWidgets('localizes the note report screen in Japanese', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          locale: Locale('ja'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: ReportContentScreen(
            placeId: 'place-1',
            target: ContentReportTarget.note,
          ),
        ),
      ),
    );

    expect(find.text('ノートを通報'), findsOneWidget);
    expect(find.text('このノートを通報する理由を選んでください'), findsOneWidget);
    expect(find.text('スパムまたは広告'), findsOneWidget);
    expect(find.text('通報を送信'), findsOneWidget);

    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '通報を送信'),
    );
    expect(button.onPressed, isNull);

    await tester.tap(find.text('スパムまたは広告'));
    await tester.pump();

    final enabledButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '通報を送信'),
    );
    expect(enabledButton.onPressed, isNotNull);
  });

  testWidgets('uses message-specific English report copy', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          locale: Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: ReportContentScreen(
            placeId: 'place-1',
            messageId: 'message-1',
            target: ContentReportTarget.message,
          ),
        ),
      ),
    );

    expect(find.text('Report message'), findsOneWidget);
    expect(find.text('Why are you reporting this message?'), findsOneWidget);
    expect(find.text('Report note'), findsNothing);
  });

  testWidgets('offers an optional block for the reported author', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authStateProvider.overrideWith(
            (ref) => Stream.value(
              const UserEntity(id: 'reporter', name: 'Reporter'),
            ),
          ),
          isUserBlockedProvider.overrideWith(
            (ref, userId) => Stream.value(false),
          ),
        ],
        child: const MaterialApp(
          locale: Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: ReportContentScreen(
            placeId: 'place-1',
            messageId: 'message-1',
            target: ContentReportTarget.message,
            reportedUser: ReportedUserTarget(
              userId: 'author',
              displayName: 'Author',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Also block this user'), findsOneWidget);
    final checkbox = tester.widget<Checkbox>(find.byType(Checkbox));
    expect(checkbox.value, isFalse);

    await tester.tap(find.text('Also block this user'));
    await tester.pump();
    expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isTrue);
  });
}
