import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:geolocator/geolocator.dart';

import '../../../core/utils/place_icon.dart';
import '../../../domain/entities/pin_summary_entity.dart';
import '../../../services/location_service.dart';
import '../../providers/providers.dart';

class PlaceListScreen extends ConsumerWidget {
  final bool embedded;

  const PlaceListScreen({super.key, this.embedded = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final anchor = ref.watch(anchorPositionProvider);
    final searchCenter = ref.watch(mapSearchCenterProvider);
    final effectiveCenter = anchor == null
        ? null
        : searchCenter ?? latLng(anchor.latitude, anchor.longitude);

    final body = anchor != null && effectiveCenter != null
        ? _PinList(
            userLatitude: anchor.latitude,
            userLongitude: anchor.longitude,
            center: effectiveCenter,
            onRefresh: () async {
              final provider = mapPinsProvider(
                MapPinsRequest(
                  center: effectiveCenter,
                  user: latLng(anchor.latitude, anchor.longitude),
                ),
              );
              ref.invalidate(provider);
              await ref.read(provider.future);
            },
          )
        : ref
              .watch(positionStreamProvider)
              .when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => e is LocationPermissionDeniedException
                    ? const _LocationDeniedView()
                    : const _ErrorView(),
                data: (_) => const Center(child: CircularProgressIndicator()),
              );

    if (embedded) return body;
    return Scaffold(
      appBar: AppBar(title: const Text('Map Notes')),
      body: body,
    );
  }
}

class _PinList extends ConsumerWidget {
  final double userLatitude;
  final double userLongitude;
  final MapLatLng center;
  final Future<void> Function() onRefresh;

  const _PinList({
    required this.userLatitude,
    required this.userLongitude,
    required this.center,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pinsAsync = ref.watch(
      mapPinsProvider(
        MapPinsRequest(
          center: center,
          user: latLng(userLatitude, userLongitude),
        ),
      ),
    );

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: pinsAsync.when(
        loading: () => const _ScrollableStatusView(
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (e, _) =>
            _ScrollableStatusView(child: Center(child: Text('Error: $e'))),
        data: (pins) {
          if (pins.isEmpty) {
            return _ScrollableStatusView(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.location_off_outlined,
                      size: 64,
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'No notes in this area.\nMove the map or drop one here!',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          final sorted = [...pins]
            ..sort((a, b) {
              final da = Geolocator.distanceBetween(
                userLatitude,
                userLongitude,
                a.latitude,
                a.longitude,
              );
              final db = Geolocator.distanceBetween(
                userLatitude,
                userLongitude,
                b.latitude,
                b.longitude,
              );
              return da.compareTo(db);
            });

          return ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            itemCount: sorted.length,
            separatorBuilder: (context, index) => const Divider(height: 1),
            itemBuilder: (context, index) {
              return _PlaceListTile(
                pin: sorted[index],
                userLatitude: userLatitude,
                userLongitude: userLongitude,
              );
            },
          );
        },
      ),
    );
  }
}

class _ScrollableStatusView extends StatelessWidget {
  final Widget child;

  const _ScrollableStatusView({required this.child});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [SizedBox(height: constraints.maxHeight, child: child)],
      ),
    );
  }
}

class _PlaceListTile extends StatelessWidget {
  final PinSummary pin;
  final double userLatitude;
  final double userLongitude;

  const _PlaceListTile({
    required this.pin,
    required this.userLatitude,
    required this.userLongitude,
  });

  @override
  Widget build(BuildContext context) {
    final color = parsePlaceColor(pin.colorHex);
    final distanceM = Geolocator.distanceBetween(
      userLatitude,
      userLongitude,
      pin.latitude,
      pin.longitude,
    );
    final distanceLabel = distanceM < 1000
        ? '${distanceM.round()} m'
        : '${(distanceM / 1000).toStringAsFixed(1)} km';

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: color,
        child: Icon(placeIconData(pin.icon), color: Colors.white, size: 20),
      ),
      title: Row(
        children: [
          if (pin.isClosed) ...[
            Icon(
              Icons.do_not_disturb_on_outlined,
              size: 14,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(width: 4),
          ] else if (pin.isPrivate) ...[
            Icon(
              Icons.lock_outline,
              size: 14,
              color: Theme.of(context).colorScheme.tertiary,
            ),
            const SizedBox(width: 4),
          ],
          Expanded(
            child: Text(
              pin.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      subtitle: pin.subtitle != null
          ? Text(pin.subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis)
          : null,
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            distanceLabel,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 2),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.chat_bubble_outline,
                size: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 2),
              Text(
                '${pin.messageCount}',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
      ),
      onTap: () => _openPin(context),
    );
  }

  Future<void> _openPin(BuildContext context) async {
    if (!pin.canOpen) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Move closer to open this note.')),
      );
      return;
    }
    final container = ProviderScope.containerOf(context, listen: false);
    try {
      await container
          .read(placeRepositoryProvider)
          .validateNoteAccess(
            placeId: pin.placeId,
            latitude: userLatitude,
            longitude: userLongitude,
          );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Move closer to open this note: $e')),
      );
      return;
    }
    if (!context.mounted) return;
    context.push(
      '/note/${pin.placeId}?title=${Uri.encodeComponent(pin.title)}',
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.error_outline,
            size: 48,
            color: Theme.of(context).colorScheme.error,
          ),
          const SizedBox(height: 12),
          const Text('Failed to load location.'),
        ],
      ),
    );
  }
}

class _LocationDeniedView extends StatelessWidget {
  const _LocationDeniedView();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.location_disabled_outlined,
            size: 48,
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
          const SizedBox(height: 12),
          Text(
            'Location unavailable.',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 4),
          Text(
            'Allow location access in Settings,\nor move to an area with better GPS signal.',
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
