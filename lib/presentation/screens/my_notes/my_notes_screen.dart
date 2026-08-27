import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../config/world_navigation.dart';
import '../../../core/utils/place_icon.dart';
import '../../../domain/entities/note_list_sort.dart';
import '../../../domain/entities/place_entity.dart';
import '../../../domain/policies/note_permissions.dart';
import '../../../l10n/l10n.dart';
import '../../../l10n/localized_formatters.dart';
import '../../providers/providers.dart';
import '../../widgets/app_alert_dialog.dart';
import '../../widgets/loading_skeleton.dart';
import '../../widgets/my_notes_notification_controls.dart';
import '../../widgets/note/note_list_card.dart';
import '../../widgets/note/note_sort_button.dart';
import '../../widgets/note/user_avatar_badge.dart';
import '../note/note_creation_screen.dart';

class MyNotesScreen extends ConsumerWidget {
  const MyNotesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Semantics(
      identifier: 'screen-my-notes',
      child: const DefaultTabController(
        length: 2,
        child: Scaffold(
          appBar: _NotesAppBar(),
          body: TabBarView(
            children: [_MyNotesListView(), _ArchivedNotesListView()],
          ),
        ),
      ),
    );
  }
}

class _NotesAppBar extends StatelessWidget implements PreferredSizeWidget {
  const _NotesAppBar();

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight + 48);

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AppBar(
      title: Text(l10n.myNotesTitle),
      actions: const [MyNotesNotificationIconButton()],
      bottom: TabBar(
        tabs: [
          Tab(text: l10n.myNotesTab),
          Tab(text: l10n.archivedNotesTab),
        ],
      ),
    );
  }
}

class _MyNotesListView extends ConsumerWidget {
  const _MyNotesListView();

