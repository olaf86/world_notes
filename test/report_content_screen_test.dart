import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:world_notes/domain/entities/content_report.dart';
import 'package:world_notes/l10n/app_localizations.dart';
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
}
