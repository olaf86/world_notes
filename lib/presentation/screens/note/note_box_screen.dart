import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import '../../../config/app_config.dart';
import '../../../domain/entities/message_entity.dart';
import '../../../domain/entities/user_entity.dart';
import '../../providers/providers.dart';
import '../../widgets/note/message_bubble.dart';

// ---------------------------------------------------------------------------
// Data class returned by the input sheet.
// ---------------------------------------------------------------------------

class _SheetResult {
  final bool send;
  final String text;
  final Uint8List? imageBytes;
  final String? imageName;

  const _SheetResult({
    required this.send,
    required this.text,
    this.imageBytes,
    this.imageName,
  });
}

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class NoteBoxScreen extends ConsumerStatefulWidget {
  final String placeId;
  final String placeTitle;

  const NoteBoxScreen({
    super.key,
    required this.placeId,
    required this.placeTitle,
  });

  @override
  ConsumerState<NoteBoxScreen> createState() => _NoteBoxScreenState();
}

class _NoteBoxScreenState extends ConsumerState<NoteBoxScreen> {
  static const _uuid = Uuid();

  final _messageController = TextEditingController();
  final _scrollController = ScrollController();

  BannerAd? _bannerAd;
  bool _adLoaded = false;

  Uint8List? _pendingImageBytes;
  String? _pendingImageName;

  /// Older messages loaded via pagination (appended below the stream window).
  final List<MessageEntity> _olderMessages = [];
  bool _loadingMore = false;
  bool _hasMore = true;

