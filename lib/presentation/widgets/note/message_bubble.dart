import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../config/app_config.dart';
import '../../../domain/entities/message_entity.dart';
import '../../../domain/entities/message_thread_item.dart';
import '../../providers/providers.dart';
import 'image_grid_layout.dart';

class MessageBubble extends StatefulWidget {
  final MessageEntity message;
  final MessageLikeState likeState;
  final bool isOwn;
  final bool canLike;
  final bool isAuthorHighlighted;
  final ValueChanged<String>? onAuthorTap;
  final Future<void> Function(bool liked)? onLikeChanged;
  final VoidCallback? onDelete;
  final VoidCallback? onReport;

  const MessageBubble({
    super.key,
    required this.message,
    this.likeState = const MessageLikeState(),
    required this.isOwn,
    this.canLike = false,
    this.isAuthorHighlighted = false,
    this.onAuthorTap,
    this.onLikeChanged,
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
  Timer? _likeDebounce;
  bool _initializedLikeState = false;
  bool _serverLiked = false;
  int _serverLikeCount = 0;
  bool _displayLiked = false;
  int _displayLikeCount = 0;
  bool _hasLocalLikeOverride = false;
  bool _sendingLike = false;
  bool _flushLikeAfterSend = false;

  @override
  void didUpdateWidget(covariant MessageBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.message.id != widget.message.id) {
      _likeDebounce?.cancel();
      _likeDebounce = null;
      _initializedLikeState = false;
      _serverLiked = false;
      _serverLikeCount = 0;
      _displayLiked = false;
      _displayLikeCount = 0;
      _hasLocalLikeOverride = false;
      _sendingLike = false;
      _flushLikeAfterSend = false;
      return;
    }
  }

  @override
  void dispose() {
    _likeDebounce?.cancel();
    final onLikeChanged = widget.onLikeChanged;
    if (_hasLocalLikeOverride &&
        _displayLiked != _serverLiked &&
        onLikeChanged != null) {
      unawaited(onLikeChanged(_displayLiked).catchError((_) {}));
    }
    super.dispose();
  }

  // ── Full-screen image viewer ──────────────────────────────────────────────

  void _openImageViewer(List<String> imageStoragePaths, int initialIndex) {
    final pageController = PageController(initialPage: initialIndex);
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
              child: PageView.builder(
                controller: pageController,
                itemCount: imageStoragePaths.length,
                itemBuilder: (context, index) => InteractiveViewer(
                  minScale: 1.0,
                  maxScale: 4.0,
                  child: Center(
                    child: _MessageStorageImage(
                      storagePath: imageStoragePaths[index],
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

  /// Applies Firestore-backed like state without letting in-flight taps flicker.
  void _applyServerLikeState({
    required bool serverLiked,
    required int serverCount,
  }) {
    _serverLiked = serverLiked;
    _serverLikeCount = serverCount;
    if (!_initializedLikeState) {
      _initializedLikeState = true;
      _displayLiked = serverLiked;
      _displayLikeCount = serverCount;
      return;
    }
    if (!_hasLocalLikeOverride && !_sendingLike && _likeDebounce == null) {
      _displayLiked = serverLiked;
      _displayLikeCount = serverCount;
      return;
    }
    if (_hasLocalLikeOverride &&
        !_sendingLike &&
        _likeDebounce == null &&
        _displayLiked == serverLiked &&
        _displayLikeCount == serverCount) {
      _hasLocalLikeOverride = false;
    }
  }

  void _toggleLike() {
    if (!widget.canLike || widget.onLikeChanged == null) return;
    final nextLiked = !_displayLiked;
    final nextCount = (_displayLikeCount + (nextLiked ? 1 : -1))
        .clamp(0, 1 << 31)
        .toInt();
    setState(() {
      _displayLiked = nextLiked;
      _displayLikeCount = nextCount;
      _hasLocalLikeOverride = true;
    });
    _scheduleLikeFlush();
  }

  void _scheduleLikeFlush() {
    _likeDebounce?.cancel();
    _likeDebounce = Timer(AppConfig.likeDebounceDuration, () {
      _likeDebounce = null;
      unawaited(_flushLike());
    });
  }

  Future<void> _flushLike() async {
    if (!mounted) return;
    if (_sendingLike) {
      _flushLikeAfterSend = true;
      return;
    }
    final onLikeChanged = widget.onLikeChanged;
    if (onLikeChanged == null) return;
    final desiredLiked = _displayLiked;
    if (desiredLiked == _serverLiked) {
      setState(() {
        _hasLocalLikeOverride = false;
        _displayLikeCount = _serverLikeCount;
      });
      return;
    }

    setState(() {
      _sendingLike = true;
      _flushLikeAfterSend = false;
    });
    try {
      await onLikeChanged(desiredLiked);
      if (!mounted) return;
      setState(() => _sendingLike = false);
      if (_flushLikeAfterSend || _displayLiked != desiredLiked) {
        _flushLikeAfterSend = false;
        _scheduleLikeFlush();
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _sendingLike = false;
        _flushLikeAfterSend = false;
        _hasLocalLikeOverride = false;
        _displayLiked = _serverLiked;
        _displayLikeCount = _serverLikeCount;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final message = widget.message;
    _applyServerLikeState(
      serverLiked: widget.likeState.likedByCurrentUser,
      serverCount: widget.likeState.count,
    );

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
    final imageStoragePaths = message.imageStoragePaths;
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
                    if (imageStoragePaths.isNotEmpty) const SizedBox(height: 8),
                  ],
                  // ── Images (optional) ───────────────────────────────
                  //
                  // Left-aligned, fills the available column width up to 280
                  // dp. The X-style grid keeps mixed photo counts compact.
                  // Tap opens a full-screen zoomable pager.
                  if (imageStoragePaths.isNotEmpty)
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 280),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: AspectRatio(
                          aspectRatio: 1.0,
                          child: _MessageImageGrid(
                            storagePaths: imageStoragePaths,
                            onTap: (index) =>
                                _openImageViewer(imageStoragePaths, index),
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(height: 8),
                  _MessageActionRow(
                    messageId: message.id,
                    liked: _displayLiked,
                    likeCount: _displayLikeCount,
                    canLike: widget.canLike,
                    isSendingLike: _sendingLike,
                    onLikePressed: _toggleLike,
                    onReportPressed: !widget.isOwn ? widget.onReport : null,
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

class _MessageActionRow extends StatelessWidget {
  final String messageId;
  final bool liked;
  final int likeCount;
  final bool canLike;
  final bool isSendingLike;
  final VoidCallback onLikePressed;
  final VoidCallback? onReportPressed;

  const _MessageActionRow({
    required this.messageId,
    required this.liked,
    required this.likeCount,
    required this.canLike,
    required this.isSendingLike,
    required this.onLikePressed,
    this.onReportPressed,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final likeColor = liked
        ? theme.colorScheme.error
        : theme.colorScheme.onSurfaceVariant;
    return Row(
      children: [
        Semantics(
          identifier: 'action-toggle-message-like-$messageId',
          button: true,
          toggled: liked,
          child: IconButton(
            tooltip: liked ? 'Unlike message' : 'Like message',
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints.tightFor(width: 32, height: 32),
            padding: EdgeInsets.zero,
            onPressed: canLike ? onLikePressed : null,
            icon: Icon(
              liked ? Icons.favorite : Icons.favorite_border,
              size: 18,
              color: canLike ? likeColor : null,
            ),
          ),
        ),
        const SizedBox(width: 2),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 140),
          child: Text(
            '$likeCount',
            key: ValueKey(likeCount),
            style: theme.textTheme.labelSmall?.copyWith(
              color: liked
                  ? theme.colorScheme.error
                  : theme.colorScheme.onSurfaceVariant,
              fontWeight: liked ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
        if (isSendingLike) ...[
          const SizedBox(width: 8),
          SizedBox.square(
            dimension: 12,
            child: CircularProgressIndicator(strokeWidth: 2, color: likeColor),
          ),
        ],
        if (onReportPressed != null) ...[
          const SizedBox(width: 14),
          IconButton(
            tooltip: 'Report message',
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints.tightFor(width: 32, height: 32),
            padding: EdgeInsets.zero,
            onPressed: onReportPressed,
            icon: Icon(
              Icons.flag_outlined,
              size: 17,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

class _MessageImageGrid extends StatelessWidget {
  final List<String> storagePaths;
  final ValueChanged<int> onTap;

  const _MessageImageGrid({required this.storagePaths, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final count = storagePaths.length.clamp(0, 4).toInt();

    Widget item(int index) => GestureDetector(
      onTap: () => onTap(index),
      child: _MessageGridImage(storagePath: storagePaths[index]),
    );

    return ImageGridLayout(
      itemCount: count,
      itemBuilder: (_, index) => item(index),
    );
  }
}

class _MessageGridImage extends StatelessWidget {
  final String storagePath;

  const _MessageGridImage({required this.storagePath});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _MessageStorageImage(
      storagePath: storagePath,
      fit: BoxFit.cover,
      placeholder: Container(
        color: theme.colorScheme.surfaceContainerHighest,
        child: const Center(child: CircularProgressIndicator()),
      ),
      errorWidget: Container(
        color: theme.colorScheme.surfaceContainerHighest,
        child: Icon(
          Icons.broken_image_outlined,
          color: theme.colorScheme.onSurfaceVariant,
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
