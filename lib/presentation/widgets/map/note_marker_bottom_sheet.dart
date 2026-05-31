import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/place_icon.dart';
import '../../../core/utils/time_format.dart';
import '../../../domain/entities/place_entity.dart';

class NoteMarkerBottomSheet extends StatelessWidget {
  final PlaceEntity place;
  const NoteMarkerBottomSheet({super.key, required this.place});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = parsePlaceColor(place.colorHex);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: color,
                child: Icon(
                  placeIconData(place.icon),
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      place.title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (place.subtitle != null)
                      Text(
                        place.subtitle!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _MetaChip(
                icon: Icons.chat_bubble_outline,
                label: '${place.messageCount} messages',
              ),
              if (place.isPrivate)
                _MetaChip(
                  icon: Icons.lock_outline,
                  label: 'Private',
                  color: theme.colorScheme.tertiary,
                ),
              if (place.isClosed)
                _MetaChip(
                  icon: Icons.do_not_disturb_on_outlined,
                  label: 'Closed',
                  color: theme.colorScheme.error,
                ),
              _MetaChip(
                icon: Icons.schedule,
                label: remainingLifetimeLabel(place.expiresAt),
              ),
            ],
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: () {
              Navigator.of(context).pop();
              context.push(
                '/note/${place.id}?title=${Uri.encodeComponent(place.title)}',
              );
            },
            icon: const Icon(Icons.open_in_new),
            label: Text(place.isClosed ? 'View Note' : 'Open Note'),
          ),
        ],
      ),
    );
  }
}

/// Compact icon + label chip used for note metadata (message count, status,
/// remaining lifetime). [color] tints both icon and text; defaults to the
/// muted onSurfaceVariant.
class _MetaChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;

  const _MetaChip({required this.icon, required this.label, this.color});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = color ?? theme.colorScheme.onSurfaceVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: c),
        const SizedBox(width: 4),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(color: c),
        ),
      ],
    );
  }
}
