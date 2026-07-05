import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../../../config/app_config.dart';
import '../../../core/utils/password_util.dart';
import '../../../core/utils/pattern_lock_util.dart';
import '../../../domain/entities/message_entity.dart';
import '../../../domain/entities/place_entity.dart';
import '../../../domain/policies/note_permissions.dart';
import '../../providers/providers.dart';
import '../../widgets/map/static_note_mini_map.dart';
import '../../widgets/note/manage_access_sheet.dart';
import '../../widgets/note/message_bubble.dart';
import '../../widgets/note/message_creation_overlay.dart';
import '../../widgets/note/note_lock_setup_dialog.dart';

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

enum _NearbyLocationMode { whileUsingApp, background }

class NoteBoxScreen extends ConsumerStatefulWidget {
  final String placeId;
  final String placeTitle;
  final bool readOnly;

  const NoteBoxScreen({
    super.key,
    required this.placeId,
    required this.placeTitle,
    this.readOnly = false,
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
  bool _nearbyNotificationBusy = false;
  String? _highlightedAuthorId;
  DateTime? _lastNearbyReadMarkedAt;

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
    final isScheduled = !message.isPublished;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          isScheduled ? 'Cancel scheduled message' : 'Delete message',
        ),
        content: Text(
          isScheduled
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
            child: Text(isScheduled ? 'Cancel message' : 'Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      final repository = ref.read(messageRepositoryProvider);
      if (isScheduled) {
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
          'note slot. Archived notes cannot be restored.',
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

  Future<bool> _showSystemSettingsDialog({required String message}) async {
    final openSettings = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.settings_outlined),
        title: const Text('Open system settings'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Not now'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.settings_outlined),
            label: const Text('Open settings'),
          ),
        ],
      ),
    );
    return openSettings ?? false;
  }

