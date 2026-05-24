import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:geolocator/geolocator.dart';

import '../../../config/app_config.dart';
import '../../../core/utils/place_icon.dart';
import '../../../domain/entities/place_entity.dart';
import '../../../services/location_service.dart';
import '../../providers/providers.dart';

class PlaceListScreen extends ConsumerWidget {
  const PlaceListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final anchor = ref.watch(anchorPositionProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Nearby Notes')),
      body: anchor != null
          ? _PlaceList(
              latitude: anchor.latitude,
              longitude: anchor.longitude,
              onRefresh: () async {
                final provider = placesNearbyProvider(
                  latLng(anchor.latitude, anchor.longitude),
                );
                ref.invalidate(provider);
                await ref.read(provider.future);
              },
            )
          : ref.watch(positionStreamProvider).when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => e is LocationPermissionDeniedException
                  ? const _LocationDeniedView()
                  : const _ErrorView(),
              data: (_) => const Center(child: CircularProgressIndicator()),
            ),
    );
  }
}

class _PlaceList extends ConsumerWidget {
  final double latitude;
  final double longitude;
  final Future<void> Function() onRefresh;

  const _PlaceList({
    required this.latitude,
    required this.longitude,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final placesAsync = ref.watch(
      placesNearbyProvider(latLng(latitude, longitude)),
    );

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: placesAsync.when(
        loading: () => const _ScrollableStatusView(
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (e, _) =>
            _ScrollableStatusView(child: Center(child: Text('Error: $e'))),
        data: (places) {
          if (places.isEmpty) {
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
                      'No notes within ${AppConfig.searchRadiusKm.toInt()} km.\nDrop the first one on the map!',
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

          final sorted = [...places]
            ..sort((a, b) {
              final da = Geolocator.distanceBetween(
                latitude, longitude, a.latitude, a.longitude,
              );
              final db = Geolocator.distanceBetween(
                latitude, longitude, b.latitude, b.longitude,
              );
              return da.compareTo(db);
            });

          return ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            itemCount: sorted.length,
            separatorBuilder: (context, index) => const Divider(height: 1),
            itemBuilder: (context, index) {
              return _PlaceListTile(
                place: sorted[index],
                userLatitude: latitude,
                userLongitude: longitude,
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
        children: [
          SizedBox(height: constraints.maxHeight, child: child),
        ],
      ),
    );
  }
}

class _PlaceListTile extends StatelessWidget {
  final PlaceEntity place;
  final double userLatitude;
  final double userLongitude;

  const _PlaceListTile({
    required this.place,
    required this.userLatitude,
    required this.userLongitude,
  });

  @override
  Widget build(BuildContext context) {
    final color = parsePlaceColor(place.colorHex);
    final distanceM = Geolocator.distanceBetween(
      userLatitude,
      userLongitude,
      place.latitude,
      place.longitude,
    );
    final distanceLabel = distanceM < 1000
        ? '${distanceM.round()} m'
        : '${(distanceM / 1000).toStringAsFixed(1)} km';

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: color,
        child: Icon(placeIconData(place.icon), color: Colors.white, size: 20),
      ),
      title: Text(place.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: place.subtitle != null
          ? Text(place.subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis)
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
                '${place.messageCount}',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
      ),
      onTap: () => context.push(
        '/note/${place.id}?title=${Uri.encodeComponent(place.title)}',
      ),
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
