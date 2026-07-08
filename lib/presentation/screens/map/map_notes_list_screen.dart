import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/time_format.dart';
import '../../../core/utils/place_icon.dart';
import '../../../domain/entities/pin_summary_entity.dart';
import '../../../services/location_service.dart';
import '../../providers/providers.dart';
import '../../widgets/note/note_list_card.dart';
import 'map_notes_error_messages.dart';

class MapNotesListScreen extends ConsumerWidget {
  final bool embedded;

  const MapNotesListScreen({super.key, this.embedded = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final anchor = ref.watch(anchorPositionProvider);
    final searchCenter = ref.watch(mapSearchCenterProvider);
    final searchRadiusKm = ref.watch(mapSearchRadiusKmProvider);
    final effectiveCenter = anchor == null
        ? null
        : searchCenter ?? latLng(anchor.latitude, anchor.longitude);

    final body = anchor != null && effectiveCenter != null
        ? _PinList(
            userLatitude: anchor.latitude,
            userLongitude: anchor.longitude,
            center: effectiveCenter,
            radiusKm: searchRadiusKm,
            onRefresh: () async {
              final provider = mapPinsProvider(
                MapPinsRequest(
                  center: effectiveCenter,
                  user: latLng(anchor.latitude, anchor.longitude),
                  radiusKm: searchRadiusKm,
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
  final double radiusKm;
  final Future<void> Function() onRefresh;

  const _PinList({
    required this.userLatitude,
    required this.userLongitude,
    required this.center,
    required this.radiusKm,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final request = MapPinsRequest(
      center: center,
      user: latLng(userLatitude, userLongitude),
      radiusKm: radiusKm,
    );
    final provider = mapPinsProvider(request);
    ref.listen<AsyncValue<List<PinSummary>>>(provider, (_, next) {
      if (!next.hasError || next.isLoading) return;
      final error = next.error;
      final stack = next.stackTrace;
      if (error == null || stack == null) return;
      unawaited(
        reportMapNotesError(
          crashlytics: ref.read(firebaseCrashlyticsProvider),
          operation: 'load list pins',
          error: error,
          stack: stack,
        ),
      );
    });
    final pinsAsync = ref.watch(provider);

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: pinsAsync.when(
        loading: () => const _ScrollableStatusView(
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (e, _) =>
            const _ScrollableStatusView(child: _MapNotesLoadErrorView()),
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
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
            physics: const AlwaysScrollableScrollPhysics(),
            itemCount: sorted.length,
            separatorBuilder: (context, index) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              return _MapNoteTile(
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

class _MapNoteTile extends StatelessWidget {
  final PinSummary pin;
  final double userLatitude;
  final double userLongitude;

  const _MapNoteTile({
    required this.pin,
    required this.userLatitude,
    required this.userLongitude,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final color = parsePlaceColor(pin.colorHex);
    final distanceM = Geolocator.distanceBetween(
      userLatitude,
      userLongitude,
      pin.latitude,
      pin.longitude,
    );
    final distanceLabel = distanceM < 1000
        ? '${distanceM.round()} meters away'
        : '${(distanceM / 1000).toStringAsFixed(1)} km away';
    return NoteListCard(
      avatarColor: color,
      avatarIcon: placeIconData(pin.icon),
      avatarImageStoragePath: pin.pinImageStoragePath,
      title: pin.title,
      subtitle: pin.subtitle,
      metadata: [
        NoteListMeta(
          icon: Icons.near_me_outlined,
          label: distanceLabel,
          color: colorScheme.primary,
        ),
        NoteListMeta(
          icon: Icons.schedule_outlined,
          label: 'Created ${noteDateTimeLabel(pin.createdAt)}',
        ),
        NoteListMeta(
          icon: Icons.event_outlined,
          label: 'Expires ${noteDateTimeLabel(pin.expiresAt)}',
        ),
        if (pin.isClosed)
          NoteListMeta(
            icon: Icons.do_not_disturb_on_outlined,
            label: 'Closed',
            color: colorScheme.error,
          )
        else if (pin.isPrivate)
          NoteListMeta(
            icon: Icons.lock_outline,
            label: 'Private',
            color: colorScheme.tertiary,
          ),
      ],
      trailing: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.chat_bubble_outline,
            size: 14,
            color: colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 2),
          Text(
            '${pin.messageCount}',
            style: theme.textTheme.labelMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
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
    } catch (error, stack) {
      await reportMapNotesError(
        crashlytics: container.read(firebaseCrashlyticsProvider),
        operation: 'open list pin',
        error: error,
        stack: stack,
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text(mapNoteOpenErrorMessage)));
      return;
    }
    if (!context.mounted) return;
    context.push(
      '/note/${pin.placeId}?title=${Uri.encodeComponent(pin.title)}',
    );
  }
}

class _MapNotesLoadErrorView extends StatelessWidget {
  const _MapNotesLoadErrorView();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, size: 48, color: theme.colorScheme.error),
          const SizedBox(height: 12),
          Text(
            mapNotesLoadErrorMessage,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
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
