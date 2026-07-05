import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../domain/entities/message_entity.dart';
import '../../providers/providers.dart';

class MessageBubble extends StatefulWidget {
  final MessageEntity message;
  final bool isOwn;
  final bool isAuthorHighlighted;
  final ValueChanged<String>? onAuthorTap;
  final VoidCallback? onDelete;
  final VoidCallback? onReport;

  const MessageBubble({
    super.key,
    required this.message,
    required this.isOwn,
    this.isAuthorHighlighted = false,
    this.onAuthorTap,
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

  // ── Full-screen image viewer ──────────────────────────────────────────────

  void _openImageViewer(String imageStoragePath) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      barrierDismissible: true,
      builder: (ctx) => Dialog.fullscreen(
        backgroundColor: Colors.black,
        child: Stack(
          children: [
            // Pinch-to-zoom image — tap outside to dismiss.
            GestureDetector(
              onTap: () => Navigator.pop(ctx),
              behavior: HitTestBehavior.opaque,
              child: InteractiveViewer(
                minScale: 1.0,
                maxScale: 4.0,
                child: Center(
                  child: _MessageStorageImage(
                    storagePath: imageStoragePath,
                    fit: BoxFit.contain,
                    placeholder: const Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    ),
                    errorWidget: const Icon(
                      Icons.broken_image_outlined,
                      color: Colors.white,
                      size: 48,
                    ),
                  ),
                ),
              ),
            ),
            // Close button (top-right, respects safe area).
            Positioned(
              top: MediaQuery.of(ctx).padding.top + 4,
              right: 4,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                tooltip: 'Close',
                onPressed: () => Navigator.pop(ctx),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _messageTimeLabel(MessageEntity message, {required bool isScheduled}) {
    final publishAt = message.publishAt.toLocal();

    if (isScheduled) {
      return DateFormat('MMM d, HH:mm').format(publishAt);
    }

    final elapsed = DateTime.now().difference(publishAt);
    final isAtLeastOneDayOld =
        !elapsed.isNegative && elapsed >= const Duration(days: 1);

    return DateFormat(
      isAtLeastOneDayOld ? 'MMM d, HH:mm' : 'HH:mm',
    ).format(publishAt);
  }

  void _showActionSheet() {
    final hasActions =
        (widget.isOwn && widget.onDelete != null) ||
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
                title: Text(
                  widget.message.isPublished
                      ? 'Delete message'
                      : 'Cancel scheduled message',
                ),
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
      final tombstoneText = message.deletedReason == 'moderation'
          ? 'This message was removed by an administrator.'
          : 'This message has been deleted.';
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
              tombstoneText,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      );
    }

    // ── Sensitive content warning ───────────────────────────────────────
    if (message.isSensitive && !_flaggedContentRevealed) {
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
                      color: theme.colorScheme.tertiary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Sensitive content',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.tertiary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'This message may contain sensitive content.',
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
    final isScheduled = widget.isOwn && !message.isPublished;
    final timeStr = _messageTimeLabel(message, isScheduled: isScheduled);
    final hasActions =
        (widget.isOwn && widget.onDelete != null) ||
        (!widget.isOwn && widget.onReport != null);

    return GestureDetector(
      onLongPress: hasActions ? _showActionSheet : null,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: widget.isAuthorHighlighted
            ? BoxDecoration(
                color: theme.colorScheme.secondaryContainer,
                border: Border(
                  left: BorderSide(
                    color: theme.colorScheme.secondary,
                    width: 3,
                  ),
                ),
              )
            : null,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onTap: widget.onAuthorTap == null
                  ? null
                  : () => widget.onAuthorTap!(message.author.id),
              child: _Avatar(
                photoUrl: message.author.photoUrl,
                name: message.author.name,
              ),
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
                        child: Row(
                          children: [
                            Flexible(
                              child: GestureDetector(
                                onTap: widget.onAuthorTap == null
                                    ? null
                                    : () => widget.onAuthorTap!(
                                        message.author.id,
                                      ),
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
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
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
                              if (isScheduled) ...[
                                Icon(
                                  Icons.schedule_send_outlined,
                                  size: 13,
                                  color: theme.colorScheme.tertiary,
                                ),
                                const SizedBox(width: 3),
                              ],
                              Flexible(
                                child: Text(
                                  message.isPending
                                      ? 'Sending…'
                                      : isScheduled
                                      ? 'Scheduled $timeStr'
                                      : timeStr,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: isScheduled
                                        ? theme.colorScheme.tertiary
                                        : theme.colorScheme.onSurfaceVariant,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.end,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  // ── Text content (X style: text first, image after) ──
                  if (message.content.isNotEmpty) ...[
                    Text(
                      message.content,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    if (message.imageStoragePath != null)
                      const SizedBox(height: 8),
                  ],
                  // ── Image (optional) ────────────────────────────────
                  //
                  // Left-aligned, fills the available column width up to
                  // maxWidth (280 dp).  AspectRatio keeps it square (1:1)
                  // with BoxFit.cover so the crop never distorts the image.
                  // Tap opens a full-screen zoomable viewer.
                  if (message.imageStoragePath != null)
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 280),
                      child: GestureDetector(
                        onTap: () =>
                            _openImageViewer(message.imageStoragePath!),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: AspectRatio(
                            aspectRatio: 1.0,
                            child: _MessageStorageImage(
                              storagePath: message.imageStoragePath!,
                              fit: BoxFit.cover,
                              placeholder: Container(
                                color:
                                    theme.colorScheme.surfaceContainerHighest,
                                child: const Center(
                                  child: CircularProgressIndicator(),
                                ),
                              ),
                              errorWidget: Container(
                                color:
                                    theme.colorScheme.surfaceContainerHighest,
                                child: Icon(
                                  Icons.broken_image_outlined,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (!widget.isOwn && widget.onReport != null) ...[
                    const SizedBox(height: 8),
                    _ReportInlineAction(onPressed: widget.onReport!),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReportInlineAction extends StatelessWidget {
  final VoidCallback onPressed;

  const _ReportInlineAction({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Align(
      alignment: Alignment.centerLeft,
      child: InkWell(
        borderRadius: BorderRadius.circular(4),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 3),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.flag_outlined,
                size: 13,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 4),
              Text(
                'Report',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MessageStorageImage extends ConsumerWidget {
  final String storagePath;
  final BoxFit fit;
  final Widget placeholder;
  final Widget errorWidget;

  const _MessageStorageImage({
    required this.storagePath,
    required this.fit,
    required this.placeholder,
    required this.errorWidget,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final imageUrl = ref.watch(messageImageUrlProvider(storagePath));
    return imageUrl.when(
      loading: () => placeholder,
      error: (_, _) => errorWidget,
      data: (url) => CachedNetworkImage(
        imageUrl: url,
        cacheKey: storagePath,
        cacheManager: ref.watch(messageImageServiceProvider).cacheManager,
        fit: fit,
        placeholder: (_, _) => placeholder,
        errorWidget: (_, _, _) => errorWidget,
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
