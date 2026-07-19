import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/place_icon.dart';
import '../../../core/theme/note_themes.dart';
import '../../../core/utils/time_format.dart';
import '../../../domain/entities/pin_summary_entity.dart';
import '../../../l10n/app_localizations.dart';
import '../../../l10n/app_localizations_ext.dart';
import '../../providers/providers.dart';
import '../../screens/map/map_pin_display.dart';
import '../note/note_pin_avatar.dart';
import '../note/user_avatar_badge.dart';

class NoteMarkerBottomSheet extends ConsumerStatefulWidget {
  final PinSummary pin;
  final Future<bool> Function(PinSummary pin) onOpen;

  const NoteMarkerBottomSheet({
    super.key,
    required this.pin,
    required this.onOpen,
  });

  @override
  ConsumerState<NoteMarkerBottomSheet> createState() =>
      _NoteMarkerBottomSheetState();
}

class _NoteMarkerBottomSheetState extends ConsumerState<NoteMarkerBottomSheet> {
  bool _isOpening = false;

  Future<void> _open(MapPinDisplay display) async {
    if (_isOpening || !display.canOpen) return;

    setState(() => _isOpening = true);
    final opened = await widget.onOpen(display.pin);
    if (!mounted) return;

    if (opened) {
      Navigator.of(context).pop();
      return;
    }

    setState(() => _isOpening = false);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = appLocalizationsOf(context);
    final livePosition = ref.watch(positionStreamProvider).valueOrNull;
    final anchor = ref.watch(anchorPositionProvider);
    final position = livePosition ?? anchor;
    final display = position == null
        ? MapPinDisplay.fromServerSnapshot(widget.pin)
        : MapPinDisplay.fromLivePosition(
            pin: widget.pin,
            position: position,
            accessRadiusMeters: ref
                .watch(noteAccessRadiusMetersProvider)
                .toDouble(),
          );
    final pin = display.pin;
    final color = parsePlaceColor(pin.colorHex);
    final palette = NoteThemes.paletteOf(context, pin.themeId);

    return Theme(
      data: NoteThemes.themed(context, pin.themeId),
      child: Builder(
        builder: (context) {
          final theme = Theme.of(context);
          return DecoratedBox(
            decoration: BoxDecoration(gradient: palette.pageGradient),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      NotePinAvatar(
                        color: color,
                        icon: placeIconData(pin.icon),
                        storagePath: pin.pinImageStoragePath,
                        radius: 20,
                        badge: UserAvatarBadge(
                          name: pin.creatorName,
                          photoUrl: pin.creatorPhotoUrl,
                          photoVersion: pin.creatorPhotoVersion,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              pin.title,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            if (pin.subtitle != null)
                              Text(
                                pin.subtitle!,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            Row(
                              children: [
                                Icon(
                                  Icons.person_outline,
                                  size: 14,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    pin.creatorName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            Text(
                              l10n.createdAt(
                                noteDateTimeLabel(
                                  pin.createdAt,
                                  locale: Localizations.localeOf(
                                    context,
                                  ).toLanguageTag(),
                                ),
                              ),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (pin.isFromFollowedAuthor)
                        _MetaChip(
                          icon: Icons.person_pin_circle_outlined,
                          label: l10n.mapNewFromFollowing,
                          color: theme.colorScheme.tertiary,
                        ),
                      if (pin.hasUnseenMessages)
                        _MetaChip(
                          icon: Icons.fiber_new_outlined,
                          label: l10n.newMessages,
                          color: theme.colorScheme.error,
                        ),
                      _MetaChip(
                        icon: Icons.chat_bubble_outline,
                        label: l10n.messageCount(pin.messageCount),
                      ),
                      _MetaChip(
                        icon: Icons.favorite_border,
                        label: l10n.likeCount(pin.likeCount),
                      ),
                      _MetaChip(
                        icon: Icons.directions_walk,
                        label: pin.footprintEnabled
                            ? pin.visitorCount > 0
                                  ? l10n.footprintCount(pin.visitorCount)
                                  : l10n.footprintsOn
                            : l10n.footprintsOff,
                        color: pin.footprintEnabled
                            ? theme.colorScheme.primary
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                      if (pin.isPrivate)
                        _MetaChip(
                          icon: Icons.lock_outline,
                          label: l10n.notePrivate,
                          color: theme.colorScheme.tertiary,
                        ),
                      if (pin.isClosed)
                        _MetaChip(
                          icon: Icons.do_not_disturb_on_outlined,
                          label: l10n.noteClosed,
                          color: theme.colorScheme.error,
                        ),
                      _MetaChip(
                        icon: Icons.schedule,
                        label: _remainingLifetimeLabel(l10n, pin.expiresAt),
                      ),
                      if (!display.canOpen)
                        _MetaChip(
                          icon: Icons.near_me_disabled_outlined,
                          label: l10n.noteMoveCloser,
                          color: theme.colorScheme.secondary,
                        ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: display.canOpen && !_isOpening
                        ? () => _open(display)
                        : null,
                    icon: _isOpening
                        ? SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: theme.colorScheme.onPrimary,
                            ),
                          )
                        : Icon(
                            display.canOpen
                                ? Icons.open_in_new
                                : Icons.lock_outline,
                          ),
                    label: Text(
                      _isOpening
                          ? l10n.noteOpening
                          : display.canOpen
                          ? (pin.isClosed ? l10n.noteView : l10n.noteOpen)
                          : l10n.noteAvailableNearby,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

String _remainingLifetimeLabel(AppLocalizations l10n, DateTime expiresAt) {
  final duration = expiresAt.difference(DateTime.now());
  if (duration.isNegative) return l10n.noteExpired;
  if (duration.inDays >= 60) {
    return l10n.noteExpiresMonths((duration.inDays / 30).round());
  }
  if (duration.inDays >= 1) return l10n.noteExpiresDays(duration.inDays);
  if (duration.inHours >= 1) return l10n.noteExpiresHours(duration.inHours);
  return l10n.noteExpiresSoon;
}

/// Compact icon + label chip used for note metadata (message count, status,
/// remaining lifetime). [color] tints both icon and text; defaults to the
/// muted onSurfaceVariant.
class _MetaChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;

  const _MetaChip({required this.icon, required this.label, this.color});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = color ?? theme.colorScheme.onSurfaceVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: c),
        const SizedBox(width: 4),
        Text(label, style: theme.textTheme.bodySmall?.copyWith(color: c)),
      ],
    );
  }
}
