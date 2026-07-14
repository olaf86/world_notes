import 'package:flutter/material.dart';

import '../../../domain/entities/place_entity.dart';
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
    final value = this.value;
    final isLocked = value != null;
    final lockTypeLabel = switch (value?.lockType) {
      NoteLockType.password => 'Password',
      NoteLockType.pattern => 'Pattern',
      null => 'Public',
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
                    isLocked ? 'Locked note' : 'Public note',
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    isLocked
                        ? '$lockTypeLabel lock${value.lockHint == null ? '' : ' with hint'}'
                        : 'Anyone nearby can open it.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: isLocked ? 'Change lock' : 'Set lock',
              onPressed: onConfigure,
              icon: Icon(isLocked ? Icons.edit_outlined : Icons.lock_outline),
            ),
            if (isLocked)
              IconButton(
                tooltip: 'Remove lock',
                onPressed: onRemove,
                icon: const Icon(Icons.close),
              ),
          ],
        ),
      ),
    );
  }
}
