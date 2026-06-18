import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/place_icon.dart';
import '../../../domain/entities/place_entity.dart';
import '../../providers/providers.dart';
import '../../widgets/my_notes_notification_controls.dart';
import '../settings/nearby_notifications_screen.dart';

class MyNotesScreen extends ConsumerWidget {
  const MyNotesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const DefaultTabController(
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final placesAsync = ref.watch(myPlacesProvider);
    final noteLimit = ref.watch(noteLimitProvider);

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
                  itemBuilder: (context, index) =>
                      _MyNoteCard(place: places[index]),
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
            itemBuilder: (context, index) => _MyNoteCard(place: places[index]),
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

  const _MyNoteCard({required this.place});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final color = parsePlaceColor(place.colorHex);
    final lastActivity = place.lastMessageAt ?? place.createdAt;
    final subtitle = place.subtitle?.trim();
    final hasSubtitle = subtitle?.isNotEmpty == true;

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => context.push('/note/${place.id}?readOnly=true'),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: color,
                child: Icon(
                  placeIconData(place.icon),
                  color: Colors.white,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            place.title,
                            style: theme.textTheme.titleSmall,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        _MessageCountBadge(count: place.messageCount),
                      ],
                    ),
                    if (hasSubtitle)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          subtitle!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          _NoteMetaChip(
                            icon: Icons.schedule_outlined,
                            label: 'Last active ${_relativeTime(lastActivity)}',
                          ),
                          if (place.isArchived)
                            _NoteMetaChip(
                              icon: Icons.archive_outlined,
                              label:
                                  'Archived ${_relativeTime(place.archivedAt ?? place.expiresAt)}',
                            )
                          else if (place.isClosed)
                            const _NoteMetaChip(
                              icon: Icons.do_not_disturb_on_outlined,
                              label: 'Closed',
                            ),
                          if (place.isPrivate)
                            const _NoteMetaChip(
                              icon: Icons.lock_outline,
                              label: 'Private',
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
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

class _NoteMetaChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _NoteMetaChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: colorScheme.onSurfaceVariant),
        const SizedBox(width: 3),
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
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
