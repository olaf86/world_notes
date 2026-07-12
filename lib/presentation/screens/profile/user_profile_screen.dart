import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../domain/entities/public_profile_entity.dart';
import '../../providers/providers.dart';

class UserProfileScreen extends ConsumerStatefulWidget {
  final String userId;

  const UserProfileScreen({super.key, required this.userId});

  @override
  ConsumerState<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends ConsumerState<UserProfileScreen> {
  bool _busy = false;

  Future<void> _setFollowing(bool following) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(followRepositoryProvider)
          .setFollowing(targetUserId: widget.userId, following: following);
      ref.invalidate(mapPinsProvider);
    } on FirebaseFunctionsException catch (e) {
      _snack(e.message ?? 'Could not update follow state.');
    } catch (e) {
      _snack(e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(publicProfileProvider(widget.userId));
    final currentUser = ref.watch(authStateProvider).valueOrNull;
    final isOwnProfile = currentUser?.id == widget.userId;
    final isFollowing = ref.watch(isFollowingUserProvider(widget.userId));

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: profileAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Could not load profile: $e')),
        data: (profile) {
          if (profile == null) {
            return const Center(child: Text('Profile not found.'));
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _ProfileHeader(profile: profile),
              const SizedBox(height: 20),
              _SocialCounts(profile: profile),
              if (!isOwnProfile) ...[
                const SizedBox(height: 20),
                isFollowing.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, _) => OutlinedButton.icon(
                    onPressed: null,
                    icon: const Icon(Icons.error_outline),
                    label: Text('Follow unavailable: $e'),
                  ),
                  data: (following) => FilledButton.icon(
                    onPressed: _busy ? null : () => _setFollowing(!following),
                    icon: Icon(
                      following
                          ? Icons.person_remove_outlined
                          : Icons.person_add_alt_1_outlined,
                    ),
                    label: Text(following ? 'Unfollow' : 'Follow'),
                  ),
                ),
              ],
              const SizedBox(height: 24),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.people_outline),
                title: const Text('Followers'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/users/${widget.userId}/followers'),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.person_search_outlined),
                title: const Text('Following'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/users/${widget.userId}/following'),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  final PublicProfile profile;

  const _ProfileHeader({required this.profile});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        CircleAvatar(
          radius: 48,
          backgroundImage: profile.photoUrl == null
              ? null
              : CachedNetworkImageProvider(profile.photoUrl!),
          child: profile.photoUrl == null
              ? Text(
                  _initial(profile.label),
                  style: const TextStyle(fontSize: 32),
                )
              : null,
        ),
        const SizedBox(height: 12),
        Text(
          profile.label,
          textAlign: TextAlign.center,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  String _initial(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? '?' : trimmed[0].toUpperCase();
  }
}

class _SocialCounts extends StatelessWidget {
  final PublicProfile profile;

  const _SocialCounts({required this.profile});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _Count(label: 'Followers', value: profile.followerCount),
        const SizedBox(width: 32),
        _Count(label: 'Following', value: profile.followingCount),
      ],
    );
  }
}

class _Count extends StatelessWidget {
  final String label;
  final int value;

  const _Count({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Text(
          '$value',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
