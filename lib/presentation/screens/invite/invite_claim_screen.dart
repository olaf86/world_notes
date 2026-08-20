import 'dart:developer' as developer;

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../config/world_catalog.dart';
import '../../../config/world_navigation.dart';
import '../../../domain/entities/note_administrator_entity.dart';
import '../../../l10n/l10n.dart';
import '../../providers/providers.dart';

/// Previews and explicitly accepts a target-bound administrator invitation.
class InviteClaimScreen extends ConsumerStatefulWidget {
  const InviteClaimScreen({
    super.key,
    required this.worldId,
    required this.token,
  });

  final WorldId worldId;
  final String token;

  @override
  ConsumerState<InviteClaimScreen> createState() => _InviteClaimScreenState();
}

class _InviteClaimScreenState extends ConsumerState<InviteClaimScreen> {
  NoteAdministratorInvitationPreview? _preview;
  bool _loading = false;
  bool _accepting = false;
  bool _switchAfterAcceptance = false;
  String? _acceptedPlaceId;
  String? _error;

  Future<void> _loadPreview() async {
    if (_loading || _preview != null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final preview = await ref
          .read(worldPlaceRepositoryProvider(widget.worldId))
          .previewNoteAdministratorInvitation(widget.token);
      if (mounted) setState(() => _preview = preview);
    } on FirebaseFunctionsException catch (error, stack) {
      _reportError('load invitation preview', error, stack);
      if (mounted) setState(() => _error = _errorMessage(error));
    } catch (error, stack) {
      _reportError('load invitation preview', error, stack);
      if (mounted) setState(() => _error = context.l10n.inviteLoadFailed);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _accept() async {
    final preview = _preview;
    if (_accepting || preview == null || !preview.canAccept) return;
    setState(() {
      _accepting = true;
      _error = null;
    });
    try {
      final placeId = await ref
          .read(worldPlaceRepositoryProvider(widget.worldId))
          .acceptNoteAdministratorInvitation(widget.token);
      if (!mounted) return;
      setState(() => _acceptedPlaceId = placeId);
      if (_switchAfterAcceptance) await _switchAndOpen(placeId);
    } on FirebaseFunctionsException catch (error, stack) {
      _reportError('accept administrator invitation', error, stack);
      if (mounted) setState(() => _error = _errorMessage(error));
    } catch (error, stack) {
      _reportError('accept administrator invitation', error, stack);
      if (mounted) setState(() => _error = context.l10n.inviteAcceptFailed);
    } finally {
      if (mounted) setState(() => _accepting = false);
    }
  }

  Future<void> _switchAndOpen(String placeId) async {
    try {
      await ref
          .read(selectedWorldProvider.notifier)
          .selectWorld(widget.worldId);
      if (mounted) {
        context.go(WorldNavigation(widget.worldId).note(placeId));
      }
    } catch (error, stack) {
      _reportError('switch to invitation world', error, stack);
      if (mounted) setState(() => _error = context.l10n.worldStillPreparing);
    }
  }

  String _errorMessage(FirebaseFunctionsException error) =>
      switch (error.code) {
        'not-found' => context.l10n.inviteInvalid,
        'deadline-exceeded' => context.l10n.inviteExpired,
        'failed-precondition'
            when error.details is Map &&
                (error.details as Map)['reason'] == 'world-not-ready' =>
          context.l10n.worldStillPreparing,
        'unavailable' => context.l10n.networkErrorTryAgain,
        _ => context.l10n.inviteAcceptFailed,
      };

  void _reportError(String operation, Object error, StackTrace stack) {
    developer.log(
      'Could not $operation.',
      name: 'world_notes.administrator_invitation',
      error: error,
      stackTrace: stack,
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authStateProvider);
    final user = auth.valueOrNull;
    if (user != null && !_loading && _preview == null && _error == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadPreview());
    }

    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.administratorInvitationTitle)),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: _body(auth, user),
          ),
        ),
      ),
    );
  }

  Widget _body(AsyncValue<dynamic> auth, Object? user) {
    if (auth.isLoading) return const CircularProgressIndicator();
    if (user == null) {
      return _MessagePanel(
        icon: Icons.lock_outline,
        message: context.l10n.inviteSignInPrompt,
        action: FilledButton(
          onPressed: () => context.push('/auth/sign-in'),
          child: Text(context.l10n.signIn),
        ),
      );
    }
    if (_loading) return const CircularProgressIndicator();
    if (_acceptedPlaceId case final placeId?) {
      return _MessagePanel(
        icon: Icons.admin_panel_settings,
        message: context.l10n.administratorInvitationAccepted,
        action: FilledButton(
          onPressed: () => _switchAndOpen(placeId),
          child: Text(context.l10n.switchWorldAndOpenNote),
        ),
      );
    }
    if (_error case final error?) {
      return _MessagePanel(
        icon: Icons.link_off,
        message: error,
        action: TextButton(
          onPressed: () => context.go('/map'),
          child: Text(context.l10n.goToMap),
        ),
      );
    }
    final preview = _preview;
    if (preview == null) return const CircularProgressIndicator();
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 520),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(Icons.admin_panel_settings_outlined, size: 64),
          const SizedBox(height: 20),
          Text(
            preview.title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 12),
          Text(
            context.l10n.administratorInvitationExplanation,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          if (!preview.worldReady)
            Text(
              context.l10n.worldStillPreparing,
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            )
          else if (preview.status != NoteAdministratorInvitationStatus.pending)
            Text(
              preview.status == NoteAdministratorInvitationStatus.expired
                  ? context.l10n.inviteExpired
                  : context.l10n.inviteInvalid,
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          CheckboxListTile(
            value: _switchAfterAcceptance,
            onChanged: preview.canAccept && !_accepting
                ? (value) =>
                      setState(() => _switchAfterAcceptance = value ?? false)
                : null,
            title: Text(context.l10n.switchWorldAfterAcceptance),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: preview.canAccept && !_accepting ? _accept : null,
            child: _accepting
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(context.l10n.acceptAdministratorInvitation),
          ),
        ],
      ),
    );
  }
}

class _MessagePanel extends StatelessWidget {
  const _MessagePanel({
    required this.icon,
    required this.message,
    required this.action,
  });

  final IconData icon;
  final String message;
  final Widget action;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 56),
      const SizedBox(height: 16),
      Text(message, textAlign: TextAlign.center),
      const SizedBox(height: 16),
      action,
    ],
  );
}
