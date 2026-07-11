import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/place_icon.dart';
import '../../../domain/entities/place_entity.dart';
import '../../../domain/policies/note_permissions.dart';
import '../../providers/providers.dart';
import '../../widgets/my_notes_notification_controls.dart';
import '../../widgets/note/note_list_card.dart';
import '../note/note_creation_screen.dart';
import 'nearby_notifications_view.dart';

class MyNotesScreen extends ConsumerWidget {
  const MyNotesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Semantics(
      identifier: 'screen-my-notes',
      child: const DefaultTabController(
        length: 3,
        child: Scaffold(
          appBar: _NotesAppBar(),
          body: TabBarView(
            children: [
              _MyNotesListView(),
              _ArchivedNotesListView(),
              NearbyNotificationsView(),
            ],
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
    return AppBar(
      title: const Text('Notes'),
      actions: const [MyNotesNotificationIconButton()],
      bottom: const TabBar(
        tabs: [
          Tab(text: 'My Notes'),
          Tab(text: 'Archived'),
          Tab(text: 'Nearby Alerts'),
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Archive this note?'),
        content: const Text(
          'It will disappear from the map, become read-only, and free one '
          'note slot. You cannot restore the archived note, but you can '
          'create a new note from its title, description, and location later.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Archive'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    try {
      await ref.read(placeRepositoryProvider).archivePlace(place.id);
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to archive note: $error')));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final placesAsync = ref.watch(myPlacesProvider);
    final noteLimit = ref.watch(noteLimitProvider);
    final currentUser = ref.watch(authStateProvider).valueOrNull;

    return Column(
      children: [
        _NoteLimitSummary(
          currentCount: placesAsync.valueOrNull?.length ?? 0,
          limit: noteLimit,
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(myPlacesProvider);
              await ref.read(myPlacesProvider.future);
            },
            child: placesAsync.when(
              loading: () => const _ScrollableStatusView(
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => _ScrollableStatusView(
                child: Center(child: Text('Error: $e')),
              ),
              data: (places) {
                if (places.isEmpty) {
                  return const _ScrollableStatusView(
                    child: _EmptyMyNotesView(),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
                  physics: const AlwaysScrollableScrollPhysics(),
                  itemCount: places.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final place = places[index];
                    final permissions = place.permissionsFor(
                      uid: currentUser?.id,
                      membership: null,
                      readOnly: true,
                      now: DateTime.now(),
                    );
                    return _MyNoteCard(
                      place: place,
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

class _ArchivedNotesListView extends ConsumerWidget {
  const _ArchivedNotesListView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final placesAsync = ref.watch(archivedMyPlacesProvider);

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(archivedMyPlacesProvider);
        await ref.read(archivedMyPlacesProvider.future);
      },
      child: placesAsync.when(
        loading: () => const _ScrollableStatusView(
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (e, _) =>
            _ScrollableStatusView(child: Center(child: Text('Error: $e'))),
        data: (places) {
          if (places.isEmpty) {
            return const _ScrollableStatusView(
              child: _EmptyArchivedNotesView(),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
            physics: const AlwaysScrollableScrollPhysics(),
            itemCount: places.length,
            separatorBuilder: (context, index) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final place = places[index];
              return _MyNoteCard(
                place: place,
                onCreateFromArchive: () => context.push(
                  '/note/create',
                  extra: NoteCreationDraft.fromPlace(place),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _NoteLimitSummary extends StatelessWidget {
  final int currentCount;
  final int limit;

  const _NoteLimitSummary({required this.currentCount, required this.limit});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Icon(Icons.note_alt_outlined, size: 18, color: colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Created notes',
              style: theme.textTheme.bodyMedium,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            '$currentCount / $limit',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _MyNoteCard extends StatelessWidget {
  final PlaceEntity place;
  final VoidCallback? onArchive;
  final VoidCallback? onCreateFromArchive;

  const _MyNoteCard({
    required this.place,
    this.onArchive,
    this.onCreateFromArchive,
  });

  @override
  Widget build(BuildContext context) {
    final color = parsePlaceColor(place.colorHex);
    final lastActivity = place.lastMessageAt ?? place.createdAt;

    return Semantics(
      identifier: 'my-note-card-${place.id}',
      button: true,
      child: NoteListCard(
        avatarColor: color,
        avatarIcon: placeIconData(place.icon),
        avatarImageStoragePath: place.pinImageStoragePath,
        title: place.title,
        subtitle: place.subtitle,
        metadata: [
          NoteListMeta(
            icon: Icons.schedule_outlined,
            label: 'Last active ${_relativeTime(lastActivity)}',
          ),
          if (place.isArchived)
            NoteListMeta(
              icon: Icons.archive_outlined,
              label:
                  'Archived ${_relativeTime(place.archivedAt ?? place.expiresAt)}',
            )
          else if (place.isClosed)
            const NoteListMeta(
              icon: Icons.do_not_disturb_on_outlined,
              label: 'Closed',
            ),
          if (place.isPrivate)
            const NoteListMeta(icon: Icons.lock_outline, label: 'Private'),
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
                tooltip: 'Create new note from archive',
                onPressed: onCreateFromArchive,
                icon: const Icon(Icons.add_location_alt_outlined, size: 20),
              ),
            ],
            if (onArchive != null) ...[
              const SizedBox(width: 4),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: 'Archive note',
                onPressed: onArchive,
                icon: const Icon(Icons.archive_outlined, size: 20),
              ),
            ],
          ],
        ),
        onTap: () => context.push('/note/${place.id}?readOnly=true'),
      ),
    );
  }

  String _relativeTime(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inDays >= 1) {
      return '${diff.inDays} day${diff.inDays == 1 ? '' : 's'} ago';
    }
    if (diff.inHours >= 1) {
      return '${diff.inHours} hour${diff.inHours == 1 ? '' : 's'} ago';
    }
    if (diff.inMinutes >= 1) {
      return '${diff.inMinutes} min ago';
    }
    return 'just now';
  }
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
              'No archived notes yet.',
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
              'No notes yet.\nCreate one from the Map tab.',
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
