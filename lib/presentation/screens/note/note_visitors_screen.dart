import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../l10n/l10n.dart';
import '../../../l10n/localized_formatters.dart';
import '../../../domain/entities/note_visitor_entity.dart';
import '../../../domain/policies/note_permissions.dart';
import '../../providers/providers.dart';

class NoteVisitorsScreen extends ConsumerStatefulWidget {
  final String placeId;

  const NoteVisitorsScreen({super.key, required this.placeId});

  @override
  ConsumerState<NoteVisitorsScreen> createState() => _NoteVisitorsScreenState();
}

class _NoteVisitorsScreenState extends ConsumerState<NoteVisitorsScreen> {
  NoteVisitorSort _sort = NoteVisitorSort.latest;
  bool _settingBusy = false;

  Future<void> _setFootprints(bool enabled) async {
    if (_settingBusy) return;
    final failureMessage = context.l10n.footprintsUpdateFailed;
    setState(() => _settingBusy = true);
    try {
      await ref
          .read(placeRepositoryProvider)
          .setFootprintEnabled(placeId: widget.placeId, enabled: enabled);
    } on FirebaseFunctionsException {
      _snack(failureMessage);
    } catch (_) {
      _snack(failureMessage);
    } finally {
      if (mounted) setState(() => _settingBusy = false);
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
    final placeAsync = ref.watch(placeProvider(widget.placeId));
    final place = placeAsync.valueOrNull;
    final currentUser = ref.watch(authStateProvider).valueOrNull;
    final isAdministrator =
        ref
            .watch(noteAdministratorAuthorityProvider(widget.placeId))
            .valueOrNull ??
        false;
    final membership = place?.isPrivate == true
        ? ref.watch(noteMembershipProvider(widget.placeId)).valueOrNull
        : null;
    final permissions = place?.permissionsFor(
      uid: currentUser?.id,
      membership: membership,
      isAdministrator: isAdministrator,
      readOnly: false,
      now: DateTime.now(),
    );
    final visitorsAsync = ref.watch(
      noteVisitorsProvider(
        NoteVisitorsRequest(placeId: widget.placeId, sort: _sort),
      ),
    );

    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.footprintsTitle)),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _FootprintSettingsHeader(
            enabled: place?.footprintEnabled ?? true,
            visitorCount: place?.visitorCount ?? 0,
            canChange: permissions?.isMaintainer ?? false,
            busy: _settingBusy,
            onChanged: _setFootprints,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: SegmentedButton<NoteVisitorSort>(
              segments: [
                ButtonSegment(
                  value: NoteVisitorSort.latest,
                  icon: const Icon(Icons.schedule_outlined),
                  label: Text(context.l10n.sortLatest),
                ),
                ButtonSegment(
                  value: NoteVisitorSort.visitCount,
                  icon: const Icon(Icons.repeat_outlined),
                  label: Text(context.l10n.visitsLabel),
                ),
              ],
              selected: {_sort},
              onSelectionChanged: (selected) {
                setState(() => _sort = selected.first);
              },
            ),
          ),
          Expanded(
            child: visitorsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(context.l10n.footprintsLoadFailed(error)),
                ),
              ),
              data: (visitors) {
                if (visitors.isEmpty) {
                  return const _EmptyVisitors();
                }
                return GridView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 180,
                    mainAxisExtent: 164,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                  ),
                  itemCount: visitors.length,
                  itemBuilder: (context, index) => _VisitorTile(
                    visitor: visitors[index],
                    sort: _sort,
                    onTap: () =>
                        context.push('/users/${visitors[index].userId}'),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _FootprintSettingsHeader extends StatelessWidget {
  final bool enabled;
  final int visitorCount;
  final bool canChange;
  final bool busy;
  final ValueChanged<bool> onChanged;

  const _FootprintSettingsHeader({
    required this.enabled,
    required this.visitorCount,
    required this.canChange,
    required this.busy,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.48),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.directions_walk, color: theme.colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    enabled
                        ? context.l10n.footprintsOn
                        : context.l10n.footprintsOff,
                    style: theme.textTheme.titleMedium,
                  ),
                  Text(
                    enabled
                        ? context.l10n.footprintCount(visitorCount)
                        : context.l10n.newVisitsNotRecorded,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (canChange)
              Switch(value: enabled, onChanged: busy ? null : onChanged),
          ],
        ),
      ),
    );
  }
}

class _VisitorTile extends StatelessWidget {
  final NoteVisitor visitor;
  final NoteVisitorSort sort;
  final VoidCallback onTap;

  const _VisitorTile({
    required this.visitor,
    required this.sort,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final photoUrl = visitor.photoUrl;
    final primaryDetail = switch (sort) {
      NoteVisitorSort.latest => formatNoteDateTime(
        visitor.lastVisitedAt,
        locale: context.localeTag,
      ),
      NoteVisitorSort.visitCount => context.l10n.visitCountLabel(
        visitor.visitCount,
      ),
    };
    final secondaryDetail = switch (sort) {
      NoteVisitorSort.latest => context.l10n.visitCountLabel(
        visitor.visitCount,
      ),
      NoteVisitorSort.visitCount => formatNoteDateTime(
        visitor.lastVisitedAt,
        locale: context.localeTag,
      ),
    };

    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircleAvatar(
                radius: 28,
                backgroundImage: photoUrl == null
                    ? null
                    : NetworkImage(photoUrl),
                child: photoUrl == null ? Text(_initial(visitor.label)) : null,
              ),
              const SizedBox(height: 10),
              Text(
                visitor.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall,
              ),
              if (visitor.isMaintainer)
                Text(
                  context.l10n.noteAdministratorLabel,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
              Text(
                primaryDetail,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              Text(
                secondaryDetail,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _initial(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? '?' : trimmed[0].toUpperCase();
  }
}

class _EmptyVisitors extends StatelessWidget {
  const _EmptyVisitors();

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
              Icons.directions_walk,
              size: 42,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(context.l10n.noFootprints, style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              context.l10n.noFootprintsDescription,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
