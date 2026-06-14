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
      length: 2,
      child: Scaffold(
        appBar: _NotesAppBar(),
        body: TabBarView(
          children: [_MyNotesListView(), NearbyNotificationsView()],
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

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(myPlacesProvider);
        await ref.read(myPlacesProvider.future);
      },
      child: placesAsync.when(
        loading: () => const _ScrollableStatusView(
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (e, _) =>
            _ScrollableStatusView(child: Center(child: Text('Error: $e'))),
        data: (places) {
          if (places.isEmpty) {
            return const _ScrollableStatusView(child: _EmptyMyNotesView());
          }

          return ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            itemCount: places.length,
            separatorBuilder: (context, index) => const Divider(height: 1),
            itemBuilder: (context, index) => _MyNoteTile(place: places[index]),
          );
        },
      ),
    );
  }
}

class _MyNoteTile extends StatelessWidget {
  final PlaceEntity place;

  const _MyNoteTile({required this.place});

  @override
  Widget build(BuildContext context) {
    final color = parsePlaceColor(place.colorHex);
    final lastActivity = place.lastMessageAt ?? place.createdAt;
    final subtitle = place.subtitle?.isNotEmpty == true
        ? place.subtitle!
        : 'Last active ${_relativeTime(lastActivity)}';

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: color,
        child: Icon(placeIconData(place.icon), color: Colors.white, size: 20),
      ),
      title: Row(
        children: [
          if (place.isClosed) ...[
            Icon(
              Icons.do_not_disturb_on_outlined,
              size: 14,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(width: 4),
          ] else if (place.isPrivate) ...[
            Icon(
              Icons.lock_outline,
              size: 14,
              color: Theme.of(context).colorScheme.tertiary,
            ),
            const SizedBox(width: 4),
          ],
          Expanded(
            child: Text(
              place.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      subtitle: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Icon(
            Icons.visibility_outlined,
            size: 16,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 2),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.chat_bubble_outline,
                size: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 2),
              Text(
                '${place.messageCount}',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
      ),
      onTap: () => context.push('/note/${place.id}?readOnly=true'),
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
