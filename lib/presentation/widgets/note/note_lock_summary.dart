import 'package:flutter/material.dart';

import '../../../domain/entities/place_entity.dart';
import '../../../l10n/l10n.dart';
import 'note_lock_setup_dialog.dart';

/// Shows the configured note lock and provides actions to manage it.
class NoteLockSummary extends StatelessWidget {
  final NoteLockSetupValue? value;
  final VoidCallback onConfigure;
  final VoidCallback onRemove;

  const NoteLockSummary({
    super.key,
    required this.value,
    required this.onConfigure,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final value = this.value;
    final isLocked = value != null;
    final lockTypeLabel = switch (value?.lockType) {
      NoteLockType.password => l10n.passwordLabel,
      NoteLockType.pattern => l10n.patternLabel,
      null => l10n.publicNote,
    };

    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Icon(
              isLocked ? Icons.lock_outline : Icons.lock_open_outlined,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    isLocked ? l10n.lockedNote : l10n.publicNote,
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    isLocked
                        ? value.lockHint == null
                              ? l10n.noteLockSummary(lockTypeLabel)
                              : l10n.noteLockSummaryWithHint(lockTypeLabel)
                        : l10n.anyoneNearbyCanOpen,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: isLocked ? l10n.changeLock : l10n.setLock,
              onPressed: onConfigure,
              icon: Icon(isLocked ? Icons.edit_outlined : Icons.lock_outline),
            ),
            if (isLocked)
              IconButton(
                tooltip: l10n.removeLock,
                onPressed: onRemove,
                icon: const Icon(Icons.close),
              ),
          ],
        ),
      ),
    );
  }
}
