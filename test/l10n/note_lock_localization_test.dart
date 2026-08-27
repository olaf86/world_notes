import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:world_notes/l10n/l10n.dart';
import 'package:world_notes/presentation/widgets/note/note_lock_setup_dialog.dart';

void main() {
  testWidgets('note lock setup uses the active locale', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ja'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => NoteLockSetupDialog(
            title: context.l10n.setLock,
            onPatternTooLong: () {},
          ),
        ),
      ),
    );

    expect(find.text('ロックを設定'), findsOneWidget);
    expect(find.text('パスワード'), findsNWidgets(2));
    expect(find.text('確認用パスワード'), findsOneWidget);
    expect(find.text('ヒント（任意）'), findsOneWidget);
    expect(find.text('キャンセル'), findsOneWidget);
    expect(find.text('保存'), findsOneWidget);

    await tester.tap(find.text('保存'));
    await tester.pump();
    expect(find.text('パスワードを入力してください。'), findsOneWidget);

    await tester.tap(find.text('パターン'));
    await tester.pump();
    expect(find.text('隣り合う点をつないでパターンを描いてください。'), findsOneWidget);
    expect(find.text('クリア'), findsOneWidget);
  });
}
