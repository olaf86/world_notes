import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/entities/note_list_sort.dart';

class NoteSortButton extends ConsumerWidget {
  final NoteListSort selected;
  final StateProvider<NoteListSort> provider;
  final List<NoteListSort> options;
  final String semanticIdentifier;

  const NoteSortButton({
    super.key,
    required this.selected,
    required this.provider,
    required this.options,
    required this.semanticIdentifier,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Semantics(
      identifier: semanticIdentifier,
      button: true,
      child: PopupMenuButton<NoteListSort>(
        tooltip: 'Sort notes: ${selected.label}',
        icon: const Icon(Icons.sort_outlined),
        onSelected: (sort) => ref.read(provider.notifier).state = sort,
        itemBuilder: (context) =>
            _buildSortMenuItems(context, options: options, selected: selected),
      ),
    );
  }
}

class NoteSortChip extends ConsumerWidget {
  final NoteListSort selected;
  final StateProvider<NoteListSort> provider;
  final List<NoteListSort> options;
  final String semanticIdentifier;

  const NoteSortChip({
    super.key,
    required this.selected,
    required this.provider,
    required this.options,
    required this.semanticIdentifier,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Semantics(
      identifier: semanticIdentifier,
      label: 'Sort notes. ${selected.label} selected',
      button: true,
      child: PopupMenuButton<NoteListSort>(
        tooltip: 'Sort notes: ${selected.label}',
        padding: EdgeInsets.zero,
        position: PopupMenuPosition.under,
        onSelected: (sort) => ref.read(provider.notifier).state = sort,
        itemBuilder: (context) =>
            _buildSortMenuItems(context, options: options, selected: selected),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 7, 8, 7),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.sort_outlined,
                  size: 16,
                  color: colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    selected.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 2),
                Icon(
                  Icons.arrow_drop_down,
                  size: 18,
                  color: colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class NoteSortStatus extends StatelessWidget {
  final NoteListSort sort;
  final String semanticIdentifier;
  final bool inline;

  const NoteSortStatus({
    super.key,
    required this.sort,
    required this.semanticIdentifier,
    this.inline = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = 'Sorted by: ${sort.label}';
    return Semantics(
      identifier: semanticIdentifier,
      label: 'Sorted by ${sort.label}',
      child: inline
          ? Text(
              label,
              textAlign: TextAlign.end,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            )
          : Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 2),
              child: Align(
                alignment: Alignment.centerRight,
                child: Text(
                  label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
    );
  }
}

List<PopupMenuEntry<NoteListSort>> _buildSortMenuItems(
  BuildContext context, {
  required List<NoteListSort> options,
  required NoteListSort selected,
}) {
  return options
      .map(
        (sort) => PopupMenuItem<NoteListSort>(
          value: sort,
          child: Row(
            children: [
              Icon(sort.icon, size: 20),
              const SizedBox(width: 12),
              Expanded(child: Text(sort.label)),
              if (sort == selected)
                Icon(
                  Icons.check,
                  size: 20,
                  color: Theme.of(context).colorScheme.primary,
                ),
            ],
          ),
        ),
      )
      .toList();
}

extension NoteListSortPresentation on NoteListSort {
  String get label => switch (this) {
    NoteListSort.distance => 'Distance',
    NoteListSort.lastActivity => 'Last activity',
    NoteListSort.newest => 'Newest',
    NoteListSort.expiresSoonest => 'Expires soon',
    NoteListSort.mostLiked => 'Most liked',
    NoteListSort.archivedNewest => 'Recently archived',
    NoteListSort.archivedOldest => 'Oldest archived',
  };

  IconData get icon => switch (this) {
    NoteListSort.distance => Icons.near_me_outlined,
    NoteListSort.lastActivity => Icons.forum_outlined,
    NoteListSort.newest => Icons.schedule_outlined,
    NoteListSort.expiresSoonest => Icons.event_outlined,
    NoteListSort.mostLiked => Icons.favorite_border,
    NoteListSort.archivedNewest => Icons.archive_outlined,
    NoteListSort.archivedOldest => Icons.unarchive_outlined,
  };
}
