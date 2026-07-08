import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../config/app_config.dart';
import '../../../core/utils/place_icon.dart';
import '../../../domain/entities/nearby_notification_entity.dart';
import '../../providers/providers.dart';
import '../../widgets/note/note_list_card.dart';

class NearbyNotificationsView extends ConsumerWidget {
  const NearbyNotificationsView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final alertsAsync = ref.watch(nearbyNotificationPlacesProvider);

    return alertsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (alerts) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            '${alerts.length} / ${AppConfig.nearbyNotificationLimit}',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            'You will be notified when a followed note has new messages and '
            'you are within the note access range.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          if (alerts.isEmpty)
            const _EmptyNearbyAlerts()
          else
            for (var index = 0; index < alerts.length; index++) ...[
              _NearbyAlertCard(alert: alerts[index]),
              if (index < alerts.length - 1) const SizedBox(height: 10),
            ],
        ],
      ),
    );
  }
}

class _EmptyNearbyAlerts extends StatelessWidget {
  const _EmptyNearbyAlerts();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        children: [
          Icon(
            Icons.near_me_disabled_outlined,
            size: 48,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 12),
          Text(
            'No nearby alerts yet.',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 4),
          Text(
            'Open someone else\'s note and turn on Nearby Note Alerts.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _NearbyAlertCard extends ConsumerStatefulWidget {
  final NearbyNotificationPlace alert;

  const _NearbyAlertCard({required this.alert});

  @override
  ConsumerState<_NearbyAlertCard> createState() => _NearbyAlertCardState();
}

class _NearbyAlertCardState extends ConsumerState<_NearbyAlertCard> {
  bool _busy = false;

  Future<void> _disable() async {
    final confirmed = await _confirmDisable();
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    try {
      await ref
          .read(placeRepositoryProvider)
          .setNearbyNotification(placeId: widget.alert.placeId, enabled: false);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Nearby alert turned off.')));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not disable this alert.')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool?> _confirmDisable() {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.notifications_off_outlined),
        title: const Text('Turn off nearby alert?'),
        content: const Text(
          'You will need to visit this location again to turn nearby alerts '
          'back on.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Turn off'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final alert = widget.alert;
    final expires = _dateLabel(alert.expiresAt);
    final lastNotified = alert.lastNotifiedMessageAt == null
        ? 'No notifications yet'
        : 'Last notified ${_dateLabel(alert.lastNotifiedMessageAt!)}';

    final color = parsePlaceColor(alert.colorHex);

    return NoteListCard(
      avatarColor: color,
      avatarIcon: placeIconData(alert.icon),
      avatarImageStoragePath: alert.pinImageStoragePath,
      title: alert.title,
      metadata: [
        NoteListMeta(icon: Icons.event_outlined, label: 'Expires $expires'),
        NoteListMeta(
          icon: Icons.notifications_none_outlined,
          label: lastNotified,
        ),
      ],
      trailing: _busy
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : IconButton(
              tooltip: 'Turn off',
              icon: const Icon(Icons.notifications_off_outlined),
              onPressed: _disable,
            ),
    );
  }

  String _dateLabel(DateTime value) {
    final local = value.toLocal();
    return '${local.year}/${local.month.toString().padLeft(2, '0')}/'
        '${local.day.toString().padLeft(2, '0')}';
  }
}
