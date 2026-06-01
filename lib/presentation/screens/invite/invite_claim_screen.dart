import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers/providers.dart';

/// Handles invite deep links (`/i/:token`). If signed in, it redeems the token
/// and forwards to the note; otherwise it asks the user to sign in first.
class InviteClaimScreen extends ConsumerStatefulWidget {
  final String token;
  const InviteClaimScreen({super.key, required this.token});

  @override
  ConsumerState<InviteClaimScreen> createState() => _InviteClaimScreenState();
}

class _InviteClaimScreenState extends ConsumerState<InviteClaimScreen> {
  bool _started = false;
  String? _error;

  Future<void> _claim() async {
    if (_started) return;
    _started = true;
    try {
      final placeId =
          await ref.read(placeRepositoryProvider).claimInvite(widget.token);
      if (mounted) {
        context.pushReplacement('/note/$placeId');
      }
    } on FirebaseFunctionsException catch (e) {
      setState(() {
        _error = switch (e.code) {
          'not-found' =>
            'This invite link is invalid or has been revoked.',
          'unavailable' || 'deadline-exceeded' =>
            'Network error. Check your connection and try again.',
          _ => e.message ?? 'Could not accept this invitation.',
        };
      });
    } catch (_) {
      setState(() => _error = 'Could not accept this invitation.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final authAsync = ref.watch(authStateProvider);
    final user = authAsync.valueOrNull;

    // Once signed in, redeem exactly once.
    if (user != null && !_started && _error == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _claim());
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Invitation')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: _buildBody(theme, authAsync, user),
        ),
      ),
    );
  }

  Widget _buildBody(
    ThemeData theme,
    AsyncValue<dynamic> authAsync,
    Object? user,
  ) {
    if (_error != null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.link_off, size: 56, color: theme.colorScheme.error),
          const SizedBox(height: 16),
          Text(_error!, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          TextButton(
            onPressed: () => context.go('/map'),
            child: const Text('Go to map'),
          ),
        ],
      );
    }

    if (authAsync.isLoading) {
      return const CircularProgressIndicator();
    }

    if (user == null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.lock_outline, size: 56, color: theme.colorScheme.outline),
          const SizedBox(height: 16),
          Text(
            'Sign in to accept this invitation, then open the link again.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => context.push('/auth/sign-in'),
            child: const Text('Sign in'),
          ),
        ],
      );
    }

    // Signed in → claiming in progress.
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: const [
        CircularProgressIndicator(),
        SizedBox(height: 16),
        Text('Accepting invitation…'),
      ],
    );
  }
}
