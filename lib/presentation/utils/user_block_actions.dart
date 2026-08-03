import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n.dart';
import '../providers/providers.dart';

Future<bool> confirmAndSetUserBlocked({
  required BuildContext context,
  required WidgetRef ref,
  required String targetUserId,
  required String targetName,
  required bool blocked,
}) async {
  final l10n = context.l10n;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(
        blocked
            ? l10n.blockUserTitle(targetName)
            : l10n.unblockUserTitle(targetName),
      ),
      content: Text(
        blocked ? l10n.blockUserConfirmation : l10n.unblockUserConfirmation,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: Text(
            MaterialLocalizations.of(dialogContext).cancelButtonLabel,
          ),
        ),
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          style: blocked
              ? TextButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error,
                )
              : null,
          child: Text(
            blocked ? l10n.blockUserConfirmAction : l10n.unblockUserAction,
          ),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return false;

  try {
    await ref
        .read(userBlockRepositoryProvider)
        .setBlocked(targetUserId: targetUserId, blocked: blocked);
    ref.read(optimisticUserBlockStatesProvider.notifier).update((states) {
      return {...states, targetUserId: blocked};
    });
    ref.invalidate(mapPinsProvider);
    if (!context.mounted) return true;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          blocked
              ? context.l10n.userBlocked(targetName)
              : context.l10n.userUnblocked(targetName),
        ),
      ),
    );
    return true;
  } on FirebaseFunctionsException catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.l10n.updateUserBlockFailed(error.message ?? error.code),
          ),
        ),
      );
    }
    return false;
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.updateUserBlockFailed(error))),
      );
    }
    return false;
  }
}