  /// Optimistic messages shown immediately on send. Each entry is removed once
  /// the matching id appears in the Firestore snapshot stream (server has
  /// confirmed the write), or right away if the write fails.
  final List<MessageEntity> _pendingMessages = [];

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    // Defer the ad load until after the first frame so isPremiumProvider
    // has had a chance to emit its initial value.
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadAdIfNeeded());
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _bannerAd?.dispose();
    super.dispose();
  }

  // ── Ad loading ────────────────────────────────────────────────────────────

  void _loadAdIfNeeded() {
    if (ref.read(isPremiumProvider).valueOrNull == true) return;
    _bannerAd = BannerAd(
      adUnitId: AppConfig.bannerAdUnitId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) => setState(() => _adLoaded = true),
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          _bannerAd = null;
        },
      ),
    )..load();
  }

  // ── Pagination ────────────────────────────────────────────────────────────

  void _onScroll() {
    // Newest messages are at the top (index 0); oldest are at the bottom.
    // Trigger pagination when the user scrolls near the bottom.
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  Future<void> _onRefresh() async {
    setState(() {
      _olderMessages.clear();
      _hasMore = true;
    });
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;

    final streamMessages =
        ref.read(messagesProvider(widget.placeId)).valueOrNull ?? [];
    final allVisible = [...streamMessages, ..._olderMessages];
    if (allVisible.isEmpty) return;

    setState(() => _loadingMore = true);
    try {
      final fetched = await ref
          .read(messageRepositoryProvider)
          .getOlderMessages(
            placeId: widget.placeId,
            beforeMessageId: allVisible.last.id,
            limit: AppConfig.messagesPageSize,
          );
      setState(() {
        _olderMessages.addAll(fetched);
        _hasMore = fetched.length == AppConfig.messagesPageSize;
      });
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  // ── Image picker ─────────────────────────────────────────────────────────

  Future<void> _pickImage() async {
    final isPremium = ref.read(isPremiumProvider).valueOrNull ?? false;
    if (!isPremium) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Photo attachments require Premium.')),
      );
      return;
    }
    final picker = ImagePicker();
    final file = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1920,
      maxHeight: 1920,
      imageQuality: 85,
    );
    if (file == null) return;
    final bytes = await file.readAsBytes();
    setState(() {
      _pendingImageBytes = bytes;
      _pendingImageName = file.name;
    });
  }

  void _clearPendingImage() {
    setState(() {
      _pendingImageBytes = null;
      _pendingImageName = null;
    });
  }

  // ── Input sheet ───────────────────────────────────────────────────────────

  Future<void> _showInputSheet() async {
    final result = await showModalBottomSheet<_SheetResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _MessageInputSheet(
        initialText: _messageController.text,
        initialImageBytes: _pendingImageBytes,
        initialImageName: _pendingImageName,
        isPremium: ref.read(isPremiumProvider).valueOrNull ?? false,
      ),
    );
    if (!mounted || result == null) return;
    _messageController.text = result.text;
    setState(() {
      _pendingImageBytes = result.imageBytes;
      _pendingImageName = result.imageName;
    });
    if (result.send) _sendMessage();
  }

  // ── Send ──────────────────────────────────────────────────────────────────

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty && _pendingImageBytes == null) return;

    final user = ref.read(authStateProvider).valueOrNull;
    if (user == null) return;

    final imageBytes = _pendingImageBytes;
    final imageName = _pendingImageName;
    _messageController.clear();
    _clearPendingImage();

    // Optimistic placeholder shown until Firestore confirms the write.
    final messageId = _uuid.v4();
    final optimistic = MessageEntity(
      id: messageId,
      placeId: widget.placeId,
      author: UserEntity(id: user.id, name: user.name, photoUrl: user.photoUrl),
      content: text,
      createdAt: DateTime.now(),
      isPending: true,
    );
    setState(() => _pendingMessages.insert(0, optimistic));

    try {
      await ref.read(messageRepositoryProvider).sendMessage(
            id: messageId,
            placeId: widget.placeId,
            content: text,
            userId: user.id,
            userName: user.name,
            userPhotoUrl: user.photoUrl,
            imageBytes: imageBytes,
            imageName: imageName,
          );
    } catch (e) {
      if (mounted) {
        setState(() => _pendingMessages.removeWhere((m) => m.id == messageId));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send: $e')),
        );
      }
    }
  }

  // ── Delete / Report ───────────────────────────────────────────────────────

  Future<void> _confirmDeleteMessage(MessageEntity message) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete message'),
        content: const Text(
          'Are you sure you want to delete this message? '
          'It will appear as deleted to all users.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await ref
          .read(messageRepositoryProvider)
          .deleteMessage(messageId: message.id);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete: $e')),
        );
      }
    }
  }

  Future<void> _showReportDialog(MessageEntity message) async {
    const reasons = [
      'Spam or advertising',
      'Harassment or bullying',
      'Adult or explicit content',
      'Illegal content',
      'Other',
    ];
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Report message'),
        children: reasons
            .map(
              (r) => SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, r),
                child: Text(r),
              ),
            )
            .toList(),
      ),
    );
    if (reason == null || !mounted) return;

    final currentUser = ref.read(authStateProvider).valueOrNull;
    if (currentUser == null) return;

    try {
      await ref.read(messageRepositoryProvider).reportMessage(
            messageId: message.id,
            placeId: widget.placeId,
            reporterId: currentUser.id,
            reason: reason,
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Report submitted. Thank you for helping keep this community safe.',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to submit report: $e')),
        );
      }
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final messagesAsync = ref.watch(messagesProvider(widget.placeId));
    final isPremium = ref.watch(isPremiumProvider).valueOrNull ?? false;
    final currentUser = ref.watch(authStateProvider).valueOrNull;

    // ref.listen must live inside build() per Riverpod spec.
    // All side-effects that touch state or the scroll controller are deferred
    // to addPostFrameCallback so they never execute during the current
    // build/layout/semantics phase — Firestore's offline cache can make the
    // stream emit its first snapshot synchronously within the same event-loop
    // turn as a Flutter frame, making direct setState here unsafe.
    ref.listen<AsyncValue<List<MessageEntity>>>(
      messagesProvider(widget.placeId),
      (prev, next) {
        // Drop optimistic bubbles that Firestore has confirmed.
        next.whenData((messages) {
          if (_pendingMessages.isEmpty) return;
          final confirmedIds = messages.map((m) => m.id).toSet();
          if (_pendingMessages.any((p) => confirmedIds.contains(p.id))) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              setState(() {
                _pendingMessages.removeWhere(
                  (p) => confirmedIds.contains(p.id),
                );
              });
            });
          }
        });
        // Auto-scroll to top when new messages arrive and user is near top.
        final prevCount = prev?.valueOrNull?.length ?? 0;
        final nextCount = next.valueOrNull?.length ?? 0;
        if (nextCount > prevCount) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted || !_scrollController.hasClients) return;
            final pos = _scrollController.position;
            if (pos.pixels < 400) {
              _scrollController.animateTo(
                0,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOut,
              );
            }
          });
        }
      },
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.placeTitle),
        actions: [
          if (!isPremium)
            IconButton(
              icon: const Icon(Icons.star_outline),
              tooltip: 'Go Premium',
              onPressed: () => context.push('/subscription'),
            ),
        ],
      ),

      // NOTE: intentionally NO bottomNavigationBar here.
      // router.dart's _MainShell already provides Scaffold.bottomNavigationBar
      // (the app-level NavigationBar). GoRouter's StatefulShellRoute.indexedStack
      // keeps the shell alive when child routes are pushed, so both Scaffolds
      // are in the widget tree simultaneously during the route transition.
      // Having TWO Scaffold.bottomNavigationBar widgets active at the same time
      // corrupts the semantics tree and triggers
      // '!semantics.parentDataDirty': is not true on every frame.
      // The input bar lives in the body Column instead.

      body: Column(
        children: [
          // Banner ad — non-premium users only.
          if (!isPremium && _adLoaded && _bannerAd != null)
            SizedBox(
              height: _bannerAd!.size.height.toDouble(),
              child: AdWidget(ad: _bannerAd!),
            ),

          // Message list.
          Expanded(
            child: messagesAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (streamMessages) {
                final allMessages = [
                  ..._pendingMessages,
                  ...streamMessages,
                  ..._olderMessages,
                ];

                if (allMessages.isEmpty) {
                  // RefreshIndicator requires a scrollable child.
                  return RefreshIndicator(
                    onRefresh: _onRefresh,
                    child: SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      child: SizedBox(
                        height: MediaQuery.of(context).size.height * 0.6,
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.chat_bubble_outline,
                                size: 64,
                                color: Theme.of(context)
                                    .colorScheme
                                    .outlineVariant,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'No messages yet.\nBe the first to write!',
                                textAlign: TextAlign.center,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                    ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                }

                return RefreshIndicator(
                  onRefresh: _onRefresh,
                  child: ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    // Extra item at the end for the pagination spinner.
                    itemCount: allMessages.length + (_loadingMore ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index == allMessages.length) {
                        return const Padding(
                          padding: EdgeInsets.all(16),
                          child: Center(child: CircularProgressIndicator()),
                        );
                      }
                      final message = allMessages[index];
                      final isOwn = message.author.id == currentUser?.id;
                      return MessageBubble(
                        message: message,
                        isOwn: isOwn,
                        onDelete: isOwn && !message.isPending
                            ? () => _confirmDeleteMessage(message)
                            : null,
                        onReport: !isOwn
                            ? () => _showReportDialog(message)
                            : null,
                      );
                    },
                  ),
                );
              },
            ),
          ),

          // Bottom input bar.
          // Kept in the body Column (not Scaffold.bottomNavigationBar) to
          // avoid having two simultaneous bottomNavigationBar slots in the
          // widget tree when this screen is stacked on top of _MainShell.
          //
          // ConstrainedBox guards against the offstage-layout path that Flutter
          // uses for routes below the frontmost opaque route: _ModalScope wraps
          // those routes in Offstage(offstage: true), which passes
          // BoxConstraints() (completely unconstrained) to the subtree.
          // Without this cap, _BottomInputBar's inner
          // Column(crossAxisAlignment: CrossAxisAlignment.stretch) computes
          // crossSize = maxCrossAxis = ∞ and passes BoxConstraints(w=∞) to the
          // Row, whose FilledButton.icon then receives tight-infinity constraints
          // that fail BoxConstraints.debugAssertIsValid in Flutter 3.41.x.
          // In normal (onstage) operation the Scaffold already provides a
          // tight finite width, so this ConstrainedBox has no visual effect.
          ConstrainedBox(
            constraints:
                BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width),
            child: _BottomInputBar(
              pendingImageBytes: _pendingImageBytes,
              onClearImage: _clearPendingImage,
              onPickImage: _pickImage,
              onNewMessage: _showInputSheet,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Bottom input bar
// ---------------------------------------------------------------------------

/// Extracted into its own widget to keep [_NoteBoxScreenState.build] lean.
/// Rendered as the last child of the body [Column], NOT as
/// [Scaffold.bottomNavigationBar], because the app shell (_MainShell in
/// router.dart) already occupies that slot with its NavigationBar. Having two
/// simultaneous [Scaffold.bottomNavigationBar] widgets in the tree during a
/// route transition corrupts the semantics tree.
class _BottomInputBar extends StatelessWidget {
  final Uint8List? pendingImageBytes;
  final VoidCallback onClearImage;
  final VoidCallback onPickImage;
  final VoidCallback onNewMessage;

  const _BottomInputBar({
    required this.pendingImageBytes,
    required this.onClearImage,
    required this.onPickImage,
    required this.onNewMessage,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(20),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      // SafeArea keeps content clear of the home indicator / gesture bar on
      // iPhones. top: false because the Scaffold + AppBar already handle the
      // top safe area.
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Image preview (shown when user has picked a photo).
              if (pendingImageBytes != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Stack(
                    alignment: Alignment.topRight,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.memory(
                          pendingImageBytes!,
                          height: 120,
                          fit: BoxFit.cover,
                        ),
                      ),
                      GestureDetector(
                        onTap: onClearImage,
                        child: Container(
                          margin: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(
                            color: Colors.black54,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.close,
                            color: Colors.white,
                            size: 18,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

              // Action row: photo attachment + new message button.
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    onPressed: onPickImage,
                    icon: const Icon(Icons.photo_outlined),
                    tooltip: 'Attach photo (Premium)',
                  ),
                  FilledButton.icon(
                    onPressed: onNewMessage,
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('New message'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Input sheet (modal bottom sheet)
// ---------------------------------------------------------------------------

class _MessageInputSheet extends StatefulWidget {
  final String initialText;
  final Uint8List? initialImageBytes;
  final String? initialImageName;
  final bool isPremium;

  const _MessageInputSheet({
    required this.initialText,
    this.initialImageBytes,
    this.initialImageName,
    required this.isPremium,
  });

  @override
  State<_MessageInputSheet> createState() => _MessageInputSheetState();
}

class _MessageInputSheetState extends State<_MessageInputSheet> {
  late final TextEditingController _controller;
  Uint8List? _imageBytes;
  String? _imageName;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialText);
    _imageBytes = widget.initialImageBytes;
    _imageName = widget.initialImageName;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    if (!widget.isPremium) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Photo attachments require Premium.')),
      );
      return;
    }
    final picker = ImagePicker();
    final file = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1920,
      maxHeight: 1920,
      imageQuality: 85,
    );
    if (file == null) return;
    final bytes = await file.readAsBytes();
    setState(() {
      _imageBytes = bytes;
      _imageName = file.name;
    });
  }

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty && _imageBytes == null) return;
    Navigator.of(context).pop(
      _SheetResult(
        send: true,
        text: text,
        imageBytes: _imageBytes,
        imageName: _imageName,
      ),
    );
  }

  void _cancel() {
    Navigator.of(context).pop(
      _SheetResult(
        send: false,
        text: _controller.text,
        imageBytes: _imageBytes,
        imageName: _imageName,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Padding at this outermost level is the correct pattern for keyboard-
    // aware bottom sheets: it lets Flutter measure available space after
    // accounting for the software keyboard, avoiding overflow / blank-sheet
    // problems that occur when viewInsets is added inside a
    // Column(mainAxisSize: min).
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Drag handle.
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Header row.
            Row(
              children: [
                Text('New message', style: theme.textTheme.titleSmall),
                const Spacer(),
                IconButton(
                  onPressed: _cancel,
                  icon: const Icon(Icons.close),
                  tooltip: 'Cancel',
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Image preview.
            if (_imageBytes != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Stack(
                  alignment: Alignment.topRight,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.memory(
                        _imageBytes!,
                        height: 120,
                        fit: BoxFit.cover,
                      ),
                    ),
                    GestureDetector(
                      onTap: () => setState(() {
                        _imageBytes = null;
                        _imageName = null;
                      }),
                      child: Container(
                        margin: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: Colors.black54,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.close,
                          color: Colors.white,
                          size: 18,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            // Text field.
            TextField(
              controller: _controller,
              autofocus: true,
              maxLines: null,
              minLines: 5,
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.newline,
              decoration: InputDecoration(
                hintText: 'Write a message...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Bottom action row.
            Row(
              children: [
                IconButton(
                  onPressed: _pickImage,
                  icon: const Icon(Icons.photo_outlined),
                  tooltip: 'Attach photo (Premium)',
                ),
                const Spacer(),
                FilledButton.icon(
                  onPressed: _send,
                  icon: const Icon(Icons.send, size: 18),
                  label: const Text('Send'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
