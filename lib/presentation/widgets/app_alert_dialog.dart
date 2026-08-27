import 'package:flutter/material.dart';

/// An app-styled alert dialog that keeps dismissive and affirmative actions
/// visually separated.
///
/// The app's regular filled buttons span the available width. Dialog actions
/// instead size themselves to their labels so the first action can sit at the
/// leading edge and the last action at the trailing edge. When the actions do
/// not fit in one row, Flutter's [OverflowBar] stacks them with extra spacing.
class AppAlertDialog extends StatelessWidget {
  final Widget? title;
  final Widget? content;
  final EdgeInsetsGeometry? contentPadding;
  final List<Widget>? actions;

  const AppAlertDialog({
    super.key,
    this.title,
    this.content,
    this.contentPadding,
    this.actions,
  });

  @override
  Widget build(BuildContext context) {
    final filledButtonStyle = Theme.of(context).filledButtonTheme.style;

    return FilledButtonTheme(
      data: FilledButtonThemeData(
        style:
            filledButtonStyle?.copyWith(
              minimumSize: const WidgetStatePropertyAll(Size(64, 48)),
            ) ??
            const ButtonStyle(
              minimumSize: WidgetStatePropertyAll(Size(64, 48)),
            ),
      ),
      child: AlertDialog(
        title: title,
        content: content,
        contentPadding: contentPadding,
        actionsAlignment: MainAxisAlignment.spaceBetween,
        actionsOverflowAlignment: OverflowBarAlignment.end,
        actionsOverflowButtonSpacing: 12,
        actions: actions,
      ),
    );
  }
}
