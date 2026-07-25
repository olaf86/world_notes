import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../config/app_config.dart';
import '../../../domain/policies/note_permissions.dart';
import '../../../l10n/l10n.dart';
import '../../providers/providers.dart';

/// Maintainer-only sheet to manage a private note's access.
class ManageAccessSheet extends ConsumerStatefulWidget {
  final String placeId;
  const ManageAccessSheet({super.key, required this.placeId});

  @override
  ConsumerState<ManageAccessSheet> createState() => _ManageAccessSheetState();
}

class _ManageAccessSheetState extends ConsumerState<ManageAccessSheet> {
  String? _token;
  bool _busy = false;
  bool _loadingInvite = true;
  bool _linkCopied = false;
  String? _inviteLoadError;
  Timer? _copyFeedbackTimer;

  @override
  void initState() {
    super.initState();
    _loadInviteLink();
  }

  Future<void> _loadInviteLink() async {
    try {
      final token = await ref
          .read(placeRepositoryProvider)
          .getInviteLink(widget.placeId);
      if (!mounted) return;
      setState(() {
        _token = token;
        _inviteLoadError = null;
      });
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      setState(() {
        _inviteLoadError = e.message ?? 'Could not check the invite link.';
      });
    } finally {
      if (mounted) setState(() => _loadingInvite = false);
    }
  }

