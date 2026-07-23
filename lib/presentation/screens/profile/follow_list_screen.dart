import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../domain/entities/follow_entity.dart';
import '../../../domain/entities/public_profile_entity.dart';
import '../../../l10n/l10n.dart';
import '../../providers/providers.dart';
import '../../widgets/loading_skeleton.dart';

class FollowListScreen extends ConsumerStatefulWidget {
  final String userId;
  final bool followers;

  const FollowListScreen({
    super.key,
    required this.userId,
    required this.followers,
  });

  @override
  ConsumerState<FollowListScreen> createState() => _FollowListScreenState();
}

class _FollowListScreenState extends ConsumerState<FollowListScreen> {
  static const int _pageSize = 20;

  final _scrollController = ScrollController();
  final List<FollowListItem> _items = [];
  Object? _cursor;
  bool _initialLoading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_maybeLoadMore);
    Future.microtask(_loadFirstPage);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadFirstPage() async {
    setState(() {
      _initialLoading = true;
      _error = null;
    });
    try {
      final page = await _loadPage(cursor: null);
      if (!mounted) return;
      setState(() {
        _items
          ..clear()
          ..addAll(page.items);
        _cursor = page.nextCursor;
        _hasMore = page.hasMore;
        _initialLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _initialLoading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore || _cursor == null) return;
    setState(() => _loadingMore = true);
    try {
      final page = await _loadPage(cursor: _cursor);
      if (!mounted) return;
      setState(() {
        _items.addAll(page.items);
        _cursor = page.nextCursor;
        _hasMore = page.hasMore;
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loadingMore = false;
      });
    }
  }

  Future<FollowPage> _loadPage({required Object? cursor}) {
    final repository = ref.read(followRepositoryProvider);
    return widget.followers
        ? repository.listFollowers(
            userId: widget.userId,
            cursor: cursor,
            limit: _pageSize,
          )
        : repository.listFollowing(
            userId: widget.userId,
            cursor: cursor,
            limit: _pageSize,
          );
  }

  void _maybeLoadMore() {
    if (_scrollController.position.extentAfter < 360) {
      _loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final title = widget.followers ? l10n.followers : l10n.following;
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: RefreshIndicator(onRefresh: _loadFirstPage, child: _body(title)),
    );
  }

  Widget _body(String title) {
    if (_initialLoading) {
      return const SkeletonView(child: SkeletonListView());
    }
    if (_error != null && _items.isEmpty) {
      return ListView(
        children: [
          const SizedBox(height: 120),
          Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('Could not load $title: $_error'),
            ),
          ),
        ],
      );
    }
    if (_items.isEmpty) {
      return ListView(
        children: [
          const SizedBox(height: 120),
          _EmptyFollowList(followers: widget.followers),
        ],
      );
    }

    return ListView.separated(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _items.length + (_loadingMore ? 1 : 0),
      separatorBuilder: (_, index) {
        if (index >= _items.length - 1) return const SizedBox.shrink();
        return const Divider(height: 1, indent: 72);
      },
      itemBuilder: (context, index) {
        if (index >= _items.length) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        return _FollowListTile(item: _items[index]);
      },
    );
  }
}

class _FollowListTile extends StatelessWidget {
  final FollowListItem item;

  const _FollowListTile({required this.item});

  @override
  Widget build(BuildContext context) {
    final profile = item.profile;
    return ListTile(
      leading: _ProfileAvatar(profile: profile),
      title: Text(profile.label, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        '${profile.followerCount} followers',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => context.push('/users/${profile.id}'),
    );
  }
}

class _ProfileAvatar extends StatelessWidget {
  final PublicProfile profile;

  const _ProfileAvatar({required this.profile});

  @override
  Widget build(BuildContext context) {
    final photoUrl = profile.photoUrl;
    return CircleAvatar(
      backgroundImage: photoUrl == null
          ? null
          : CachedNetworkImageProvider(photoUrl),
      child: photoUrl == null ? Text(_initial(profile.label)) : null,
    );
  }

  String _initial(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? '?' : trimmed[0].toUpperCase();
  }
}

class _EmptyFollowList extends StatelessWidget {
  final bool followers;

  const _EmptyFollowList({required this.followers});

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
              Icons.people_outline,
              size: 44,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              followers ? context.l10n.noFollowers : context.l10n.noFollowing,
              style: theme.textTheme.titleMedium,
            ),
          ],
        ),
      ),
    );
  }
}
