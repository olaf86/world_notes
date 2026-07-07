import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/time_format.dart';
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
    setState(() => _settingBusy = true);
    try {
      await ref
          .read(placeRepositoryProvider)
          .setFootprintEnabled(placeId: widget.placeId, enabled: enabled);
    } on FirebaseFunctionsException catch (e) {
      _snack(e.message ?? 'Could not update footprints.');
    } catch (e) {
      _snack(e.toString());
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
    final membership = place?.isPrivate == true
        ? ref.watch(noteMembershipProvider(widget.placeId)).valueOrNull
        : null;
    final permissions = place?.permissionsFor(
      uid: currentUser?.id,
      membership: membership,
      readOnly: false,
      now: DateTime.now(),
    );
    final visitorsAsync = ref.watch(
      noteVisitorsProvider(
        NoteVisitorsRequest(placeId: widget.placeId, sort: _sort),
      ),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Footprints')),
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
              segments: const [
                ButtonSegment(
                  value: NoteVisitorSort.latest,
                  icon: Icon(Icons.schedule_outlined),
                  label: Text('Latest'),
                ),
                ButtonSegment(
                  value: NoteVisitorSort.visitCount,
                  icon: Icon(Icons.repeat_outlined),
                  label: Text('Visits'),
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
                  child: Text('Could not load footprints: $error'),
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
                  itemBuilder: (context, index) =>
                      _VisitorTile(visitor: visitors[index], sort: _sort),
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
                    enabled ? 'Footprints are on' : 'Footprints are off',
                    style: theme.textTheme.titleMedium,
                  ),
                  Text(
                    enabled
                        ? _visitorCountLabel
                        : 'New visits are not being recorded',
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

  String get _visitorCountLabel {
    final noun = visitorCount == 1 ? 'visitor' : 'visitors';
    final verb = visitorCount == 1 ? 'has' : 'have';
    return '$visitorCount $noun $verb left footprints';
  }
}

class _VisitorTile extends StatelessWidget {
  final NoteVisitor visitor;
  final NoteVisitorSort sort;

  const _VisitorTile({required this.visitor, required this.sort});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final photoUrl = visitor.photoUrl;
    final primaryDetail = switch (sort) {
      NoteVisitorSort.latest => noteDateTimeLabel(visitor.lastVisitedAt),
      NoteVisitorSort.visitCount =>
        '${visitor.visitCount} visit${visitor.visitCount == 1 ? '' : 's'}',
    };
    final secondaryDetail = switch (sort) {
      NoteVisitorSort.latest =>
        '${visitor.visitCount} visit${visitor.visitCount == 1 ? '' : 's'}',
      NoteVisitorSort.visitCount => noteDateTimeLabel(visitor.lastVisitedAt),
    };

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircleAvatar(
              radius: 28,
              backgroundImage: photoUrl == null ? null : NetworkImage(photoUrl),
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
                'Maintainer',
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
            Text('No footprints yet', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Visitors will appear here after they open this note.',
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