  Future<void> _createLink() async {
    setState(() => _busy = true);
    try {
      final token = await ref
          .read(placeRepositoryProvider)
          .createInviteLink(widget.placeId);
      if (mounted) {
        setState(() {
          _token = token;
          _linkCopied = false;
          _inviteLoadError = null;
        });
      }
    } on FirebaseFunctionsException catch (e) {
      _snack(e.message ?? 'Could not create the link.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _revokeLink() async {
    setState(() => _busy = true);
    try {
      await ref.read(placeRepositoryProvider).revokeInvite(widget.placeId);
      _copyFeedbackTimer?.cancel();
      if (mounted) {
        setState(() {
          _token = null;
          _linkCopied = false;
          _inviteLoadError = null;
        });
      }
      _snack('Invite link revoked.');
    } on FirebaseFunctionsException catch (e) {
      _snack(e.message ?? 'Could not revoke the link.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _removeMember(String userId) async {
    try {
      await ref
          .read(placeRepositoryProvider)
          .revokeNoteAccess(placeId: widget.placeId, userId: userId);
    } on FirebaseFunctionsException catch (e) {
      _snack(e.message ?? 'Could not remove this member.');
    }
  }

  Future<void> _grantMaintainer(String userId) async {
    try {
      await ref
          .read(placeRepositoryProvider)
          .grantNoteMaintainer(placeId: widget.placeId, userId: userId);
      _snack('Maintainer access granted.');
    } on FirebaseFunctionsException catch (e) {
      _snack(e.message ?? 'Could not make this person a maintainer.');
    }
  }

  Future<void> _revokeMaintainer(String userId) async {
    try {
      await ref
          .read(placeRepositoryProvider)
          .revokeNoteMaintainer(placeId: widget.placeId, userId: userId);
      _snack('Maintainer access removed.');
    } on FirebaseFunctionsException catch (e) {
      _snack(e.message ?? 'Could not remove maintainer access.');
    }
  }

  Future<void> _copyLink() async {
    if (_token == null) return;
    await Clipboard.setData(ClipboardData(text: AppConfig.inviteLink(_token!)));
    if (!mounted) return;

    _copyFeedbackTimer?.cancel();
    setState(() => _linkCopied = true);
    _copyFeedbackTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _linkCopied = false);
    });
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void dispose() {
    _copyFeedbackTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currentUser = ref.watch(authStateProvider).valueOrNull;
    final place = ref.watch(placeProvider(widget.placeId)).valueOrNull;
    final permissions = place?.permissionsFor(
      uid: currentUser?.id,
      membership: null,
      readOnly: false,
      now: DateTime.now(),
    );
    final membersAsync = ref.watch(noteMembersProvider(widget.placeId));

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: 20 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Manage access', style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              'Share the invite link so people can read and post without the '
              'password. Maintainers can create invite links; only the '
              'creator can revoke links or change maintainers.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),

            // ── Invite link ────────────────────────────────────────────
            if (_loadingInvite)
              FilledButton.icon(
                onPressed: null,
                icon: const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                label: const Text('Checking invite link'),
              )
            else if (_token == null) ...[
              if (_inviteLoadError != null) ...[
                Text(
                  _inviteLoadError!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
                const SizedBox(height: 8),
              ],
              FilledButton.icon(
                onPressed: _busy ? null : _createLink,
                icon: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.link),
                label: const Text('Create invite link'),
              ),
            ] else ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SelectableText(
                  AppConfig.inviteLink(_token!),
                  style: theme.textTheme.bodySmall,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _copyLink,
                      icon: Icon(
                        _linkCopied ? Icons.check : Icons.copy,
                        size: 18,
                      ),
                      label: Text(_linkCopied ? 'Copied' : 'Copy link'),
                    ),
                  ),
                  if (permissions?.canRevokeInviteLink ?? false) ...[
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _revokeLink,
                      icon: const Icon(Icons.link_off, size: 18),
                      label: const Text('Revoke'),
                    ),
                  ],
                ],
              ),
            ],

            const Divider(height: 32),

            Text('People with access', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Flexible(
              child: membersAsync.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (e, _) => Text('Error: $e'),
                data: (members) => members.isEmpty
                    ? Text(
                        context.l10n.noAccessMembers,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      )
                    : ListView.builder(
                        shrinkWrap: true,
                        itemCount: members.length,
                        itemBuilder: (context, i) {
                          final m = members[i];
                          final memberPermissions =
                              place == null || permissions == null
                              ? const NoteMemberPermissions(
                                  canRemoveAccess: false,
                                  canPromoteToMaintainer: false,
                                  canDemoteMaintainer: false,
                                )
                              : m.permissionsFor(
                                  place: place,
                                  actor: permissions,
                                );
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: CircleAvatar(
                              child: Text(
                                m.label.isNotEmpty
                                    ? m.label[0].toUpperCase()
                                    : '?',
                              ),
                            ),
                            title: Text(
                              m.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              [
                                if (m.isMaintainer) 'Maintainer',
                                if (m.invited)
                                  'Invited'
                                else
                                  'Unlocked with password',
                              ].join(' • '),
                            ),
                            trailing: memberPermissions.hasActions
                                ? PopupMenuButton<String>(
                                    tooltip: 'Member options',
                                    onSelected: (value) {
                                      if (value == 'grantMaintainer') {
                                        _grantMaintainer(m.userId);
                                      }
                                      if (value == 'revokeMaintainer') {
                                        _revokeMaintainer(m.userId);
                                      }
                                      if (value == 'removeAccess') {
                                        _removeMember(m.userId);
                                      }
                                    },
                                    itemBuilder: (context) => [
                                      if (memberPermissions.canDemoteMaintainer)
                                        const PopupMenuItem(
                                          value: 'revokeMaintainer',
                                          child: ListTile(
                                            leading: Icon(
                                              Icons
                                                  .admin_panel_settings_outlined,
                                            ),
                                            title: Text('Remove maintainer'),
                                            contentPadding: EdgeInsets.zero,
                                          ),
                                        ),
                                      if (memberPermissions
                                          .canPromoteToMaintainer)
                                        const PopupMenuItem(
                                          value: 'grantMaintainer',
                                          child: ListTile(
                                            leading: Icon(
                                              Icons
                                                  .admin_panel_settings_outlined,
                                            ),
                                            title: Text('Make maintainer'),
                                            contentPadding: EdgeInsets.zero,
                                          ),
                                        ),
                                      if (memberPermissions
                                          .canRemoveAccess) ...[
                                        const PopupMenuDivider(),
                                        const PopupMenuItem(
                                          value: 'removeAccess',
                                          child: ListTile(
                                            leading: Icon(
                                              Icons.person_remove_outlined,
                                            ),
                                            title: Text('Remove access'),
                                            contentPadding: EdgeInsets.zero,
                                          ),
                                        ),
                                      ],
                                    ],
                                  )
                                : null,
                          );
                        },
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
