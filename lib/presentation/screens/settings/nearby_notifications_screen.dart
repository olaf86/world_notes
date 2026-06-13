import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../config/app_config.dart';
import '../../../domain/entities/nearby_notification_entity.dart';
import '../../providers/providers.dart';

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
            'These alerts are only for notes you do not own. You will be '
            'notified when a followed note has new messages and you are '
            'within the note access range.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          if (alerts.isEmpty)
            const _EmptyNearbyAlerts()
          else
            ...alerts.map((alert) => _NearbyAlertTile(alert: alert)),
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

class _NearbyAlertTile extends ConsumerStatefulWidget {
  final NearbyNotificationPlace alert;

  const _NearbyAlertTile({required this.alert});

  @override
  ConsumerState<_NearbyAlertTile> createState() => _NearbyAlertTileState();
}

class _NearbyAlertTileState extends ConsumerState<_NearbyAlertTile> {
  bool _busy = false;

  Future<void> _disable() async {
    setState(() => _busy = true);
    try {
      await ref
          .read(placeRepositoryProvider)
          .setNearbyNotification(placeId: widget.alert.placeId, enabled: false);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not disable this alert.')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final alert = widget.alert;
    final radiusKm = alert.radiusMeters / 1000;
    final expires = _dateLabel(alert.expiresAt);
    final lastNotified = alert.lastNotifiedMessageAt == null
        ? 'No notifications yet'
        : 'Last notified ${_dateLabel(alert.lastNotifiedMessageAt!)}';

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.notifications_active_outlined),
      title: Text(alert.title),
      subtitle: Text(
        'Within ${radiusKm.toStringAsFixed(radiusKm >= 10 ? 0 : 1)} km '
        '/ expires $expires\n$lastNotified',
      ),
      isThreeLine: true,
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
