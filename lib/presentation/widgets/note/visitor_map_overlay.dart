import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../domain/entities/note_visitor_entity.dart';
import '../../../l10n/l10n.dart';
import '../../providers/providers.dart';

class VisitorMapOverlay extends ConsumerWidget {
  static const double _avatarSize = 22;
  static const double _avatarStep = 14;
  static const int _avatarMax = 3;

  final String placeId;
  final bool footprintEnabled;
  final int visitorCount;

  const VisitorMapOverlay({
    super.key,
    required this.placeId,
    required this.footprintEnabled,
    required this.visitorCount,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final visitors = ref.watch(recentNoteVisitorsProvider(placeId));

    void onTap() {
      context.push(
        ref.read(selectedWorldNavigationProvider).noteVisitors(placeId),
      );
    }

    return visitors.when(
      loading: () => _OverlayPreview(
        title: _title(context),
        avatars: const [],
        trailing: const SizedBox.square(
          dimension: 12,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        onTap: onTap,
      ),
      error: (_, _) => _OverlayPreview(
        title: _title(context),
        avatars: const [],
        trailing: const Icon(Icons.chevron_right, size: 16),
        onTap: onTap,
      ),
      data: (items) => _OverlayPreview(
        title: _title(context),
        avatars: footprintEnabled ? items.take(_avatarMax).toList() : const [],
        avatarSize: _avatarSize,
        avatarStep: _avatarStep,
        trailing: const Icon(Icons.chevron_right, size: 16),
        onTap: onTap,
      ),
    );
  }

  String _title(BuildContext context) {
    if (!footprintEnabled) return context.l10n.footprintsOff;
    if (visitorCount == 0) return context.l10n.noFootprints;
    return context.l10n.footprintCount(visitorCount);
  }
}

class _OverlayPreview extends StatelessWidget {
  final String title;
  final List<NoteVisitor> avatars;
  final double avatarSize;
  final double avatarStep;
  final Widget trailing;
  final VoidCallback onTap;

  const _OverlayPreview({
    required this.title,
    required this.avatars,
    this.avatarSize = 24,
    this.avatarStep = 16,
    required this.trailing,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final borderRadius = BorderRadius.circular(999);
    final maxWidth = math.max(
      104.0,
      math.min(220.0, MediaQuery.sizeOf(context).width - 64),
    );

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Material(
        color: theme.colorScheme.surface.withValues(alpha: 0.92),
        elevation: 3,
        shadowColor: theme.colorScheme.shadow.withValues(alpha: 0.18),
        borderRadius: borderRadius,
        child: InkWell(
          borderRadius: borderRadius,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(8, 5, 6, 5),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.directions_walk,
                  size: 15,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium,
                  ),
                ),
                if (avatars.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  SizedBox(
                    width: avatarSize + (avatars.length - 1) * avatarStep,
                    height: avatarSize,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        for (var i = 0; i < avatars.length; i++)
                          PositionedDirectional(
                            start: i * avatarStep,
                            child: _VisitorAvatar(
                              visitor: avatars[i],
                              size: avatarSize,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(width: 4),
                IconTheme(
                  data: IconThemeData(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  child: trailing,
                ),
              ],
            ),
          ),
        ),
      ),
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
