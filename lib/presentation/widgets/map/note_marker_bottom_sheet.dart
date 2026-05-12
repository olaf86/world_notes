import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../domain/entities/note_entity.dart';

class NoteMarkerBottomSheet extends StatelessWidget {
  final NoteBoxEntity noteBox;
  const NoteMarkerBottomSheet({super.key, required this.noteBox});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final place = noteBox.place;
    final note = noteBox.note;
    final color = _parseColor(place.colorHex);

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
                  _iconData(place.icon),
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
          Row(
            children: [
              Icon(
                Icons.chat_bubble_outline,
                size: 16,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 4),
              Text(
                '${note.messageCount} messages',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: () {
              Navigator.of(context).pop();
              context.push(
                '/note/${note.id}?title=${Uri.encodeComponent(place.title)}',
              );
            },
            icon: const Icon(Icons.open_in_new),
            label: const Text('Open Note'),
          ),
        ],
      ),
    );
  }

  Color _parseColor(String hex) {
    try {
      return Color(
        int.parse(hex.replaceFirst('#', '0xFF')),
      );
    } catch (_) {
      return Colors.green;
    }
  }

  IconData _iconData(String icon) {
    return switch (icon) {
      'restaurant' => Icons.restaurant,
      'park' => Icons.park,
      'home' => Icons.home,
      'star' => Icons.star,
      'photo' => Icons.photo_camera,
      'music' => Icons.music_note,
      _ => Icons.place,
    };
  }
}
