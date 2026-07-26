import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../domain/entities/user_block_entity.dart';
import '../../../l10n/l10n.dart';
import '../../providers/providers.dart';
import '../../utils/user_block_actions.dart';
import '../../widgets/loading_skeleton.dart';

class BlockedUsersScreen extends ConsumerWidget {
  const BlockedUsersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final blockedUsers = ref.watch(blockedUsersProvider);
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.blockedUsersTitle)),
      body: blockedUsers.when(
        loading: () => const SkeletonView(child: SkeletonListView()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(context.l10n.blockedUsersLoadFailed(error)),
          ),
        ),
        data: (blocks) => blocks.isEmpty
            ? _EmptyBlockedUsers(label: context.l10n.noBlockedUsers)
            : ListView.separated(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: blocks.length,
                separatorBuilder: (_, _) =>
                    const Divider(height: 1, indent: 72),
                itemBuilder: (context, index) => _BlockedUserTile(
                  block: blocks[index],
                  onUnblock: () => confirmAndSetUserBlocked(
                    context: context,
                    ref: ref,
                    targetUserId: blocks[index].userId,
                    targetName: blocks[index].profile.label,
                    blocked: false,
                  ),
                ),
              ),
      ),
    );
  }
}

class _BlockedUserTile extends StatelessWidget {
  final UserBlock block;
  final VoidCallback onUnblock;

  const _BlockedUserTile({required this.block, required this.onUnblock});

  @override
  Widget build(BuildContext context) {
    final profile = block.profile;
    final photoUrl = profile.photoUrl;
    return ListTile(
      leading: CircleAvatar(
        backgroundImage: photoUrl == null
            ? null
            : CachedNetworkImageProvider(photoUrl),
        child: photoUrl == null ? Text(_initial(profile.label)) : null,
      ),
      title: Text(profile.label, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: TextButton(
        onPressed: onUnblock,
        child: Text(context.l10n.unblockUserAction),
      ),
      onTap: () => context.push('/users/${profile.id}'),
    );
  }

  String _initial(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? '?' : trimmed[0].toUpperCase();
  }
}

class _EmptyBlockedUsers extends StatelessWidget {
  final String label;

  const _EmptyBlockedUsers({required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.block_outlined,
              size: 44,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(label, style: theme.textTheme.titleMedium),
          ],
        ),
      ),
    );
  }
}
