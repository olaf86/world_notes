import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../../../config/app_config.dart';
import '../../../core/utils/pattern_lock_util.dart';
import '../../../domain/entities/message_entity.dart';
import '../../../domain/entities/place_entity.dart';
import '../../providers/providers.dart';
import '../../widgets/note/manage_access_sheet.dart';
import '../../widgets/note/message_bubble.dart';
import '../../widgets/note/message_creation_overlay.dart';
import '../../widgets/pattern_lock/pattern_lock_input.dart';

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
          .deleteMessage(placeId: widget.placeId, messageId: message.id);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to delete: $e')));
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
      await ref
          .read(messageRepositoryProvider)
          .reportMessage(
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to submit report: $e')));
      }
    }
  }

  // ── Owner thread controls ─────────────────────────────────────────────────

  Future<void> _closeThread() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Close this thread?'),
        content: const Text(
          'No new messages can be posted once closed. Existing messages stay '
          'readable, and you can re-open it later.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Close thread'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await ref
          .read(placeRepositoryProvider)
          .closePlace(widget.placeId, reason: ClosedReason.owner);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to close: $e')));
      }
    }
  }

  Future<void> _reopenThread() async {
    try {
      await ref.read(placeRepositoryProvider).reopenPlace(widget.placeId);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to re-open: $e')));
      }
    }
  }

  /// Owner: open the access-management sheet (invite link + member list).
  void _showManageAccess() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => ManageAccessSheet(placeId: widget.placeId),
    );
  }

  // ── Private access (set pattern lock / unlock) ───────────────────────────

  void _showPatternTooLongSnack() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Pattern is too long. Use 30 nodes or fewer.'),
      ),
    );
  }

  /// Owner: set or change the note pattern lock (locks it as private).
  Future<void> _promptSetPassword({required bool isChange}) async {
    final place = ref.read(placeProvider(widget.placeId)).valueOrNull;
    final hintController = TextEditingController(text: place?.lockHint ?? '');
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        List<int> pattern = const [];
        String? error;
        var busy = false;
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            Future<void> submit() async {
              if (busy) return;
              final validation = PatternLockUtil.validate(pattern);
              if (validation != null) {
                setLocal(() => error = validation);
                return;
              }
              setLocal(() {
                busy = true;
                error = null;
              });
              try {
                await ref
                    .read(placeRepositoryProvider)
                    .setNotePassword(
                      placeId: widget.placeId,
                      password: PatternLockUtil.encode(pattern),
                      lockHint: hintController.text.trim().isEmpty
                          ? null
                          : hintController.text.trim(),
                    );
                if (ctx.mounted) Navigator.pop(ctx);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Pattern lock saved. This note is private.',
                      ),
                    ),
                  );
                }
              } on FirebaseFunctionsException catch (e) {
                setLocal(() {
                  busy = false;
                  error = e.message ?? 'Failed to save the pattern lock.';
                });
              } catch (_) {
                setLocal(() {
                  busy = false;
                  error = 'Failed to save the pattern lock.';
                });
              }
            }

            return AlertDialog(
              title: Text(
                isChange ? 'Change pattern lock' : 'Set pattern lock',
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Draw a path between neighboring dots. Short patterns are '
                      'easy to guess; longer paths are better for private notes.',
                    ),
                    const SizedBox(height: 12),
                    PatternLockInput(
                      size: 248,
                      onChanged: (path) {
                        setLocal(() {
                          pattern = path;
                          error = null;
                        });
                      },
                      onTooLong: _showPatternTooLongSnack,
                    ),
                    if (error != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        error!,
                        style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                          color: Theme.of(ctx).colorScheme.error,
                        ),
                      ),
                    ],
                    if (pattern.isNotEmpty && pattern.length < 4) ...[
                      const SizedBox(height: 8),
                      Text(
                        'This is a very short pattern.',
                        style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                          color: Theme.of(ctx).colorScheme.tertiary,
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    TextField(
                      controller: hintController,
                      maxLength: 140,
                      decoration: InputDecoration(
                        labelText: 'Hint (optional)',
                        counterText: '',
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: busy ? null : () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: busy ? null : submit,
                  child: busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
    hintController.dispose();
  }

  /// Visitor: draw a pattern to unlock a private note. On success the
  /// membership stream updates and the screen rebuilds with access.
  Future<void> _promptUnlock() async {
    final place = ref.read(placeProvider(widget.placeId)).valueOrNull;
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        List<int> pattern = const [];
        String? error;
        var busy = false;
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            Future<void> submit() async {
              if (busy) return;
              final validation = PatternLockUtil.validate(pattern);
              if (validation != null) {
                setLocal(() => error = validation);
                return;
              }
              setLocal(() {
                busy = true;
                error = null;
              });
              try {
                await ref
                    .read(placeRepositoryProvider)
                    .unlockNote(
                      placeId: widget.placeId,
                      password: PatternLockUtil.encode(pattern),
                    );
                if (ctx.mounted) Navigator.pop(ctx);
              } on FirebaseFunctionsException catch (e) {
                setLocal(() {
                  busy = false;
                  error = switch (e.code) {
                    'permission-denied' => 'Incorrect pattern.',
                    'resource-exhausted' =>
                      'Too many attempts. Please try again later.',
                    'unavailable' || 'deadline-exceeded' =>
                      'Network error. Check your connection.',
                    _ => e.message ?? 'Could not unlock this note.',
                  };
                });
              } catch (_) {
                setLocal(() {
                  busy = false;
                  error = 'Could not unlock this note.';
                });
              }
            }

            return AlertDialog(
              title: const Text('Draw pattern'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('This note is private.'),
                    if (place?.lockHint case final hint?
                        when hint.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Hint: $hint',
                        style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    PatternLockInput(
                      size: 248,
                      onChanged: (path) {
                        setLocal(() {
                          pattern = path;
                          error = null;
                        });
                      },
                      onCompleted: (_) => submit(),
                      onTooLong: _showPatternTooLongSnack,
                    ),
                    if (error != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        error!,
                        style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                          color: Theme.of(ctx).colorScheme.error,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: busy ? null : () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: busy ? null : submit,
                  child: busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Unlock'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isPremium = ref.watch(isPremiumProvider).valueOrNull ?? false;
    final currentUser = ref.watch(authStateProvider).valueOrNull;
    final place = ref.watch(placeProvider(widget.placeId)).valueOrNull;

    final isOwner =
        place != null &&
        currentUser != null &&
        place.createdByUserId == currentUser.id;

    // Private-note access gate. For a private note the viewer doesn't own,
    // check their membership grant; if it's absent or stale, show the locked
    // view and DON'T subscribe to messages (the read would be denied anyway).
    if (place != null && place.isPrivate && !isOwner) {
      final membership = ref
          .watch(noteMembershipProvider(widget.placeId))
          .valueOrNull;
      if (!place.isAccessibleBy(currentUser?.id, membership)) {
        return _LockedNoteView(
          title: widget.placeTitle,
          lockHint: place.lockHint,
          onUnlock: _promptUnlock,
        );
      }
    }

    // Public, owned, or unlocked — safe to read messages now.
    final messagesAsync = ref.watch(messagesProvider(widget.placeId));
    // Whether a new message may be posted right now — only once the place is
    // loaded and still accepting messages (open, not expired/archived/full).
    final canPostMessage = place?.canAcceptMessages ?? false;

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
                        tooltip: 'Go PRO',
                        onPressed: () => context.push('/subscription'),
                      ),
                    // Owner-only thread controls.
                    if (isOwner)
                      PopupMenuButton<String>(
                        tooltip: 'Thread options',
                        onSelected: (value) {
                          if (value == 'close') _closeThread();
                          if (value == 'reopen') _reopenThread();
                          if (value == 'password') {
                            _promptSetPassword(isChange: place.isPrivate);
                          }
                          if (value == 'access') _showManageAccess();
                        },
                        itemBuilder: (ctx) => [
                          if (place.isOpen)
                            const PopupMenuItem(
                              value: 'close',
                              child: ListTile(
                                leading: Icon(Icons.do_not_disturb_on_outlined),
                                title: Text('Close thread'),
                                contentPadding: EdgeInsets.zero,
                              ),
                            ),
                          if (place.canReopen)
                            const PopupMenuItem(
                              value: 'reopen',
                              child: ListTile(
                                leading: Icon(Icons.lock_open_outlined),
                                title: Text('Re-open thread'),
                                contentPadding: EdgeInsets.zero,
                              ),
                            ),
                          PopupMenuItem(
                            value: 'password',
                            child: ListTile(
                              leading: Icon(
                                place.isPrivate
                                    ? Icons.grid_3x3
                                    : Icons.lock_person_outlined,
                              ),
                              title: Text(
                                place.isPrivate
                                    ? 'Change pattern lock'
                                    : 'Set pattern lock',
                              ),
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                          if (place.isPrivate)
                            const PopupMenuItem(
                              value: 'access',
                              child: ListTile(
                                leading: Icon(Icons.group_outlined),
                                title: Text('Manage access'),
                                contentPadding: EdgeInsets.zero,
                              ),
                            ),
                        ],
                      ),
                  ],
                ),
                // Body = optional status banner + message list.
                body: Column(
                  children: [
                    if (place != null && !place.canAcceptMessages)
                      _ThreadStatusBanner(place: place),
                    Expanded(
                      child: messagesAsync.when(
                        loading: () =>
                            const Center(child: CircularProgressIndicator()),
                        error: (e, _) => Center(child: Text('Error: $e')),
                        data: (messages) => messages.isEmpty
                            ? const _EmptyState()
                            : ListView.builder(
                                controller: _scrollController,
                                // Extra bottom padding so the FAB never obscures the
                                // last message (FAB 56 + margin 16 + breathing 16).
                                padding: const EdgeInsets.only(
                                  top: 8,
                                  bottom: 88,
                                ),
                                itemCount: messages.length,
                                itemBuilder: (context, index) {
                                  final message = messages[index];
                                  final isOwn =
                                      message.author.id == currentUser?.id;
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
                    ),
                  ],
                ),

                // FAB — opens the compose overlay (state flag + slide-up animation
                // in a Stack sibling layer below).  heroTag is unique to prevent
                // Hero conflicts with the map screen's FABs ('mapAddNote',
                // 'tracking').  Hidden when the thread is closed / expired / full.
                floatingActionButton: canPostMessage
                    ? FloatingActionButton(
                        heroTag: 'noteCompose',
                        onPressed: _openCompose,
                        tooltip: 'Write a message',
                        child: const Icon(Icons.edit_outlined),
                      )
                    : null,

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
                    position:
                        Tween<Offset>(
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
// Thread status banner — shown when the thread can't accept new messages
// ---------------------------------------------------------------------------

class _ThreadStatusBanner extends StatelessWidget {
  final PlaceEntity place;
  const _ThreadStatusBanner({required this.place});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Resolve the most relevant reason, in priority order.
    final (IconData icon, String text) = switch (place) {
      _ when place.isArchived || place.isExpired => (
        Icons.inventory_2_outlined,
        'This note has been archived. It is read-only.',
      ),
      _ when place.isAtMessageLimit => (
        Icons.do_not_disturb_on_outlined,
        'This thread reached its ${AppConfig.maxMessagesPerThread}-message '
            'limit and is now closed.',
      ),
      _ when place.closedReason == ClosedReason.messageLimit => (
        Icons.do_not_disturb_on_outlined,
        'This thread is full and closed.',
      ),
      _ => (
        Icons.lock_outline,
        'The owner closed this thread. It is read-only.',
      ),
    };

    return Material(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Locked view — shown when a private note has not been unlocked
// ---------------------------------------------------------------------------

class _LockedNoteView extends StatelessWidget {
  final String title;
  final String? lockHint;
  final VoidCallback onUnlock;

  const _LockedNoteView({
    required this.title,
    this.lockHint,
    required this.onUnlock,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.lock_outline,
                size: 64,
                color: theme.colorScheme.outline,
              ),
              const SizedBox(height: 16),
              Text('This note is private', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(
                'Draw the pattern lock to read and post messages here.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if (lockHint case final hint? when hint.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  'Hint: $hint',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: onUnlock,
                icon: const Icon(Icons.key_outlined),
                label: const Text('Draw pattern'),
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
