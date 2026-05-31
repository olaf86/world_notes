import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../../../config/app_config.dart';
import '../../../domain/entities/message_entity.dart';
import '../../providers/providers.dart';
import '../../widgets/note/message_bubble.dart';
import '../../widgets/note/message_creation_overlay.dart';

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

class _NoteBoxScreenState extends ConsumerState<NoteBoxScreen>
    with SingleTickerProviderStateMixin {
  final _scrollController = ScrollController();

  // Banner ad — ValueNotifier avoids calling setState() from the ad callback,
  // which previously caused Column layout mutations mid-frame and triggered the
  // '!semantics.parentDataDirty' loop.  Only the ValueListenableBuilder
  // subtree is rebuilt when the ad loads; the rest of the screen is untouched.
  BannerAd? _bannerAd;
  final _adLoaded = ValueNotifier<bool>(false);

  // ── Compose overlay state ─────────────────────────────────────────────────
  //
  // The message creation UI is rendered as an overlay inside this screen's
  // own widget tree, not as a separate Navigator route.  Every Navigator-
  // based attempt (Navigator.push, showModalBottomSheet, ShellRoute child
  // route) triggered the '!semantics.parentDataDirty' loop on this screen
  // because of the BlockSemantics widget that ModalBarrier injects.  An
  // overlay driven purely by an AnimationController bypasses Navigator
  // entirely, so no extra ModalBarrier / BlockSemantics layer is added.
  late final AnimationController _composeController;
  bool _isComposing = false;

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _composeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadAdIfNeeded());
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _adLoaded.dispose();
    _bannerAd?.dispose();
    _composeController.dispose();
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

  // ── Compose overlay ───────────────────────────────────────────────────────

  void _openCompose() {
    if (_isComposing) return;
    setState(() => _isComposing = true);
    _composeController.forward();
  }

  Future<void> _closeCompose() async {
    if (!_isComposing) return;
    await _composeController.reverse();
    if (mounted) setState(() => _isComposing = false);
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

    // Defensive constraint clamp.  Even with opaque:false on all push routes,
    // any future route that lands on top of NoteBoxScreen with opaque:true
    // would wrap this Scaffold in Offstage(offstage:true), pushing
    // BoxConstraints() (0..∞) into the FAB Column / Scaffold body and
    // re-triggering '!semantics.parentDataDirty' loops.  Same pattern as
    // _MainShell in router.dart.
    final size = MediaQuery.sizeOf(context);

    return PopScope(
      // Intercept back gesture / hardware back when the compose overlay is
      // visible — close the overlay instead of popping the route.
      canPop: !_isComposing,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _isComposing) _closeCompose();
      },
      child: ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: size.width,
        maxHeight: size.height,
      ),
      child: ExcludeSemantics(
        excluding: !isCurrent,
        child: Stack(
          children: [
            // ── Base layer: the message-box screen ──────────────────────
            Scaffold(
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

        // FAB — opens the compose overlay (state flag + slide-up animation
        // in a Stack sibling layer below).  heroTag is unique to prevent
        // Hero conflicts with the map screen's FABs ('mapAddNote',
        // 'tracking').
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

            // ── Overlay layer: compose UI, slides up from the bottom ────
            //
            // Rendered only while `_isComposing` is true.  The animation
            // controller drives a SlideTransition from (0, 1) → (0, 0).
            // Because this overlay lives in the SAME Stack as the base
            // Scaffold (not a Navigator route), no ModalBarrier /
            // BlockSemantics is added to the tree — sidestepping the
            // '!semantics.parentDataDirty' loop seen with route pushes.
            if (_isComposing)
              Positioned.fill(
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, 1),
                    end: Offset.zero,
                  ).animate(
                    CurvedAnimation(
                      parent: _composeController,
                      curve: Curves.easeOutCubic,
                      reverseCurve: Curves.easeInCubic,
                    ),
                  ),
                  child: MessageCreationOverlay(
                    placeId: widget.placeId,
                    onClose: _closeCompose,
                  ),
                ),
              ),
          ],
        ),
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

// Compose UI is rendered as an in-tree overlay; see MessageCreationOverlay
// in lib/presentation/widgets/note/message_creation_overlay.dart.
