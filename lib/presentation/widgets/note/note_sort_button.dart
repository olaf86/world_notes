import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/entities/note_list_sort.dart';

class NoteSortButton extends ConsumerWidget {
  final NoteListSort selected;
  final StateProvider<NoteListSort> provider;
  final String semanticIdentifier;

  const NoteSortButton({
    super.key,
    required this.selected,
    required this.provider,
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
        itemBuilder: (context) => NoteListSort.values
            .map(
              (sort) => PopupMenuItem(
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
            .toList(),
      ),
    );
  }
}

extension NoteListSortPresentation on NoteListSort {
  String get label => switch (this) {
    NoteListSort.distance => 'Distance',
    NoteListSort.newest => 'Newest',
    NoteListSort.expiresSoonest => 'Expires soon',
    NoteListSort.mostLiked => 'Most liked',
  };

  IconData get icon => switch (this) {
    NoteListSort.distance => Icons.near_me_outlined,
    NoteListSort.newest => Icons.schedule_outlined,
    NoteListSort.expiresSoonest => Icons.event_outlined,
    NoteListSort.mostLiked => Icons.favorite_border,
  };
}
