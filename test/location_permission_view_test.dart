import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:world_notes/l10n/app_localizations.dart';
import 'package:world_notes/presentation/widgets/map/location_permission_view.dart';
import 'package:world_notes/services/location_service.dart';

void main() {
  testWidgets('shows retry copy when permission can be requested', (
    tester,
  ) async {
    var retried = false;

    await _pumpView(
      tester,
      issue: LocationAvailabilityIssue.permissionDenied,
      onRetry: () => retried = true,
    );

    expect(find.text('Location Required'), findsOneWidget);
    expect(
      find.text('Enable location tracking to enjoy World Notes.'),
      findsOneWidget,
    );
    expect(find.text('Allow Location'), findsOneWidget);

    await tester.tap(find.text('Allow Location'));
    expect(retried, isTrue);
  });

  testWidgets('shows location service settings copy when services are off', (
    tester,
  ) async {
    await _pumpView(
      tester,
      issue: LocationAvailabilityIssue.serviceDisabled,
      onRetry: () {},
    );

    expect(find.text('Turn On Location Services'), findsOneWidget);
    expect(
      find.text('Turn on location services to use World Notes.'),
      findsOneWidget,
    );
    expect(find.text('Open Location Settings'), findsOneWidget);
  });
}

Future<void> _pumpView(
  WidgetTester tester, {
  required LocationAvailabilityIssue issue,
  required VoidCallback onRetry,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: LocationPermissionView(issue: issue, onRetry: onRetry),
    ),
  );
}
