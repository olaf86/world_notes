import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:geolocator/geolocator.dart';

import '../../../config/app_config.dart';
import '../../../domain/entities/note_entity.dart';
import '../../../services/location_service.dart';
import '../../providers/providers.dart';

class PlaceListScreen extends ConsumerWidget {
  const PlaceListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final positionAsync = ref.watch(positionStreamProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Nearby Notes')),
      body: positionAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => e is LocationPermissionDeniedException
            ? const _LocationDeniedView()
            : const _ErrorView(),
        data: (pos) =>
            _NoteBoxList(latitude: pos.latitude, longitude: pos.longitude),
      ),
    );
  }
}

class _NoteBoxList extends ConsumerWidget {
  final double latitude;
  final double longitude;

  const _NoteBoxList({required this.latitude, required this.longitude});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final noteBoxesAsync = ref.watch(
      noteBoxesProvider(latLng(latitude, longitude)),
    );

    return noteBoxesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (noteBoxes) {
        if (noteBoxes.isEmpty) {
          return Center(
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
          );
        }

        final sorted = [...noteBoxes]..sort((a, b) {
            final da = Geolocator.distanceBetween(
              latitude,
              longitude,
              a.place.latitude,
              a.place.longitude,
            );
            final db = Geolocator.distanceBetween(
              latitude,
              longitude,
              b.place.latitude,
              b.place.longitude,
            );
            return da.compareTo(db);
          });

        return ListView.separated(
          itemCount: sorted.length,
          separatorBuilder: (context, index) => const Divider(height: 1),
          itemBuilder: (context, index) {
            return _PlaceListTile(
              noteBox: sorted[index],
              userLatitude: latitude,
              userLongitude: longitude,
            );
          },
        );
      },
    );
  }
}

class _PlaceListTile extends StatelessWidget {
  final NoteBoxEntity noteBox;
  final double userLatitude;
  final double userLongitude;

  const _PlaceListTile({
    required this.noteBox,
    required this.userLatitude,
    required this.userLongitude,
  });

  @override
  Widget build(BuildContext context) {
    final place = noteBox.place;
    final note = noteBox.note;
    final color = _parseColor(place.colorHex);
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
        child: Icon(_iconData(place.icon), color: Colors.white, size: 20),
      ),
      title: Text(place.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: place.subtitle != null
          ? Text(
              place.subtitle!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            )
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
                '${note.messageCount}',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        ],
      ),
      onTap: () => context.push(
        '/note/${note.id}?title=${Uri.encodeComponent(place.title)}',
      ),
    );
  }

  Color _parseColor(String hex) {
    try {
      return Color(int.parse(hex.replaceFirst('#', '0xFF')));
    } catch (_) {
      return Colors.green;
    }
  }

  IconData _iconData(String icon) {
    return switch (icon) {
      'restaurant' => Icons.restaurant,
      'park' => Icons.park,
      'home' => Icons.home,
      'star' => Icons.star,
      'photo' => Icons.photo_camera,
      'music' => Icons.music_note,
      _ => Icons.place,
    };
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
