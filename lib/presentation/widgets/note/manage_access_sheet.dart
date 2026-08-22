import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/entities/note_administrator_entity.dart';
import '../../../domain/policies/note_permissions.dart';
import '../../../l10n/l10n.dart';
import '../../providers/providers.dart';

/// Manages delegated administrators and ordinary password access separately.
class ManageAccessSheet extends ConsumerStatefulWidget {
  const ManageAccessSheet({super.key, required this.placeId});

  final String placeId;

  @override
  ConsumerState<ManageAccessSheet> createState() => _ManageAccessSheetState();
}

class _ManageAccessSheetState extends ConsumerState<ManageAccessSheet> {
  final _targetUidController = TextEditingController();
  NoteAdministratorAccess? _administratorAccess;
  NoteAdministratorInvitationResult? _createdInvitation;
  bool _loading = true;
  bool _busy = false;
  bool _linkCopied = false;
  String? _error;
  Timer? _copyFeedbackTimer;

  @override
  void initState() {
    super.initState();
    _loadAdministratorAccess();
  }

  Future<void> _loadAdministratorAccess() async {
    try {
      final access = await ref
          .read(placeRepositoryProvider)
          .getNoteAdministratorAccess(widget.placeId);
      if (mounted) {
        setState(() {
          _administratorAccess = access;
          _error = null;
        });
      }
    } catch (error, stack) {
      _reportError('load administrator access', error, stack);
      if (mounted) {
        setState(() => _error = context.l10n.inviteLoadFailed);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _createInvitation() async {
    final targetUid = _targetUidController.text.trim();
    if (_busy || targetUid.isEmpty) return;
    final l10n = context.l10n;
    setState(() => _busy = true);
    try {
      final invitation = await ref
          .read(placeRepositoryProvider)
          .createNoteAdministratorInvitation(
            placeId: widget.placeId,
            targetUid: targetUid,
          );
      if (!mounted) return;
      setState(() {
        _createdInvitation = invitation;
        _linkCopied = false;
      });
      await _loadAdministratorAccess();
      _snack(l10n.administratorInviteCreated);
    } catch (error, stack) {
      _reportError('create administrator invitation', error, stack);
      _snack(l10n.inviteCreateFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _copyCreatedLink() async {
    final invitation = _createdInvitation;
    if (invitation == null) return;
    final link = ref
        .read(selectedWorldNavigationProvider)
        .inviteUrl(invitation.token);
    await Clipboard.setData(ClipboardData(text: link));
    if (!mounted) return;
    _copyFeedbackTimer?.cancel();
    setState(() => _linkCopied = true);
    _copyFeedbackTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _linkCopied = false);
    });
  }

  Future<void> _revokeInvitation(String targetUid) async {
    if (_busy) return;
    final l10n = context.l10n;
    setState(() => _busy = true);
    try {
      await ref
          .read(placeRepositoryProvider)
          .revokeNoteAdministratorInvitation(
            placeId: widget.placeId,
            targetUid: targetUid,
          );
      if (_createdInvitation?.targetUid == targetUid && mounted) {
        setState(() => _createdInvitation = null);
      }
      await _loadAdministratorAccess();
      _snack(l10n.administratorInviteRevoked);
    } catch (error, stack) {
      _reportError('revoke administrator invitation', error, stack);
      _snack(l10n.inviteRevokeFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _removeAdministrator(String targetUid) async {
    if (_busy) return;
    final l10n = context.l10n;
    setState(() => _busy = true);
    try {
      await ref
          .read(placeRepositoryProvider)
          .removeNoteAdministrator(
            placeId: widget.placeId,
            targetUid: targetUid,
          );
      await _loadAdministratorAccess();
      _snack(l10n.administratorRemoved);
    } catch (error, stack) {
      _reportError('remove administrator', error, stack);
      _snack(l10n.administratorRemoveFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _removeMember(String userId) async {
    final l10n = context.l10n;
    try {
      await ref
          .read(placeRepositoryProvider)
          .revokeNoteAccess(placeId: widget.placeId, userId: userId);
    } catch (error, stack) {
      _reportError('remove password member', error, stack);
      _snack(l10n.memberRemoveFailed);
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _reportError(String operation, Object error, StackTrace stack) {
    developer.log(
      'Could not $operation.',
      name: 'world_notes.note_access',
      error: error,
      stackTrace: stack,
    );
  }

  @override
  void dispose() {
    _copyFeedbackTimer?.cancel();
    _targetUidController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currentUser = ref.watch(authStateProvider).valueOrNull;
    final place = ref.watch(placeProvider(widget.placeId)).valueOrNull;
    final isAdministrator =
        ref
            .watch(noteAdministratorAuthorityProvider(widget.placeId))
            .valueOrNull ??
        false;
    final permissions = place?.permissionsFor(
      uid: currentUser?.id,
      membership: null,
      isAdministrator: isAdministrator,
      readOnly: false,
      now: DateTime.now(),
    );
    final members = ref.watch(noteMembersProvider(widget.placeId));

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: 20 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: ListView(
          shrinkWrap: true,
          children: [
            Text(
              context.l10n.manageAccessAction,
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            Text(
              context.l10n.administratorManageDescription,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _targetUidController,
              enabled: !_busy,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                labelText: context.l10n.targetUserIdLabel,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _busy ? null : _createInvitation,
              icon: const Icon(Icons.person_add_alt_1),
              label: Text(context.l10n.sendAdministratorInvitation),
            ),
            if (_createdInvitation case final invitation?) ...[
              const SizedBox(height: 12),
              SelectableText(
                ref
                    .watch(selectedWorldNavigationProvider)
                    .inviteUrl(invitation.token),
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _copyCreatedLink,
                icon: Icon(_linkCopied ? Icons.check : Icons.copy),
                label: Text(
                  _linkCopied ? context.l10n.copied : context.l10n.copyLink,
                ),
              ),
            ],
            if (_error case final error?) ...[
              const SizedBox(height: 8),
              Text(error, style: TextStyle(color: theme.colorScheme.error)),
            ],
            const Divider(height: 32),
            Text(
              context.l10n.noteAdministratorsTitle,
              style: theme.textTheme.titleMedium,
            ),
            if (_loading)
              const Center(child: CircularProgressIndicator())
            else
              ..._administratorTiles(currentUser?.id),
            const SizedBox(height: 16),
            Text(
              context.l10n.pendingAdministratorInvitationsTitle,
              style: theme.textTheme.titleMedium,
            ),
            ..._pendingInvitationTiles(),
            const Divider(height: 32),
            Text(
              context.l10n.passwordAccessMembersTitle,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              context.l10n.passwordAccessDescription,
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            members.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => Text(context.l10n.commonError(error)),
              data: (values) => values.isEmpty
                  ? Text(context.l10n.noAccessMembers)
                  : Column(
                      children: values
                          .map((member) {
                            final canRemove =
                                permissions?.canRemoveMemberAccess ?? false;
                            return ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: CircleAvatar(
                                child: Text(_initial(member.label)),
                              ),
                              title: Text(member.label),
                              subtitle: Text(context.l10n.unlockedWithPassword),
                              trailing: canRemove
                                  ? IconButton(
                                      tooltip: context.l10n.removeAccess,
                                      onPressed: () =>
                                          _removeMember(member.userId),
                                      icon: const Icon(
                                        Icons.person_remove_outlined,
                                      ),
                                    )
                                  : null,
                            );
                          })
                          .toList(growable: false),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _administratorTiles(String? currentUid) {
    final values = _administratorAccess?.administrators ?? const [];
    return values
        .map((administrator) {
          final canRemove = !administrator.isCreator;
          final subtitle = administrator.isCreator
              ? context.l10n.noteCreatorLabel
              : context.l10n.noteAdministratorLabel;
          return ListTile(
            contentPadding: EdgeInsets.zero,
            leading: CircleAvatar(
              backgroundImage: administrator.photoUrl == null
                  ? null
                  : NetworkImage(administrator.photoUrl!),
              child: administrator.photoUrl == null
                  ? Text(_initial(administrator.label))
                  : null,
            ),
            title: Text(administrator.label),
            subtitle: Text(subtitle),
            trailing: canRemove
                ? IconButton(
                    tooltip: administrator.userId == currentUid
                        ? context.l10n.resignAdministrator
                        : context.l10n.removeAdministrator,
                    onPressed: _busy
                        ? null
                        : () => _removeAdministrator(administrator.userId),
                    icon: const Icon(Icons.remove_moderator_outlined),
                  )
                : null,
          );
        })
        .toList(growable: false);
  }

  List<Widget> _pendingInvitationTiles() {
    final values = _administratorAccess?.pendingInvitations ?? const [];
    if (values.isEmpty) return [Text(context.l10n.noPendingInvitations)];
    return values
        .map((invitation) {
          return ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const CircleAvatar(child: Icon(Icons.schedule)),
            title: Text(invitation.label),
            subtitle: Text(
              invitation.expired
                  ? context.l10n.inviteExpired
                  : context.l10n.invitationPending,
            ),
            trailing: IconButton(
              tooltip: context.l10n.revokeInvitation,
              onPressed: _busy
                  ? null
                  : () => _revokeInvitation(invitation.targetUid),
              icon: const Icon(Icons.link_off),
            ),
          );
        })
        .toList(growable: false);
  }

  String _initial(String value) {
    return value.isEmpty ? '?' : value.characters.first.toUpperCase();
  }
}
