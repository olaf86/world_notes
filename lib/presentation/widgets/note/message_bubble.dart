import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../domain/entities/message_entity.dart';

class MessageBubble extends StatefulWidget {
  final MessageEntity message;
  final bool isOwn;
  final VoidCallback? onDelete;
  final VoidCallback? onReport;

  const MessageBubble({
    super.key,
    required this.message,
    required this.isOwn,
    this.onDelete,
    this.onReport,
  });

  @override
  State<MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<MessageBubble> {
  /// Whether the user has chosen to reveal flagged content for this bubble.
  /// Resets to false each time the screen is re-entered (not persisted).
  bool _flaggedContentRevealed = false;

  void _showActionSheet() {
    final hasActions = (widget.isOwn && widget.onDelete != null) ||
        (!widget.isOwn && widget.onReport != null);
    if (!hasActions) return;

    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.isOwn && widget.onDelete != null)
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('Delete message'),
                textColor: Theme.of(context).colorScheme.error,
                iconColor: Theme.of(context).colorScheme.error,
                onTap: () {
                  Navigator.pop(ctx);
                  widget.onDelete!();
                },
              ),
            if (!widget.isOwn && widget.onReport != null)
              ListTile(
                leading: const Icon(Icons.flag_outlined),
                title: const Text('Report message'),
                onTap: () {
                  Navigator.pop(ctx);
                  widget.onReport!();
                },
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final message = widget.message;

    // ── Deleted tombstone ─────────────────────────────────────────────────
    if (message.isDeleted) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
        child: Row(
          children: [
            Icon(
              Icons.remove_circle_outline,
              size: 14,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 4),
            Text(
              'This message has been deleted.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      );
    }

    // ── Flagged content warning ───────────────────────────────────────────
    if (!message.isVisible && !_flaggedContentRevealed) {
      return GestureDetector(
        onLongPress: _showActionSheet,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: theme.colorScheme.errorContainer),
              borderRadius: BorderRadius.circular(8),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      size: 15,
                      color: theme.colorScheme.error,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Flagged content',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.error,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'This message was hidden by our moderation system '
                  'for potentially harmful content.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: () => setState(() => _flaggedContentRevealed = true),
                  child: Text(
                    'Show anyway',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.primary,
                      decoration: TextDecoration.underline,
                      decorationColor: theme.colorScheme.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // ── Normal item — bulletin-board style ───────────────────────────────
    //
    // All messages are left-aligned.  Own messages are distinguished by:
    //   • A 3 dp primary-coloured left border
    //   • A subtle primaryContainer background tint
    //   • Author name rendered in primary colour
    //   • A small "You" badge next to the name
    final timeStr = DateFormat('HH:mm').format(message.createdAt.toLocal());
    final hasActions = (widget.isOwn && widget.onDelete != null) ||
        (!widget.isOwn && widget.onReport != null);

    return GestureDetector(
      onLongPress: hasActions ? _showActionSheet : null,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Avatar(
              photoUrl: message.author.photoUrl,
              name: message.author.name,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Header: name · [You badge] · timestamp ──────────
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          message.author.name,
                          style: theme.textTheme.labelMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: widget.isOwn
                                ? theme.colorScheme.primary
                                : theme.colorScheme.onSurface,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (widget.isOwn) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'You',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onPrimary,
                              fontWeight: FontWeight.w700,
                              fontSize: 10,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(width: 8),
                      if (message.isPending) ...[
                        SizedBox(
                          width: 10,
                          height: 10,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.5,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(width: 4),
                      ],
                      Text(
                        message.isPending ? 'Sending…' : timeStr,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  // ── Image (optional) ────────────────────────────────
                  if (message.imageUrl != null) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: CachedNetworkImage(
                        imageUrl: message.imageUrl!,
                        width: 220,
                        fit: BoxFit.cover,
                        placeholder: (context, url) => const SizedBox(
                          height: 120,
                          width: 220,
                          child: Center(child: CircularProgressIndicator()),
                        ),
                        errorWidget: (context, url, error) => const SizedBox(
                          height: 80,
                          width: 220,
                          child: Icon(Icons.broken_image_outlined),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                  ],
                  // ── Text content ────────────────────────────────────
                  if (message.content.isNotEmpty)
                    Text(
                      message.content,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final String? photoUrl;
  final String name;

  const _Avatar({this.photoUrl, required this.name});

  @override
  Widget build(BuildContext context) {
    if (photoUrl != null) {
      return CircleAvatar(
        radius: 16,
        backgroundImage: CachedNetworkImageProvider(photoUrl!),
      );
    }
    return CircleAvatar(
      radius: 16,
      backgroundColor: Theme.of(context).colorScheme.primaryContainer,
      child: Text(
        name.isNotEmpty ? name[0].toUpperCase() : '?',
        style: TextStyle(
          fontSize: 12,
          color: Theme.of(context).colorScheme.onPrimaryContainer,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
