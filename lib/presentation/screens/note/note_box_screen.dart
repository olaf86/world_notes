import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../../../config/app_config.dart';
import '../../../core/theme/note_themes.dart';
import '../../../core/utils/password_util.dart';
import '../../../core/utils/pattern_lock_util.dart';
import '../../../domain/entities/message_entity.dart';
import '../../../domain/entities/place_entity.dart';
import '../../../domain/entities/note_theme.dart';
import '../../../domain/policies/note_permissions.dart';
import '../../providers/providers.dart';
import '../../widgets/map/static_note_mini_map.dart';
import '../../widgets/loading_skeleton.dart';
import '../../widgets/note/manage_access_sheet.dart';
import '../../widgets/note/message_bubble.dart';
import '../../widgets/note/message_creation_overlay.dart';
import '../../widgets/note/note_lock_setup_dialog.dart';
import '../../widgets/note/note_theme_picker.dart';
import '../../widgets/note/user_avatar_badge.dart';
import '../../widgets/note/visitor_map_overlay.dart';
import 'note_creation_screen.dart';

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class NoteBoxScreen extends ConsumerStatefulWidget {
  final String placeId;
  final String placeTitle;
  final bool readOnly;
  final NoteAccessValidationRequest? accessValidation;

  const NoteBoxScreen({
    super.key,
    required this.placeId,
    required this.placeTitle,
    this.readOnly = false,
    this.accessValidation,
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

  // ── Message editor overlay state ──────────────────────────────────────────
  //
  // The message creation UI is rendered as an overlay inside this screen's
  // own widget tree, not as a separate Navigator route.  Every Navigator-
  // based attempt (Navigator.push, showModalBottomSheet, ShellRoute child
  // route) triggered the '!semantics.parentDataDirty' loop on this screen
  // because of the BlockSemantics widget that ModalBarrier injects.  An
  // overlay driven purely by an AnimationController bypasses Navigator
  // entirely, so no extra ModalBarrier / BlockSemantics layer is added.
  late final AnimationController _messageEditorController;
  bool _isMessageEditorOpen = false;
  bool _preparingMessageEditor = false;
  String? _highlightedAuthorId;
  String? _visitRecordedForPlaceId;

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _messageEditorController = AnimationController(
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
    _messageEditorController.dispose();
    super.dispose();
  }

  // ── Ad loading ────────────────────────────────────────────────────────────

  void _loadAdIfNeeded() {
    if (!AppConfig.supportsMobileAds) return;
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

  // ── Message editor overlay ────────────────────────────────────────────────

  Future<void> _openMessageEditor() async {
    if (_isMessageEditorOpen || _preparingMessageEditor || widget.readOnly) {
      return;
    }
    setState(() => _preparingMessageEditor = true);
    try {
      if (!mounted) return;
      setState(() => _isMessageEditorOpen = true);
      _messageEditorController.forward();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Cannot write here: $e')));
      }
    } finally {
      if (mounted) setState(() => _preparingMessageEditor = false);
    }
  }

  Future<void> _closeMessageEditor() async {
    if (!_isMessageEditorOpen) return;
    await _messageEditorController.reverse();
    if (mounted) setState(() => _isMessageEditorOpen = false);
  }

  void _toggleAuthorHighlight(String authorId) {
    setState(() {
      _highlightedAuthorId = _highlightedAuthorId == authorId ? null : authorId;
    });
  }

  // ── Delete ────────────────────────────────────────────────────────────────

  Future<void> _confirmDeleteMessage(MessageEntity message) async {
    final isAwaitingPublication = !message.isPublished;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          isAwaitingPublication ? 'Cancel scheduled message' : 'Delete message',
        ),
        content: Text(
          isAwaitingPublication
              ? 'Cancel this scheduled message? Its reserved slot will be freed.'
              : 'Are you sure you want to delete this message? '
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
            child: Text(isAwaitingPublication ? 'Cancel message' : 'Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      final repository = ref.read(messageRepositoryProvider);
      if (isAwaitingPublication) {
        await repository.cancelScheduledMessage(
          placeId: widget.placeId,
          messageId: message.id,
        );
      } else {
        await repository.deleteMessage(
          placeId: widget.placeId,
          messageId: message.id,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to delete: $e')));
      }
    }
  }

  // ── Report ────────────────────────────────────────────────────────────────

  Future<void> _openReportMessageScreen(MessageEntity message) async {
    final reported = await context.push<bool>(
      '/note/${widget.placeId}/messages/${message.id}/report',
    );
    if (!mounted || reported != true) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Report submitted. Thank you for helping keep this community safe.',
        ),
      ),
    );
  }

  Future<void> _setMessageLike(MessageEntity message, bool liked) async {
    try {
      await ref
          .read(messageRepositoryProvider)
          .setMessageLike(
            placeId: widget.placeId,
            messageId: message.id,
            liked: liked,
          );
    } on FirebaseFunctionsException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.message ?? 'Could not update like.')),
        );
      }
      rethrow;
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not update like. Check your connection.'),
          ),
        );
      }
      rethrow;
    }
  }

  // ── Maintainer thread controls ────────────────────────────────────────────

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

  Future<void> _archiveNote() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Archive this note?'),
        content: const Text(
          'It will disappear from the map, become read-only, and free one '
          'note slot. You cannot restore the archived note, but you can '
          'create a new note from its title, description, and location later.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Archive'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await ref.read(placeRepositoryProvider).archivePlace(widget.placeId);
      if (mounted && context.canPop()) context.pop();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to archive note: $error')));
    }
  }

  /// Maintainer: open the access-management sheet.
  void _showManageAccess() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => ManageAccessSheet(placeId: widget.placeId),
    );
  }

  void _showThemePicker(PlaceEntity place) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => Theme(
        data: NoteThemes.themed(context, place.themeId),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Change theme',
                    style: Theme.of(sheetContext).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'This changes the note appearance for everyone.',
                    style: Theme.of(sheetContext).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 16),
                  NoteThemePicker(
                    selected: place.themeId,
                    onChanged: (themeId) {
                      Navigator.of(sheetContext).pop();
                      _setNoteTheme(themeId);
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _setNoteTheme(NoteThemeId themeId) async {
    try {
      await ref
          .read(placeRepositoryProvider)
          .setNoteTheme(placeId: widget.placeId, themeId: themeId);
    } on FirebaseFunctionsException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message ?? 'Could not change theme.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Could not change theme.')));
    }
  }

  void _recordVisitIfNeeded({
    required PlaceEntity place,
    required NotePermissions permissions,
    required String? currentUserId,
  }) {
    if (currentUserId == null ||
        !permissions.canReadContent ||
        _visitRecordedForPlaceId == place.id) {
      return;
    }
    _visitRecordedForPlaceId = place.id;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_recordVisit(place.id));
    });
  }

  Future<void> _recordVisit(String placeId) async {
    try {
      await ref.read(placeRepositoryProvider).recordNoteVisit(placeId);
    } catch (error, stackTrace) {
      assert(() {
        debugPrint('recordNoteVisit failed for $placeId: $error');
        return true;
      }());
      await ref
          .read(firebaseCrashlyticsProvider)
          .recordError(
            error,
            stackTrace,
            reason: 'recordNoteVisit failed for $placeId',
            fatal: false,
          );
    }
  }

  // ── Private access (set lock / unlock) ───────────────────────────────────

  void _showPatternTooLongSnack() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Pattern is too long. Use 30 nodes or fewer.'),
      ),
    );
  }

  /// Creator: set or change the note lock (locks it as private).
  Future<void> _promptSetPassword({required bool isChange}) async {
    final place = ref.read(placeProvider(widget.placeId)).valueOrNull;
    final saved = await showDialog<NoteLockSetupValue>(
      context: context,
      builder: (_) => NoteLockSetupDialog(
        title: isChange ? 'Change lock' : 'Set lock',
        initialLockType: place?.lockType,
        initialHint: place?.lockHint,
        onPatternTooLong: _showPatternTooLongSnack,
        onSubmit: (value) async {
          try {
            await ref
                .read(placeRepositoryProvider)
                .setNotePassword(
                  placeId: widget.placeId,
                  password: value.secret,
                  lockType: value.lockType,
                  lockHint: value.lockHint,
                );
            return null;
          } on FirebaseFunctionsException catch (e) {
            assert(() {
              debugPrint(
                'setNotePassword failed: code=${e.code}, '
                'message=${e.message}, details=${e.details}',
              );
              return true;
            }());
            final isSignedIn =
                ref.read(firebaseAuthProvider).currentUser != null;
            return _lockSaveErrorMessage(e, isSignedIn: isSignedIn);
          } catch (_) {
            return 'Failed to save the lock.';
          }
        },
      ),
    );
    if (saved != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lock saved. This note is private.')),
      );
    }
  }

  String _lockSaveErrorMessage(
    FirebaseFunctionsException error, {
    required bool isSignedIn,
  }) {
    return switch (error.code) {
      'unauthenticated' =>
        isSignedIn
            ? 'Could not verify this app. Please try again.'
            : 'Authentication failed. Please sign in again.',
      'permission-denied' => 'Only the note creator can change this lock.',
      'not-found' => 'Note not found.',
      'invalid-argument' ||
      'failed-precondition' => error.message ?? 'Failed to save the lock.',
      'unavailable' ||
      'deadline-exceeded' => 'Network error. Check your connection.',
      _ => error.message ?? 'Failed to save the lock.',
    };
  }

  /// Visitor: enter the configured secret to unlock a private note. On success
  /// the membership stream updates and the screen rebuilds with access.
  Future<void> _promptUnlock() async {
    final place = ref.read(placeProvider(widget.placeId)).valueOrNull;
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        final lockType = place?.lockType == NoteLockType.password
            ? NoteLockType.password
            : NoteLockType.pattern;
        var password = '';
        List<int> pattern = const [];
        String? error;
        var busy = false;
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            Future<void> submit() async {
              if (busy) return;
              final validation = switch (lockType) {
                NoteLockType.password => PasswordUtil.validate(password),
                NoteLockType.pattern => PatternLockUtil.validate(pattern),
              };
              if (validation != null) {
                setLocal(() => error = validation);
                return;
              }
              final secret = switch (lockType) {
                NoteLockType.password => password,
                NoteLockType.pattern => PatternLockUtil.encode(pattern),
              };
              setLocal(() {
                busy = true;
                error = null;
              });
              try {
                await ref
                    .read(placeRepositoryProvider)
                    .unlockNote(placeId: widget.placeId, password: secret);
                // A message query may have failed before the private-note
                // membership grant reached the client. Ensure the unlocked
                // view always starts with a fresh Firestore subscription.
                ref.invalidate(messagesProvider(widget.placeId));
                if (ctx.mounted) Navigator.pop(ctx);
              } on FirebaseFunctionsException catch (e) {
                setLocal(() {
                  busy = false;
                  error = switch (e.code) {
                    'permission-denied' =>
                      lockType == NoteLockType.pattern
                          ? 'Incorrect pattern.'
                          : 'Incorrect password.',
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
              title: const Text('Unlock note'),
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
                    if (lockType == NoteLockType.password)
                      PasswordLockInput(
                        onChanged: (value) {
                          setLocal(() {
                            password = value;
                            error = null;
                          });
                        },
                        onSubmitted: submit,
                      )
                    else
                      PatternLockInputWithClear(
                        enabled: !busy,
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
    final placeAsync = ref.watch(placeProvider(widget.placeId));
    final accessValidation = widget.accessValidation;
    final accessAsync = accessValidation == null
        ? null
        : ref.watch(noteAccessValidationProvider(accessValidation));
    final place = placeAsync.valueOrNull;
    final now = DateTime.now();

    if (accessAsync?.isLoading ?? false) {
      return _LoadingNoteView(title: widget.placeTitle);
    }
    if (accessAsync?.hasError ?? false) {
      return _NoteAccessErrorView(
        title: widget.placeTitle,
        onRetry: () =>
            ref.invalidate(noteAccessValidationProvider(accessValidation!)),
      );
    }
    if (placeAsync.hasError && place == null) {
      return _UnavailableNoteView(title: widget.placeTitle);
    }
    if (place == null) {
      return _LoadingNoteView(title: widget.placeTitle);
    }

    final creator = ref.watch(
      noteCreatorProfileProvider(place.createdByUserId),
    );
    final membership = place.isPrivate
        ? ref.watch(noteMembershipProvider(widget.placeId)).valueOrNull
        : null;
    final permissions = place.permissionsFor(
      uid: currentUser?.id,
      membership: membership,
      readOnly: widget.readOnly,
      now: now,
    );
    final displayTitle = place.title;
    // Private-note access gate. If the membership grant is absent or stale,
    // show the locked view and DON'T subscribe to messages.
    if (place.isPrivate && !permissions.canReadContent) {
      return _LockedNoteView(
        title: displayTitle,
        lockType: place.lockType,
        lockHint: place.lockHint,
        onUnlock: _promptUnlock,
      );
    }

    // Public, owned, or unlocked — safe to read messages now.
    _recordVisitIfNeeded(
      place: place,
      permissions: permissions,
      currentUserId: currentUser?.id,
    );
    final messagesAsync = ref.watch(messagesProvider(widget.placeId));

    // Exclude this screen's semantics while a dialog, report sheet, or message
    // editor is shown on top — prevents parentDataDirty noise when two routes
    // coexist.
    final bool isCurrent = ModalRoute.of(context)?.isCurrent ?? true;

    // Defensive size boundary. A route above this one may put the screen
    // offstage; retaining finite constraints keeps its Scaffold, FAB, and ad
    // slot stable until the user returns.
    final size = MediaQuery.sizeOf(context);
    final palette = NoteThemes.paletteOf(context, place.themeId);

    return Theme(
      data: NoteThemes.themed(context, place.themeId),
      child: PopScope(
        // Intercept back gesture / hardware back when the message editor is
        // visible — close the overlay instead of popping the route.
        canPop: !_isMessageEditorOpen,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop && _isMessageEditorOpen) _closeMessageEditor();
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
                Positioned.fill(
                  child: DecoratedBox(
                    key: ValueKey('note-theme-page-${place.themeId.name}'),
                    decoration: BoxDecoration(gradient: palette.pageGradient),
                  ),
                ),
                // ── Base layer: the message-box screen ──────────────────────
                Semantics(
                  identifier: 'screen-note-detail-${place.id}',
                  child: Scaffold(
                    backgroundColor: Colors.transparent,
                    appBar: AppBar(
                      backgroundColor: Colors.transparent,
                      surfaceTintColor: Colors.transparent,
                      leading: const _NoteBackButton(),
                      title: Text(displayTitle),
                      actions: [
                        if (!isPremium)
                          IconButton(
                            icon: const Icon(Icons.star_outline),
                            tooltip: 'Go PRO',
                            onPressed: () => context.push('/subscription'),
                          ),
                        if (place.isArchived &&
                            place.isMaintainedBy(currentUser?.id))
                          IconButton(
                            icon: const Icon(Icons.add_location_alt_outlined),
                            tooltip: 'Create new note from archive',
                            onPressed: () => context.push(
                              '/note/create',
                              extra: NoteCreationDraft.fromPlace(place),
                            ),
                          ),
                        if (permissions.hasThreadActions)
                          PopupMenuButton<String>(
                            tooltip: 'Thread options',
                            onSelected: (value) {
                              if (value == 'close') _closeThread();
                              if (value == 'reopen') _reopenThread();
                              if (value == 'archive') _archiveNote();
                              if (value == 'password') {
                                _promptSetPassword(isChange: place.isPrivate);
                              }
                              if (value == 'access') _showManageAccess();
                              if (value == 'theme') _showThemePicker(place);
                            },
                            itemBuilder: (ctx) => [
                              if (permissions.canCloseThread)
                                const PopupMenuItem(
                                  value: 'close',
                                  child: ListTile(
                                    leading: Icon(
                                      Icons.do_not_disturb_on_outlined,
                                    ),
                                    title: Text('Close thread'),
                                    contentPadding: EdgeInsets.zero,
                                  ),
                                ),
                              if (permissions.canReopenThread)
                                const PopupMenuItem(
                                  value: 'reopen',
                                  child: ListTile(
                                    leading: Icon(Icons.lock_open_outlined),
                                    title: Text('Re-open thread'),
                                    contentPadding: EdgeInsets.zero,
                                  ),
                                ),
                              if (permissions.canChangeLock)
                                PopupMenuItem(
                                  value: 'password',
                                  child: ListTile(
                                    leading: Icon(
                                      place.isPrivate
                                          ? Icons.lock_reset
                                          : Icons.lock_person_outlined,
                                    ),
                                    title: Text(
                                      place.isPrivate
                                          ? 'Change lock'
                                          : 'Set lock',
                                    ),
                                    contentPadding: EdgeInsets.zero,
                                  ),
                                ),
                              if (permissions.canChangeTheme)
                                const PopupMenuItem(
                                  value: 'theme',
                                  child: ListTile(
                                    leading: Icon(Icons.palette_outlined),
                                    title: Text('Change theme'),
                                    contentPadding: EdgeInsets.zero,
                                  ),
                                ),
                              if (permissions.canManageAccess)
                                const PopupMenuItem(
                                  value: 'access',
                                  child: ListTile(
                                    leading: Icon(Icons.group_outlined),
                                    title: Text('Manage access'),
                                    contentPadding: EdgeInsets.zero,
                                  ),
                                ),
                              if (permissions.canArchive) ...[
                                const PopupMenuDivider(),
                                const PopupMenuItem(
                                  value: 'archive',
                                  child: ListTile(
                                    leading: Icon(Icons.archive_outlined),
                                    title: Text('Archive note'),
                                    contentPadding: EdgeInsets.zero,
                                  ),
                                ),
                              ],
                            ],
                          ),
                      ],
                    ),
                    // Body = optional status banner + message list.
                    body: Column(
                      children: [
                        if (widget.readOnly) const _ReadOnlyBanner(),
                        if (!place.canAcceptMessagesAt(now))
                          _ThreadStatusBanner(place: place, now: now),
                        StaticNoteMiniMap(
                          place: place,
                          topLeftOverlay: _CreatorMapOverlay(
                            name: creator?.name,
                            photoUrl: creator?.photoUrl,
                            onTap: () =>
                                context.push('/users/${place.createdByUserId}'),
                          ),
                          showTopLeftConnector: true,
                          topRightOverlay: VisitorMapOverlay(
                            placeId: widget.placeId,
                            footprintEnabled: place.footprintEnabled,
                            visitorCount: place.visitorCount,
                          ),
                        ),
                        _NoteLikeRow(
                          placeId: widget.placeId,
                          serverLikeCount: place.likeCount,
                          canLike: permissions.canLikeNote,
                          isOwnNote: currentUser?.id == place.createdByUserId,
                        ),
                        Expanded(
                          child: messagesAsync.when(
                            loading: () => const Center(
                              child: CircularProgressIndicator(),
                            ),
                            error: (e, _) => Center(child: Text('Error: $e')),
                            data: (messages) {
                              return messages.isEmpty
                                  ? const _EmptyState()
                                  : ListView.builder(
                                      controller: _scrollController,
                                      // Extra bottom padding so the FAB never
                                      // obscures the last message.
                                      padding: const EdgeInsets.only(
                                        top: 8,
                                        bottom: 88,
                                      ),
                                      itemCount: messages.length,
                                      itemBuilder: (context, index) {
                                        final item = messages[index];
                                        final message = item.message;
                                        final isOwn =
                                            message.author.id ==
                                            currentUser?.id;
                                        return MessageBubble(
                                          key: ValueKey(message.id),
                                          message: message,
                                          likeState: item.likeState,
                                          isOwn: isOwn,
                                          canLike: permissions.canLikeMessage(
                                            message,
                                            now: now,
                                          ),
                                          onLikeChanged: (liked) =>
                                              _setMessageLike(message, liked),
                                          isAuthorHighlighted:
                                              _highlightedAuthorId ==
                                              message.author.id,
                                          onAuthorTap: _toggleAuthorHighlight,
                                          onDelete: isOwn
                                              ? () => _confirmDeleteMessage(
                                                  message,
                                                )
                                              : null,
                                          onReport: !isOwn
                                              ? () => _openReportMessageScreen(
                                                  message,
                                                )
                                              : null,
                                        );
                                      },
                                    );
                            },
                          ),
                        ),
                      ],
                    ),

                    // FAB — opens the message editor (state flag + slide-up animation
                    // in a Stack sibling layer below).  heroTag is unique to prevent
                    // Hero conflicts with the map screen's FABs ('mapAddNote',
                    // 'tracking').  Hidden when the thread is closed / expired / full.
                    floatingActionButton: permissions.canPostMessage
                        ? Semantics(
                            identifier: 'action-write-message',
                            button: true,
                            child: FloatingActionButton(
                              heroTag: 'noteMessageEditor',
                              onPressed: _preparingMessageEditor
                                  ? null
                                  : _openMessageEditor,
                              tooltip: 'Write a message',
                              child: _preparingMessageEditor
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.edit_outlined),
                            ),
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
                ),

                // ── Overlay layer: message editor, slides up from the bottom ─
                //
                // Rendered only while `_isMessageEditorOpen` is true.  The animation
                // controller drives a SlideTransition from (0, 1) → (0, 0).
                // Because this overlay lives in the SAME Stack as the base
                // Scaffold (not a Navigator route), no ModalBarrier /
                // BlockSemantics is added to the tree — sidestepping the
                // '!semantics.parentDataDirty' loop seen with route pushes.
                if (_isMessageEditorOpen)
                  Positioned.fill(
                    child: SlideTransition(
                      position:
                          Tween<Offset>(
                            begin: const Offset(0, 1),
                            end: Offset.zero,
                          ).animate(
                            CurvedAnimation(
                              parent: _messageEditorController,
                              curve: Curves.easeOutCubic,
                              reverseCurve: Curves.easeInCubic,
                            ),
                          ),
                      child: MessageCreationOverlay(
                        placeId: widget.placeId,
                        onClose: _closeMessageEditor,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CreatorMapOverlay extends StatelessWidget {
  final String? name;
  final String? photoUrl;
  final VoidCallback onTap;

  const _CreatorMapOverlay({
    required this.name,
    required this.photoUrl,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final displayName = name?.trim().isNotEmpty == true
        ? name!.trim()
        : UserAvatarBadge.defaultName;

    return Semantics(
      button: true,
      label: 'View $displayName\'s profile',
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          key: const ValueKey('creator-map-overlay'),
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.all(2),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox.square(
                  dimension: 32,
                  child: UserAvatarBadge(name: name, photoUrl: photoUrl),
                ),
                const SizedBox(height: 3),
                Container(
                  constraints: const BoxConstraints(maxWidth: 92),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface.withValues(alpha: 0.94),
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.16),
                        blurRadius: 3,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                  child: Text(
                    displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NoteLikeRow extends ConsumerStatefulWidget {
  final String placeId;
  final int serverLikeCount;
  final bool canLike;
  final bool isOwnNote;

  const _NoteLikeRow({
    required this.placeId,
    required this.serverLikeCount,
    required this.canLike,
    required this.isOwnNote,
  });

  @override
  ConsumerState<_NoteLikeRow> createState() => _NoteLikeRowState();
}

class _NoteLikeRowState extends ConsumerState<_NoteLikeRow> {
  Timer? _debounce;
  bool _initialized = false;
  bool _serverLiked = false;
  bool _displayLiked = false;
  int _displayLikeCount = 0;
  bool _hasLocalOverride = false;
  bool _sending = false;
  bool _flushAfterSend = false;

  @override
  void dispose() {
    _debounce?.cancel();
    if (_hasLocalOverride && _displayLiked != _serverLiked) {
      unawaited(
        ref
            .read(placeRepositoryProvider)
            .setNoteLike(placeId: widget.placeId, liked: _displayLiked),
      );
    }
    super.dispose();
  }

  /// Applies the latest Firestore state to the optimistic display state.
  ///
  /// While a tap is pending or being sent, the local display wins so the heart
  /// does not flicker. Once Firestore confirms both the like state and count,
  /// the local override is cleared and later server changes drive the display.
  void _applyServerLikeState({
    required bool serverLiked,
    required int serverCount,
  }) {
    _serverLiked = serverLiked;
    if (!_initialized) {
      _initialized = true;
      _displayLiked = serverLiked;
      _displayLikeCount = serverCount;
      return;
    }
    if (!_hasLocalOverride && !_sending && _debounce == null) {
      _displayLiked = serverLiked;
      _displayLikeCount = serverCount;
      return;
    }
    if (_hasLocalOverride &&
        !_sending &&
        _debounce == null &&
        _displayLiked == serverLiked &&
        _displayLikeCount == serverCount) {
      _hasLocalOverride = false;
    }
  }

  void _toggleLike() {
    if (!widget.canLike) return;
    final nextLiked = !_displayLiked;
    final countDelta = nextLiked ? 1 : -1;
    setState(() {
      _displayLiked = nextLiked;
      final nextCount = _displayLikeCount + countDelta;
      _displayLikeCount = nextCount < 0 ? 0 : nextCount;
      _hasLocalOverride = true;
    });
    _scheduleFlush();
  }

  void _scheduleFlush() {
    _debounce?.cancel();
    _debounce = Timer(AppConfig.likeDebounceDuration, () {
      _debounce = null;
      unawaited(_flushLike());
    });
  }

  Future<void> _flushLike() async {
    if (!mounted) return;
    if (_sending) {
      _flushAfterSend = true;
      return;
    }
    final desiredLiked = _displayLiked;
    if (desiredLiked == _serverLiked) {
      setState(() {
        _hasLocalOverride = false;
        _displayLikeCount = widget.serverLikeCount;
      });
      return;
    }

    setState(() {
      _sending = true;
      _flushAfterSend = false;
    });
    try {
      await ref
          .read(placeRepositoryProvider)
          .setNoteLike(placeId: widget.placeId, liked: desiredLiked);
      if (!mounted) return;
      setState(() {
        _sending = false;
      });
      if (_flushAfterSend || _displayLiked != desiredLiked) {
        _flushAfterSend = false;
        _scheduleFlush();
      }
    } on FirebaseFunctionsException catch (error) {
      if (!mounted) return;
      _showFailure(error.message ?? 'Could not update like.');
    } catch (_) {
      if (!mounted) return;
      _showFailure('Could not update like. Check your connection.');
    }
  }

  void _showFailure(String message) {
    setState(() {
      _sending = false;
      _flushAfterSend = false;
      _hasLocalOverride = false;
      _displayLiked = _serverLiked;
      _displayLikeCount = widget.serverLikeCount;
    });
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final likedAsync = ref.watch(noteLikeProvider(widget.placeId));
    final serverLiked = likedAsync.valueOrNull ?? false;
    _applyServerLikeState(
      serverLiked: serverLiked,
      serverCount: widget.serverLikeCount,
    );

    final icon = _displayLiked ? Icons.favorite : Icons.favorite_border;
    final color = _displayLiked
        ? colorScheme.error
        : colorScheme.onSurfaceVariant;
    final tooltip = widget.canLike
        ? (_displayLiked ? 'Unlike note' : 'Like note')
        : widget.isOwnNote
        ? 'You cannot like your own note'
        : 'Like unavailable';

    return Material(
      color: colorScheme.surface.withValues(alpha: 0.78),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Row(
          children: [
            Semantics(
              identifier: 'action-toggle-note-like',
              button: true,
              toggled: _displayLiked,
              child: IconButton(
                tooltip: tooltip,
                onPressed: widget.canLike ? _toggleLike : null,
                icon: Icon(icon, color: widget.canLike ? color : null),
              ),
            ),
            const SizedBox(width: 4),
            Text(
              '$_displayLikeCount like${_displayLikeCount == 1 ? '' : 's'}',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            if (_sending) ...[
              const SizedBox(width: 8),
              SizedBox.square(
                dimension: 12,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
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
  final DateTime now;
  const _ThreadStatusBanner({required this.place, required this.now});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Resolve the most relevant reason, in priority order.
    final (IconData icon, String text) = switch (place) {
      _ when !place.isPublishedAt(now) => (
        Icons.event_outlined,
        'This note is scheduled and is not accepting messages yet.',
      ),
      _ when place.isArchived || place.isExpiredAt(now) => (
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
        'A maintainer closed this thread. It is read-only.',
      ),
    };

    return Material(
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.82),
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

class _NoteBackButton extends StatelessWidget {
  const _NoteBackButton();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      identifier: 'action-close-note-detail',
      button: true,
      child: BackButton(
        key: const ValueKey('note-detail-back-button'),
        onPressed: () {
          if (context.canPop()) {
            context.pop();
          } else {
            context.go('/map');
          }
        },
      ),
    );
  }
}

class _UnavailableNoteView extends StatelessWidget {
  final String title;

  const _UnavailableNoteView({required this.title});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        leading: const _NoteBackButton(),
        title: Text(title.isEmpty ? 'Note' : title),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.lock_clock_outlined,
                size: 48,
                color: theme.colorScheme.outline,
              ),
              const SizedBox(height: 12),
              Text(
                'This note is not available.',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 6),
              Text(
                'It may not be published yet, may have expired, or may no '
                'longer be accessible from here.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
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

class _NoteAccessErrorView extends StatelessWidget {
  final String title;
  final VoidCallback onRetry;

  const _NoteAccessErrorView({required this.title, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        leading: const _NoteBackButton(),
        title: Text(title.isEmpty ? 'Note' : title),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.near_me_disabled_outlined,
                size: 48,
                color: theme.colorScheme.outline,
              ),
              const SizedBox(height: 12),
              Text(
                'Could not open this note.',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 6),
              Text(
                'Check your connection and make sure you are still nearby.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Try again'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LoadingNoteView extends StatelessWidget {
  final String title;

  const _LoadingNoteView({required this.title});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const _NoteBackButton(),
        title: Text(title.isEmpty ? 'Note' : title),
      ),
      body: const SkeletonView(
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 12),
              child: SkeletonBox(
                width: double.infinity,
                height: 150,
                borderRadius: BorderRadius.all(Radius.circular(16)),
              ),
            ),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  SkeletonBox(
                    width: 36,
                    height: 36,
                    borderRadius: BorderRadius.all(Radius.circular(18)),
                  ),
                  SizedBox(width: 12),
                  Expanded(child: SkeletonBox(height: 14)),
                  SizedBox(width: 32),
                  SkeletonBox(width: 56, height: 28),
                ],
              ),
            ),
            SizedBox(height: 8),
            Expanded(child: SkeletonListView(itemCount: 4)),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Read-only banner — shown when opened from My Notes
// ---------------------------------------------------------------------------

class _ReadOnlyBanner extends StatelessWidget {
  const _ReadOnlyBanner();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.82),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Icon(
              Icons.visibility_outlined,
              size: 18,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Read-only from My Notes.',
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
  final NoteLockType? lockType;
  final String? lockHint;
  final VoidCallback onUnlock;

  const _LockedNoteView({
    required this.title,
    this.lockType,
    this.lockHint,
    required this.onUnlock,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bodyText = switch (lockType) {
      NoteLockType.password => 'Enter the password to read and post messages.',
      NoteLockType.pattern => 'Draw the pattern to read and post messages.',
      null => 'Unlock this note to read and post messages.',
    };
    final buttonText = switch (lockType) {
      NoteLockType.password => 'Enter password',
      NoteLockType.pattern => 'Draw pattern',
      null => 'Unlock',
    };
    final buttonIcon = switch (lockType) {
      NoteLockType.pattern => Icons.grid_3x3,
      _ => Icons.key_outlined,
    };

    return Scaffold(
      appBar: AppBar(leading: const _NoteBackButton(), title: Text(title)),
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
                bodyText,
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
                icon: Icon(buttonIcon),
                label: Text(buttonText),
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

// The message editor is rendered as an in-tree overlay; see
// MessageCreationOverlay in lib/presentation/widgets/note/message_creation_overlay.dart.
