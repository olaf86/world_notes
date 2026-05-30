import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../../../config/app_config.dart';
import '../../../domain/entities/message_entity.dart';
import '../../providers/providers.dart';
import '../../widgets/note/message_bubble.dart';

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
  final _scrollController = ScrollController();

  // Banner ad — ValueNotifier avoids calling setState() from the ad callback,
  // which previously caused Column layout mutations mid-frame and triggered the
  // '!semantics.parentDataDirty' loop.  Only the ValueListenableBuilder
  // subtree is rebuilt when the ad loads; the rest of the screen is untouched.
  BannerAd? _bannerAd;
  final _adLoaded = ValueNotifier<bool>(false);

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadAdIfNeeded());
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _adLoaded.dispose();
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
        onAdLoaded: (_) => _adLoaded.value = true,
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          _bannerAd = null;
        },
      ),
    )..load();
  }

  // ── Compose ───────────────────────────────────────────────────────────────

  /// Opens an AlertDialog for message composition.
  ///
  /// Using a dialog instead of an inline panel avoids layout mutations inside
  /// NoteBoxScreen's Scaffold body (keyboard appearance / Column resize) that
  /// previously triggered '!semantics.parentDataDirty' assertion loops.
  /// AlertDialog gets its own independent layout context from the dialog route.
  Future<void> _openCompose() async {
    final text = await showDialog<String>(
      context: context,
      builder: (_) => const _ComposeDialog(),
    );
    if (text == null || text.isEmpty || !mounted) return;

    final user = ref.read(authStateProvider).valueOrNull;
    if (user == null) return;

    try {
      await ref.read(messageRepositoryProvider).sendMessage(
            placeId: widget.placeId,
            content: text,
            userId: user.id,
            userName: user.name,
            userPhotoUrl: user.photoUrl,
          );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send: $e')),
        );
      }
    }
  }

  // ── Delete ────────────────────────────────────────────────────────────────

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

  // ── Report ────────────────────────────────────────────────────────────────

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

    // Exclude this screen's semantics while a dialog (delete, report, compose)
    // is shown on top — prevents parentDataDirty noise when two routes coexist.
    final bool isCurrent = ModalRoute.of(context)?.isCurrent ?? true;

    return ExcludeSemantics(
      excluding: !isCurrent,
      child: Scaffold(
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
        // Message list — body is the list alone; the FAB and banner are
        // declared separately so the FAB automatically floats above the banner.
        body: messagesAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Error: $e')),
          data: (messages) => messages.isEmpty
              ? const _EmptyState()
              : ListView.builder(
                  controller: _scrollController,
                  // Extra bottom padding so the FAB never obscures the last
                  // message (FAB 56 dp + margin 16 dp + breathing room 16 dp).
                  padding: const EdgeInsets.only(top: 8, bottom: 88),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final message = messages[index];
                    final isOwn = message.author.id == currentUser?.id;
                    return MessageBubble(
                      message: message,
                      isOwn: isOwn,
                      onDelete: isOwn
                          ? () => _confirmDeleteMessage(message)
                          : null,
                      onReport: !isOwn
                          ? () => _showReportDialog(message)
                          : null,
                    );
                  },
                ),
        ),

        // FAB — opens the compose dialog, positioned bottom-right like X/Twitter.
        // heroTag must differ from the map screen's FABs ('mapAddNote',
        // 'tracking') so Flutter does not Hero-animate between them during
        // route transitions, which caused the "Add Note" label to flash on
        // this button when navigating back.
        floatingActionButton: FloatingActionButton(
          heroTag: 'noteCompose',
          onPressed: _openCompose,
          tooltip: 'Write a message',
          child: const Icon(Icons.edit_outlined),
        ),

        // Banner ad — placed in bottomNavigationBar so the Scaffold
        // automatically lifts the FAB above it when the ad is loaded.
        bottomNavigationBar: ValueListenableBuilder<bool>(
          valueListenable: _adLoaded,
          builder: (context, loaded, _) {
            final ad = _bannerAd;
            return AnimatedSize(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOut,
              child: (loaded && ad != null && !isPremium)
                  ? SafeArea(
                      top: false,
                      child: SizedBox(
                        height: ad.size.height.toDouble(),
                        child: AdWidget(ad: ad),
                      ),
                    )
                  : const SizedBox.shrink(),
            );
          },
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Empty state
// ---------------------------------------------------------------------------

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.chat_bubble_outline,
            size: 64,
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
          const SizedBox(height: 16),
          Text(
            'No messages yet.\nBe the first to write!',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Compose dialog  (shown via showDialog — independent layout context)
// ---------------------------------------------------------------------------

/// Full-screen compose dialog.  Owning its own TextEditingController avoids
/// any shared mutable state with the parent screen.
class _ComposeDialog extends StatefulWidget {
  const _ComposeDialog();

  @override
  State<_ComposeDialog> createState() => _ComposeDialogState();
}

class _ComposeDialogState extends State<_ComposeDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New message'),
      contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLines: null,
        minLines: 4,
        keyboardType: TextInputType.multiline,
        textInputAction: TextInputAction.newline,
        decoration: InputDecoration(
          hintText: 'Write a message…',
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 12,
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.pop(context, _controller.text.trim()),
          icon: const Icon(Icons.send, size: 18),
          label: const Text('Send'),
        ),
      ],
    );
  }
}
