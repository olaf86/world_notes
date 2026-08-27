import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:world_notes/core/theme/app_theme.dart';
import 'package:world_notes/presentation/widgets/app_alert_dialog.dart';

void main() {
  Future<void> pumpDialog(
    WidgetTester tester, {
    TextDirection textDirection = TextDirection.ltr,
    List<Widget>? actions,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Directionality(
          textDirection: textDirection,
          child: Scaffold(
            body: AppAlertDialog(
              title: const Text('Archive note?'),
              content: const Text(
                'The note will be hidden from the map until restored.',
              ),
              actions:
                  actions ??
                  [
                    TextButton(
                      key: const Key('cancel'),
                      onPressed: () {},
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      key: const Key('confirm'),
                      onPressed: () {},
                      child: const Text('Archive'),
                    ),
                  ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('places cancel and confirm at opposite edges', (tester) async {
    await pumpDialog(tester);

    final dialog = tester.widget<AlertDialog>(find.byType(AlertDialog));
    final cancelRect = tester.getRect(find.byKey(const Key('cancel')));
    final confirmRect = tester.getRect(find.byKey(const Key('confirm')));

    expect(dialog.actionsAlignment, MainAxisAlignment.spaceBetween);
    expect(dialog.actionsOverflowButtonSpacing, 12);
    expect(confirmRect.left - cancelRect.right, greaterThan(48));
    expect(confirmRect.width, lessThan(160));
  });

  testWidgets('uses logical leading and trailing edges in RTL', (tester) async {
    await pumpDialog(tester, textDirection: TextDirection.rtl);

    final cancelRect = tester.getRect(find.byKey(const Key('cancel')));
    final confirmRect = tester.getRect(find.byKey(const Key('confirm')));

    expect(cancelRect.left - confirmRect.right, greaterThan(48));
  });

  testWidgets('stacks long actions with space on narrow screens', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(280, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await pumpDialog(
      tester,
      actions: [
        TextButton(
          key: const Key('cancel'),
          onPressed: () {},
          child: const Text('Cancel this operation'),
        ),
        FilledButton(
          key: const Key('confirm'),
          onPressed: () {},
          child: const Text('Confirm permanent change'),
        ),
      ],
    );

    final cancelRect = tester.getRect(find.byKey(const Key('cancel')));
    final confirmRect = tester.getRect(find.byKey(const Key('confirm')));

    expect(confirmRect.top - cancelRect.bottom, greaterThanOrEqualTo(12));
    expect(tester.takeException(), isNull);
  });

  testWidgets('keeps a three-action dialog in logical action order', (
    tester,
  ) async {
    await pumpDialog(
      tester,
      actions: [
        TextButton(
          key: const Key('cancel'),
          onPressed: () {},
          child: const Text('Cancel'),
        ),
        TextButton(
          key: const Key('reset'),
          onPressed: () {},
          child: const Text('Reset'),
        ),
        FilledButton(
          key: const Key('confirm'),
          onPressed: () {},
          child: const Text('Use image'),
        ),
      ],
    );

    final cancelCenter = tester.getCenter(find.byKey(const Key('cancel')));
    final resetCenter = tester.getCenter(find.byKey(const Key('reset')));
    final confirmCenter = tester.getCenter(find.byKey(const Key('confirm')));

    expect(cancelCenter.dx, lessThan(resetCenter.dx));
    expect(resetCenter.dx, lessThan(confirmCenter.dx));
  });
}
