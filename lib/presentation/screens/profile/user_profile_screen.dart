import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../domain/entities/public_profile_entity.dart';
import '../../../l10n/l10n.dart';
import '../../providers/providers.dart';
import '../../utils/user_block_actions.dart';
import '../../widgets/loading_skeleton.dart';

class UserProfileScreen extends ConsumerStatefulWidget {
  final String userId;

  const UserProfileScreen({super.key, required this.userId});

  @override
  ConsumerState<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends ConsumerState<UserProfileScreen> {
  bool _busy = false;
  bool? _optimisticFollowing;

  Future<void> _setFollowing(bool following) async {
    if (_busy) return;
    final failureMessage = context.l10n.followUpdateFailed;
    setState(() => _busy = true);
    try {
      await ref
          .read(followRepositoryProvider)
          .setFollowing(targetUserId: widget.userId, following: following);
      if (mounted) setState(() => _optimisticFollowing = following);
      ref.invalidate(mapPinsProvider);
    } on FirebaseFunctionsException {
      _snack(failureMessage);
    } catch (_) {
      _snack(failureMessage);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setBlocked({
    required bool blocked,
    required String targetName,
  }) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await confirmAndSetUserBlocked(
        context: context,
        ref: ref,
        targetUserId: widget.userId,
        targetName: targetName,
        blocked: blocked,
      );
      if (blocked && mounted) {
        setState(() => _optimisticFollowing = false);
      }
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
    final isBlocked = ref.watch(isUserBlockedProvider(widget.userId));

    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.profileTitle)),
      body: profileAsync.when(
        loading: () => const _ProfileSkeleton(),
        error: (e, _) => Center(child: Text(context.l10n.profileLoadFailed(e))),
        data: (profile) {
          if (profile == null) {
            return Center(child: Text(context.l10n.profileNotFound));
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _ProfileHeader(profile: profile),
              const SizedBox(height: 20),
              _SocialCounts(profile: profile),
              if (!isOwnProfile) ...[
                const SizedBox(height: 20),
                isBlocked.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (error, _) => OutlinedButton.icon(
                    onPressed: null,
                    icon: const Icon(Icons.error_outline),
                    label: Text(context.l10n.updateUserBlockFailed(error)),
                  ),
                  data: (blocked) => blocked
                      ? OutlinedButton.icon(
                          onPressed: _busy
                              ? null
                              : () => _setBlocked(
                                  blocked: false,
                                  targetName: profile.label,
                                ),
                          icon: const Icon(Icons.block_outlined),
                          label: Text(context.l10n.unblockUserAction),
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            isFollowing.when(
                              loading: () => const Center(
                                child: CircularProgressIndicator(),
                              ),
                              error: (e, _) => OutlinedButton.icon(
                                onPressed: null,
                                icon: const Icon(Icons.error_outline),
                                label: Text(context.l10n.followUnavailable(e)),
                              ),
                              data: (following) => FilledButton.icon(
                                onPressed: _busy
                                    ? null
                                    : () => _setFollowing(
                                        !(_optimisticFollowing ?? following),
                                      ),
                                icon: Icon(
                                  (_optimisticFollowing ?? following)
                                      ? Icons.person_remove_outlined
                                      : Icons.person_add_alt_1_outlined,
                                ),
                                label: Text(
                                  (_optimisticFollowing ?? following)
                                      ? context.l10n.unfollowAction
                                      : context.l10n.followAction,
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextButton.icon(
                              onPressed: _busy
                                  ? null
                                  : () => _setBlocked(
                                      blocked: true,
                                      targetName: profile.label,
                                    ),
                              style: TextButton.styleFrom(
                                foregroundColor: Theme.of(
                                  context,
                                ).colorScheme.error,
                              ),
                              icon: const Icon(Icons.block_outlined),
                              label: Text(context.l10n.blockUserAction),
                            ),
                          ],
                        ),
                ),
              ],
              const SizedBox(height: 24),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.people_outline),
                title: Text(context.l10n.followers),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/users/${widget.userId}/followers'),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.person_search_outlined),
                title: Text(context.l10n.following),
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

class _ProfileSkeleton extends StatelessWidget {
  const _ProfileSkeleton();

  @override
  Widget build(BuildContext context) {
    return const SkeletonView(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          children: [
            SkeletonBox(
              width: 96,
              height: 96,
              borderRadius: BorderRadius.all(Radius.circular(48)),
            ),
            SizedBox(height: 16),
            SkeletonBox(width: 180, height: 22),
            SizedBox(height: 12),
            SkeletonBox(width: 240, height: 14),
            SizedBox(height: 28),
            SkeletonBox(width: double.infinity, height: 52),
            SizedBox(height: 24),
            Expanded(child: SkeletonListView(itemCount: 3)),
          ],
        ),
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
        _Count(label: context.l10n.followers, value: profile.followerCount),
        const SizedBox(width: 32),
        _Count(label: context.l10n.following, value: profile.followingCount),
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
