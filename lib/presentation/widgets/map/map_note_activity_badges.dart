import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../domain/entities/pin_summary_entity.dart';
import '../../../l10n/l10n.dart';
import '../../../l10n/localized_formatters.dart';

/// Prominent, shared status treatment for activity surfaced from the map.
class MapNoteActivityBadges extends StatelessWidget {
  final PinSummary pin;
  final bool animate;

  const MapNoteActivityBadges({
    super.key,
    required this.pin,
    this.animate = true,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = Theme.of(context).colorScheme;

    return Wrap(
      spacing: 8,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (pin.hasUnseenMessages)
          _ActivityBadge(
            key: const ValueKey('map-note-activity-unseen'),
            icon: Icons.mark_chat_unread_rounded,
            label: l10n.newMessages,
            detail: l10n.lastActive(
              formatRelativeTime(l10n, pin.lastActivityAt),
            ),
            foregroundColor: colors.onErrorContainer,
            backgroundColor: colors.errorContainer,
            accentColor: colors.error,
            animate: animate,
          ),
        if (pin.isFromFollowedAuthor)
          _ActivityBadge(
            key: const ValueKey('map-note-activity-followed-author'),
            icon: Icons.person_pin_circle_rounded,
            label: l10n.mapNewFromFollowing,
            semanticLabel: l10n.mapFromFollowingSemantic,
            foregroundColor: colors.onTertiaryContainer,
            backgroundColor: colors.tertiaryContainer,
            accentColor: colors.tertiary,
          ),
      ],
    );
  }
}

class _ActivityBadge extends StatefulWidget {
  final IconData icon;
  final String label;
  final String? detail;
  final String? semanticLabel;
  final Color foregroundColor;
  final Color backgroundColor;
  final Color accentColor;
  final bool animate;

  const _ActivityBadge({
    super.key,
    required this.icon,
    required this.label,
    this.detail,
    this.semanticLabel,
    required this.foregroundColor,
    required this.backgroundColor,
    required this.accentColor,
    this.animate = false,
  });

  @override
  State<_ActivityBadge> createState() => _ActivityBadgeState();
}

class _ActivityBadgeState extends State<_ActivityBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _isAnimating = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncAnimation();
  }

  @override
  void didUpdateWidget(covariant _ActivityBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.animate != widget.animate) _syncAnimation();
  }

  void _syncAnimation() {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final shouldAnimate = widget.animate && !reduceMotion;
    if (shouldAnimate == _isAnimating) return;

    _isAnimating = shouldAnimate;
    if (shouldAnimate) {
      // Two soft pulses draw the eye when the status enters the viewport,
      // then stop so the list remains calm and inexpensive to render.
      _controller.forward(from: 0);
    } else {
      _controller
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final detail = widget.detail;
    final semanticLabel = [
      widget.semanticLabel ?? widget.label,
      ?detail,
    ].join('. ');

    return Semantics(
      container: true,
      label: semanticLabel,
      child: ExcludeSemantics(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            final pulse = math
                .pow(math.sin(_controller.value * math.pi * 2), 2)
                .toDouble();
            return Transform.scale(
              scale: 1 + pulse * 0.035,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: widget.backgroundColor,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: widget.accentColor, width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: widget.accentColor.withValues(
                        alpha: 0.12 + pulse * 0.24,
                      ),
                      blurRadius: 3 + pulse * 9,
                      spreadRadius: pulse * 2,
                    ),
                  ],
                ),
                child: child,
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(widget.icon, size: 16, color: widget.foregroundColor),
                const SizedBox(width: 5),
                Text(
                  widget.label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: widget.foregroundColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (detail != null) ...[
                  const SizedBox(width: 5),
                  Text(
                    '\u00b7 $detail',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: widget.foregroundColor.withValues(alpha: 0.82),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
