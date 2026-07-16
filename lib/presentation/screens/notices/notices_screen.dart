import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../domain/entities/notice_entity.dart';
import '../../providers/providers.dart';
import '../../widgets/loading_skeleton.dart';

class NoticesScreen extends ConsumerWidget {
  const NoticesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final noticesAsync = ref.watch(noticesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: noticesAsync.when(
        loading: () => const SkeletonView(child: SkeletonListView()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Could not load notifications.\n$error'),
          ),
        ),
        data: (notices) => notices.isEmpty
            ? const _EmptyNotices()
            : RefreshIndicator(
                onRefresh: () async {
                  ref.invalidate(noticesProvider);
                  await ref.read(noticesProvider.future);
                },
                child: ListView.separated(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemBuilder: (context, index) {
                    final notice = notices[index];
                    return _NoticeTile(
                      notice: notice,
                      onTap: () => _openNotice(context, ref, notice),
                    );
                  },
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemCount: notices.length,
                ),
              ),
      ),
    );
  }

  Future<void> _openNotice(
    BuildContext context,
    WidgetRef ref,
    NoticeEntity notice,
  ) async {
    final user = ref.read(authStateProvider).valueOrNull;
    if (user != null && notice.isUnread) {
      // Reading a notice must not delay its destination. The live notices
      // stream updates the badge when this best-effort write completes.
      unawaited(
        ref
            .read(noticeRepositoryProvider)
            .markRead(userId: user.id, noticeId: notice.id)
            .onError((error, stack) {
              debugPrint('Could not mark notice ${notice.id} read: $error');
            }),
      );
    }
    if (notice.category == 'social' && notice.sourceId?.isNotEmpty == true) {
      await context.push<void>('/users/${notice.sourceId}');
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: Icon(
          _iconFor(notice),
          color: _colorFor(Theme.of(dialogContext), notice),
        ),
        title: Text(notice.title),
        content: SingleChildScrollView(child: Text(notice.body)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

class _EmptyNotices extends StatelessWidget {
  const _EmptyNotices();

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
              Icons.notifications_none_outlined,
              size: 48,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              'No notifications yet.',
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NoticeTile extends StatelessWidget {
  final NoticeEntity notice;
  final VoidCallback onTap;

  const _NoticeTile({required this.notice, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final createdAt = DateFormat(
      DateTime.now().difference(notice.createdAt).inDays >= 1
          ? 'MMM d, HH:mm'
          : 'HH:mm',
    ).format(notice.createdAt.toLocal());

    return ListTile(
      leading: Stack(
        clipBehavior: Clip.none,
        children: [
          Icon(_iconFor(notice), color: _colorFor(theme, notice)),
          if (notice.isUnread)
            Positioned(
              right: -1,
              top: -1,
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary,
                  shape: BoxShape.circle,
                ),
              ),
            ),
        ],
      ),
      title: Text(
        notice.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.titleSmall?.copyWith(
          fontWeight: notice.isUnread ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
      subtitle: Text(notice.body, maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: Text(
        createdAt,
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      onTap: onTap,
    );
  }
}

IconData _iconFor(NoticeEntity notice) {
  if (notice.isCritical) return Icons.priority_high_rounded;
  if (notice.isWarning) return Icons.warning_amber_rounded;
  return switch (notice.category) {
    'social' => Icons.person_add_alt_1_outlined,
    'developer' => Icons.campaign_outlined,
    'report' => Icons.flag_outlined,
    'ban' => Icons.block_outlined,
    _ => Icons.notifications_outlined,
  };
}

Color _colorFor(ThemeData theme, NoticeEntity notice) {
  if (notice.isCritical) return theme.colorScheme.error;
  if (notice.isWarning) return theme.colorScheme.tertiary;
  return theme.colorScheme.primary;
}