  Future<_NearbyLocationMode?> _chooseNearbyLocationMode() {
    final backgroundPermissionLabel = switch (defaultTargetPlatform) {
      TargetPlatform.iOS => '"Always"',
      TargetPlatform.android => '"Allow all the time"',
      _ => 'background location access',
    };
    return showDialog<_NearbyLocationMode>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.notifications_active_outlined),
        title: const Text('Choose when alerts work'),
        content: Text(
          'Nearby alerts can use location only while ${AppConfig.appName} is '
          'open. For alerts after you leave the app, set location access to '
          '$backgroundPermissionLabel.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.pop(ctx, _NearbyLocationMode.whileUsingApp),
            child: const Text('While using app'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, _NearbyLocationMode.background),
            child: const Text('Background alerts'),
          ),
        ],
      ),
    );
  }

  Future<void> _setNearbyNotification(bool enabled) async {
    if (_nearbyNotificationBusy) return;
    setState(() => _nearbyNotificationBusy = true);
    var openLocationSettingsAfterEnable = false;
    try {
      if (enabled) {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Notify when nearby'),
            content: Text(
              '${AppConfig.appName} uses your location to notify you about new '
              'messages when you are near this note.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Continue'),
              ),
            ],
          ),
        );
        if (confirmed != true) return;
        final notificationGranted = await ref
            .read(nearbyNotificationServiceProvider)
            .requestPermission();
        if (!notificationGranted) {
          if (!mounted) return;
          final openSettings = await _showSystemSettingsDialog(
            message:
                'Notifications are not allowed. Open system settings and '
                'enable notifications to receive nearby alerts.',
          );
          if (openSettings) await Geolocator.openAppSettings();
          return;
        }
        await ref
            .read(myNotesNotificationServiceProvider)
            .registerCurrentToken();
        final permission = await ref
            .read(locationServiceProvider)
            .ensurePermission();
        if (permission != LocationPermission.always &&
            permission != LocationPermission.whileInUse) {
          if (!mounted) return;
          final openSettings = await _showSystemSettingsDialog(
            message:
                'Location access is required for nearby alerts. Open system '
                'settings and allow location while using '
                '${AppConfig.appName}.',
          );
          if (openSettings) await Geolocator.openAppSettings();
          return;
        }
        if (permission == LocationPermission.whileInUse) {
          if (!mounted) return;
          final mode = await _chooseNearbyLocationMode();
          if (mode == null) return;
          openLocationSettingsAfterEnable =
              mode == _NearbyLocationMode.background;
        }
      }
      await ref
          .read(placeRepositoryProvider)
          .setNearbyNotification(placeId: widget.placeId, enabled: enabled);
      if (openLocationSettingsAfterEnable) {
        await Geolocator.openAppSettings();
      }
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      final message = switch (e.code) {
        'resource-exhausted' =>
          'Nearby alerts are limited to '
              '${AppConfig.nearbyNotificationLimit} notes. '
              'Turn one off first.',
        'failed-precondition' =>
          e.message ?? 'Nearby alerts are not available for this note.',
        _ => e.message ?? 'Could not update nearby alerts.',
      };
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _nearbyNotificationBusy = false);
    }
  }

  void _markNearbyNotificationReadIfNeeded({
    required bool nearbyEnabled,
    required List<MessageEntity> messages,
  }) {
    if (!nearbyEnabled || messages.isEmpty) return;
    final latest = messages
        .map((message) => message.publishAt)
        .reduce((a, b) => a.isAfter(b) ? a : b);
    final previous = _lastNearbyReadMarkedAt;
    if (previous != null && !latest.isAfter(previous)) return;
    _lastNearbyReadMarkedAt = latest;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref
          .read(placeRepositoryProvider)
          .markNearbyNotificationRead(widget.placeId);
    });
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
    final place = placeAsync.valueOrNull;
    final now = DateTime.now();

    if (placeAsync.hasError && place == null) {
      return _UnavailableNoteView(title: widget.placeTitle);
    }
    if (place == null) {
      return _LoadingNoteView(title: widget.placeTitle);
    }

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
    final nearbyAlertAsync = ref.watch(
      nearbyNotificationPlaceProvider(widget.placeId),
    );
    final nearbyAlert = nearbyAlertAsync.valueOrNull;
    final nearbyAlertEnabled = nearbyAlert?.isActive ?? false;

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
    final messagesAsync = ref.watch(messagesProvider(widget.placeId));

    // Exclude this screen's semantics while a dialog, report sheet, or message
    // editor is shown on top — prevents parentDataDirty noise when two routes
    // coexist.
    final bool isCurrent = ModalRoute.of(context)?.isCurrent ?? true;

    // Defensive constraint clamp.  Even with opaque:false on all push routes,
    // any future route that lands on top of NoteBoxScreen with opaque:true
    // would wrap this Scaffold in Offstage(offstage:true), pushing
    // BoxConstraints() (0..∞) into the FAB Column / Scaffold body and
    // re-triggering '!semantics.parentDataDirty' loops.  Same pattern as
    // _MainShell in router.dart.
    final size = MediaQuery.sizeOf(context);

    return PopScope(
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
              // ── Base layer: the message-box screen ──────────────────────
              Scaffold(
                appBar: AppBar(
                  title: Text(displayTitle),
                  actions: [
                    if (!isPremium)
                      IconButton(
                        icon: const Icon(Icons.star_outline),
                        tooltip: 'Go PRO',
                        onPressed: () => context.push('/subscription'),
                      ),
                    if (permissions.canSubscribeNearbyAlerts)
                      IconButton(
                        icon:
                            _nearbyNotificationBusy ||
                                nearbyAlertAsync.isLoading
                            ? const SizedBox.square(
                                dimension: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Icon(
                                nearbyAlertEnabled
                                    ? Icons.notifications_active_outlined
                                    : Icons.notifications_none_outlined,
                              ),
                        tooltip: nearbyAlertEnabled
                            ? 'Turn off nearby alerts'
                            : 'Notify when nearby',
                        onPressed:
                            _nearbyNotificationBusy ||
                                nearbyAlertAsync.isLoading
                            ? null
                            : () => _setNearbyNotification(!nearbyAlertEnabled),
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
                        },
                        itemBuilder: (ctx) => [
                          if (permissions.canCloseThread)
                            const PopupMenuItem(
                              value: 'close',
                              child: ListTile(
                                leading: Icon(Icons.do_not_disturb_on_outlined),
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
                                  place.isPrivate ? 'Change lock' : 'Set lock',
                                ),
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
                    StaticNoteMiniMap(place: place),
                    Expanded(
                      child: messagesAsync.when(
                        loading: () =>
                            const Center(child: CircularProgressIndicator()),
                        error: (e, _) => Center(child: Text('Error: $e')),
                        data: (messages) {
                          _markNearbyNotificationReadIfNeeded(
                            nearbyEnabled: nearbyAlertEnabled,
                            messages: messages,
                          );
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
                                    final message = messages[index];
                                    final isOwn =
                                        message.author.id == currentUser?.id;
                                    return MessageBubble(
                                      message: message,
                                      isOwn: isOwn,
                                      isAuthorHighlighted:
                                          _highlightedAuthorId ==
                                          message.author.id,
                                      onAuthorTap: _toggleAuthorHighlight,
                                      onDelete: isOwn
                                          ? () => _confirmDeleteMessage(message)
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
                    ? FloatingActionButton(
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

class _UnavailableNoteView extends StatelessWidget {
  final String title;

  const _UnavailableNoteView({required this.title});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(title.isEmpty ? 'Note' : title)),
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

class _LoadingNoteView extends StatelessWidget {
  final String title;

  const _LoadingNoteView({required this.title});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title.isEmpty ? 'Note' : title)),
      body: const Center(child: CircularProgressIndicator()),
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
      color: theme.colorScheme.surfaceContainerHighest,
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