  Future<void> _archivePlace(
    BuildContext context,
    WidgetRef ref,
    PlaceEntity place,
  ) async {
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AppAlertDialog(
        title: Text(l10n.archiveNoteTitle),
        content: Text(l10n.archiveNoteMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(l10n.archiveAction),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    try {
      await ref.read(placeRepositoryProvider).archivePlace(place.id);
      ref.invalidate(archivedMyPlacesCountProvider);
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.archiveFailed(error))));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final placesAsync = ref.watch(myPlacesProvider);
    final noteLimit = ref.watch(noteLimitProvider);
    final currentUser = ref.watch(authStateProvider).valueOrNull;
    final sort = ref.watch(myNotesSortProvider);

    return Column(
      children: [
        _NoteLimitSummary(
          currentCount: placesAsync.valueOrNull?.length ?? 0,
          limit: noteLimit,
          sort: sort,
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(myPlacesProvider);
              await ref.read(myPlacesProvider.future);
            },
            child: placesAsync.when(
              loading: () => const SkeletonView(child: SkeletonListView()),
              error: (e, _) => _ScrollableStatusView(
                child: Center(child: Text(context.l10n.commonError(e))),
              ),
              data: (places) {
                if (places.isEmpty) {
                  return const _ScrollableStatusView(
                    child: _EmptyMyNotesView(),
                  );
                }

                final sorted = _sortPlaces(places, sort: sort);

                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
                  physics: const AlwaysScrollableScrollPhysics(),
                  itemCount: sorted.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final place = sorted[index];
                    final permissions = place.permissionsFor(
                      uid: currentUser?.id,
                      membership: null,
                      isAdministrator: place.createdByUserId != currentUser?.id,
                      readOnly: true,
                      now: DateTime.now(),
                    );
                    return _MyNoteCard(
                      place: place,
                      navigation: ref.watch(selectedWorldNavigationProvider),
                      onArchive: permissions.canArchive
                          ? () => _archivePlace(context, ref, place)
                          : null,
                    );
                  },
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _ArchivedNotesListView extends ConsumerStatefulWidget {
  const _ArchivedNotesListView();

  @override
  ConsumerState<_ArchivedNotesListView> createState() =>
      _ArchivedNotesListViewState();
}

class _ArchivedNotesListViewState
    extends ConsumerState<_ArchivedNotesListView> {
  static const _pageSize = 50;

  final List<PlaceEntity> _places = [];
  Object? _cursor;
  bool _initialLoading = true;
  bool _loadingMore = false;
  bool _hasMore = false;
  String? _error;
  int _requestGeneration = 0;

  @override
  void initState() {
    super.initState();
    Future.microtask(_loadFirstPage);
  }

  Future<void> _loadFirstPage() async {
    final requestGeneration = ++_requestGeneration;
    final user = ref.read(authStateProvider).valueOrNull;
    final sort = ref.read(archivedMyNotesSortProvider);
    setState(() {
      _initialLoading = true;
      _loadingMore = false;
      _error = null;
      _places.clear();
      _cursor = null;
      _hasMore = false;
    });
    if (user == null) {
      if (!mounted || requestGeneration != _requestGeneration) return;
      setState(() {
        _places.clear();
        _cursor = null;
        _hasMore = false;
        _initialLoading = false;
      });
      return;
    }

    try {
      final page = await ref
          .read(placeRepositoryProvider)
          .listArchivedMyPlaces(userId: user.id, sort: sort, limit: _pageSize);
      if (!mounted || requestGeneration != _requestGeneration) return;
      setState(() {
        _places
          ..clear()
          ..addAll(page.places);
        _cursor = page.nextCursor;
        _hasMore = page.hasMore;
        _initialLoading = false;
      });
    } catch (error) {
      if (!mounted || requestGeneration != _requestGeneration) return;
      setState(() {
        _error = error.toString();
        _initialLoading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore || _cursor == null) return;
    final user = ref.read(authStateProvider).valueOrNull;
    if (user == null) return;

    final requestGeneration = _requestGeneration;
    final sort = ref.read(archivedMyNotesSortProvider);
    setState(() {
      _loadingMore = true;
      _error = null;
    });
    try {
      final page = await ref
          .read(placeRepositoryProvider)
          .listArchivedMyPlaces(
            userId: user.id,
            sort: sort,
            cursor: _cursor,
            limit: _pageSize,
          );
      if (!mounted || requestGeneration != _requestGeneration) return;
      setState(() {
        _places.addAll(page.places);
        _cursor = page.nextCursor;
        _hasMore = page.hasMore;
        _loadingMore = false;
      });
    } catch (error) {
      if (!mounted || requestGeneration != _requestGeneration) return;
      setState(() {
        _error = error.toString();
        _loadingMore = false;
      });
    }
  }

  Future<void> _refresh() async {
    ref.invalidate(archivedMyPlacesCountProvider);
    await Future.wait([
      _loadFirstPage(),
      ref.read(archivedMyPlacesCountProvider.future),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<NoteListSort>(archivedMyNotesSortProvider, (previous, next) {
      if (previous != next) _loadFirstPage();
    });
    ref.listen(authStateProvider, (previous, next) {
      if (previous?.valueOrNull?.id != next.valueOrNull?.id) {
        _loadFirstPage();
      }
    });

    final countAsync = ref.watch(archivedMyPlacesCountProvider);
    final sort = ref.watch(archivedMyNotesSortProvider);

    return Column(
      children: [
        _ArchivedNotesSummary(
          count: countAsync.valueOrNull,
          isLoading: countAsync.isLoading,
          sort: sort,
        ),
        Expanded(
          child: RefreshIndicator(onRefresh: _refresh, child: _buildList()),
        ),
      ],
    );
  }

  Widget _buildList() {
    if (_initialLoading) {
      return const SkeletonView(child: SkeletonListView());
    }
    if (_error != null && _places.isEmpty) {
      return _ScrollableStatusView(
        child: Center(child: Text(context.l10n.commonError(_error!))),
      );
    }
    if (_places.isEmpty) {
      return const _ScrollableStatusView(child: _EmptyArchivedNotesView());
    }

    final showsFooter = _hasMore || _loadingMore || _error != null;
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: _places.length + (showsFooter ? 1 : 0),
      separatorBuilder: (context, index) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        if (index == _places.length) return _loadMoreFooter();
        final place = _places[index];
        return _MyNoteCard(
          place: place,
          navigation: ref.read(selectedWorldNavigationProvider),
          onCreateFromArchive: () => context.push(
            ref.read(selectedWorldNavigationProvider).noteCreation,
            extra: NoteCreationDraft.fromPlace(place),
          ),
        );
      },
    );
  }

  Widget _loadMoreFooter() {
    final l10n = context.l10n;
    if (_loadingMore) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return Center(
      child: TextButton.icon(
        onPressed: _loadMore,
        icon: const Icon(Icons.expand_more),
        label: Text(_error == null ? l10n.loadMore : l10n.retryLoadMore),
      ),
    );
  }
}

List<PlaceEntity> _sortPlaces(
  Iterable<PlaceEntity> places, {
  required NoteListSort sort,
}) {
  return sortNoteList(
    places,
    sort: sort,
    createdAt: (place) => place.createdAt,
    lastActivityAt: (place) => place.lastMessageAt ?? place.createdAt,
    archivedAt: (place) => place.archivedAt,
    expiresAt: (place) => place.expiresAt,
    likeCount: (place) => place.likeCount,
    id: (place) => place.id,
  );
}

class _NoteLimitSummary extends StatelessWidget {
  final int currentCount;
  final int limit;
  final NoteListSort sort;

  const _NoteLimitSummary({
    required this.currentCount,
    required this.limit,
    required this.sort,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final l10n = context.l10n;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Icon(Icons.note_alt_outlined, size: 18, color: colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    l10n.createdNotes,
                    style: theme.textTheme.bodyMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '$currentCount / $limit',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: NoteSortChip(
                selected: sort,
                provider: myNotesSortProvider,
                options: const [
                  NoteListSort.lastActivity,
                  NoteListSort.newest,
                  NoteListSort.expiresSoonest,
                ],
                semanticIdentifier: 'action-sort-my-notes',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ArchivedNotesSummary extends StatelessWidget {
  final int? count;
  final bool isLoading;
  final NoteListSort sort;

  const _ArchivedNotesSummary({
    required this.count,
    required this.isLoading,
    required this.sort,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final l10n = context.l10n;

    return Semantics(
      identifier: 'archived-notes-count',
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Icon(Icons.archive_outlined, size: 18, color: colorScheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      l10n.archivedNotes,
                      style: theme.textTheme.bodyMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (count != null)
                    Text(
                      '$count',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    )
                  else if (isLoading)
                    SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: colorScheme.primary,
                      ),
                    )
                  else
                    Text(
                      '—',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Align(
                alignment: Alignment.centerRight,
                child: NoteSortChip(
                  selected: sort,
                  provider: archivedMyNotesSortProvider,
                  options: const [
                    NoteListSort.archivedNewest,
                    NoteListSort.archivedOldest,
                  ],
                  semanticIdentifier: 'action-sort-archived-notes',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MyNoteCard extends StatelessWidget {
  final PlaceEntity place;
  final WorldNavigation navigation;
  final VoidCallback? onArchive;
  final VoidCallback? onCreateFromArchive;

  const _MyNoteCard({
    required this.place,
    required this.navigation,
    this.onArchive,
    this.onCreateFromArchive,
  });

  @override
  Widget build(BuildContext context) {
    final color = parsePlaceColor(place.colorHex);
    final lastActivity = place.lastMessageAt ?? place.createdAt;
    final l10n = context.l10n;

    return Semantics(
      identifier: 'my-note-card-${place.id}',
      button: true,
      child: NoteListCard(
        avatarColor: color,
        avatarIcon: placeIconData(place.icon),
        avatarImageStoragePath: place.pinImageStoragePath,
        themeId: place.themeId,
        isArchived: place.isArchived,
        avatarBadge: UserAvatarBadge(
          name: place.creatorName,
          photoUrl: place.creatorPhotoUrl,
          photoVersion: place.creatorPhotoVersion,
        ),
        title: place.title,
        subtitle: place.subtitle,
        metadata: [
          NoteListMeta(
            icon: Icons.schedule_outlined,
            label: l10n.lastActive(_relativeTime(l10n, lastActivity)),
          ),
          if (place.isArchived)
            NoteListMeta(
              icon: Icons.archive_outlined,
              label: l10n.archivedAt(
                _relativeTime(l10n, place.archivedAt ?? place.expiresAt),
              ),
            )
          else if (place.isClosed)
            NoteListMeta(
              icon: Icons.do_not_disturb_on_outlined,
              label: l10n.noteClosed,
            ),
          if (place.isPrivate)
            NoteListMeta(icon: Icons.lock_outline, label: l10n.notePrivate),
        ],
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _MessageCountBadge(count: place.messageCount),
            const SizedBox(width: 8),
            _LikeCountBadge(count: place.likeCount),
            if (onCreateFromArchive != null) ...[
              const SizedBox(width: 4),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: l10n.createFromArchiveTooltip,
                onPressed: onCreateFromArchive,
                icon: const Icon(Icons.add_location_alt_outlined, size: 20),
              ),
            ],
            if (onArchive != null) ...[
              const SizedBox(width: 4),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: l10n.archiveNoteTooltip,
                onPressed: onArchive,
                icon: const Icon(Icons.archive_outlined, size: 20),
              ),
            ],
          ],
        ),
        onTap: () => context.push(navigation.note(place.id, readOnly: true)),
      ),
    );
  }

  String _relativeTime(AppLocalizations l10n, DateTime time) =>
      formatRelativeTime(l10n, time);
}

class _MessageCountBadge extends StatelessWidget {
  final int count;

  const _MessageCountBadge({required this.count});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.chat_bubble_outline,
          size: 14,
          color: colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 3),
        Text(
          '$count',
          style: theme.textTheme.labelMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _LikeCountBadge extends StatelessWidget {
  final int count;

  const _LikeCountBadge({required this.count});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.favorite_border,
          size: 14,
          color: colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 3),
        Text(
          '$count',
          style: theme.textTheme.labelMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _EmptyArchivedNotesView extends StatelessWidget {
  const _EmptyArchivedNotesView();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.archive_outlined,
              size: 64,
              color: theme.colorScheme.outlineVariant,
            ),
            const SizedBox(height: 16),
            Text(
              l10n.noArchivedNotes,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScrollableStatusView extends StatelessWidget {
  final Widget child;

  const _ScrollableStatusView({required this.child});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [SizedBox(height: constraints.maxHeight, child: child)],
      ),
    );
  }
}

class _EmptyMyNotesView extends StatelessWidget {
  const _EmptyMyNotesView();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.bookmark_border_outlined,
              size: 64,
              color: theme.colorScheme.outlineVariant,
            ),
            const SizedBox(height: 16),
            Text(
              l10n.noMyNotes,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
