import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../config/app_config.dart';
import '../../../domain/entities/note_visitor_entity.dart';
import '../../providers/providers.dart';

class VisitorPreview extends ConsumerWidget {
  static const double _avatarSize = 30;
  static const double _avatarStep = 20;

  final String placeId;
  final bool footprintEnabled;
  final int visitorCount;

  const VisitorPreview({
    super.key,
    required this.placeId,
    required this.footprintEnabled,
    required this.visitorCount,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final visitors = ref.watch(recentNoteVisitorsProvider(placeId));

    return Material(
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.48),
      child: InkWell(
        onTap: () => context.push('/note/$placeId/visitors'),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final maxAvatars = _maxAvatarsForWidth(constraints.maxWidth);
              return visitors.when(
                loading: () => _PreviewRow(
                  icon: Icons.directions_walk,
                  title: _title,
                  subtitle: _subtitle,
                  trailing: const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
                error: (_, _) => _PreviewRow(
                  icon: Icons.directions_walk,
                  title: _title,
                  subtitle: _subtitle,
                  trailing: const Icon(Icons.chevron_right),
                ),
                data: (items) => _PreviewRow(
                  icon: Icons.directions_walk,
                  title: _title,
                  subtitle: _subtitle,
                  avatars: items.take(maxAvatars).toList(),
                  avatarSize: _avatarSize,
                  avatarStep: _avatarStep,
                  trailing: const Icon(Icons.chevron_right),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  String get _title {
    if (!footprintEnabled) return 'Footprints off';
    if (visitorCount == 0) return 'No footprints yet';
    return '$visitorCount footprint${visitorCount == 1 ? '' : 's'}';
  }

  String get _subtitle {
    if (!footprintEnabled) return 'Visits are not being recorded';
    return visitorCount == 0 ? 'Be the first to leave one' : 'Recent visitors';
  }

  int _maxAvatarsForWidth(double width) {
    final expanded = width >= 520;
    final cap = expanded
        ? AppConfig.visitorPreviewExpandedMax
        : AppConfig.visitorPreviewCompactMax;
    final reservedForText = expanded ? 220 : 180;
    final available = math.max(0, width - reservedForText);
    final byWidth = 1 + (available / _avatarStep).floor();
    return math.max(0, math.min(cap, byWidth));
  }
}

class _PreviewRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final List<NoteVisitor> avatars;
  final double avatarSize;
  final double avatarStep;
  final Widget trailing;

  const _PreviewRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.avatars = const [],
    this.avatarSize = 30,
    this.avatarStep = 20,
    required this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, color: theme.colorScheme.primary),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: theme.textTheme.titleSmall),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        if (avatars.isNotEmpty) ...[
          const SizedBox(width: 12),
          SizedBox(
            width: avatarSize + (avatars.length - 1) * avatarStep,
            height: avatarSize,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                for (var i = 0; i < avatars.length; i++)
                  Positioned(
                    left: i * avatarStep,
                    child: _VisitorAvatar(
                      visitor: avatars[i],
                      size: avatarSize,
                    ),
                  ),
              ],
            ),
          ),
        ],
        const SizedBox(width: 8),
        IconTheme(
          data: IconThemeData(color: theme.colorScheme.onSurfaceVariant),
          child: trailing,
        ),
      ],
    );
  }
}

class _VisitorAvatar extends StatelessWidget {
  final NoteVisitor visitor;
  final double size;

  const _VisitorAvatar({required this.visitor, required this.size});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final photoUrl = visitor.photoUrl;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: theme.colorScheme.surface, width: 2),
      ),
      child: CircleAvatar(
        backgroundImage: photoUrl == null ? null : NetworkImage(photoUrl),
        child: photoUrl == null ? Text(_initial(visitor.label)) : null,
      ),
    );
  }

  String _initial(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? '?' : trimmed[0].toUpperCase();
  }
}
