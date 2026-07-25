import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../core/utils/place_icon.dart';
import '../../../l10n/l10n.dart';

/// Shows the selected map-pin image and actions to add, replace, or remove it.
class PinImageSummary extends StatelessWidget {
  final Uint8List? bytes;
  final Color selectedColor;
  final String selectedIcon;
  final bool picking;
  final VoidCallback onPick;
  final VoidCallback onRemove;

  const PinImageSummary({
    super.key,
    required this.bytes,
    required this.selectedColor,
    required this.selectedIcon,
    required this.picking,
    required this.onPick,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final thumbnail = bytes;
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
            CircleAvatar(
              radius: 24,
              backgroundColor: selectedColor,
              backgroundImage: thumbnail == null
                  ? null
                  : MemoryImage(thumbnail),
              child: thumbnail == null
                  ? Icon(placeIconData(selectedIcon), color: Colors.white)
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    thumbnail == null ? l10n.imagePin : l10n.imagePinReady,
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    thumbnail == null
                        ? l10n.pinImageEmptyDescription
                        : l10n.pinImageReadyDescription,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: thumbnail == null ? l10n.chooseImage : l10n.changeImage,
              onPressed: picking ? null : onPick,
              icon: picking
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(
                      thumbnail == null
                          ? Icons.add_photo_alternate_outlined
                          : Icons.edit_outlined,
                    ),
            ),
            if (thumbnail != null)
              IconButton(
                tooltip: l10n.removeImage,
                onPressed: picking ? null : onRemove,
                icon: const Icon(Icons.close),
              ),
          ],
        ),
      ),
    );
  }
}
