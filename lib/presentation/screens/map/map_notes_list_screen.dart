import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/place_icon.dart';
import '../../../domain/entities/note_list_sort.dart';
import '../../../domain/entities/pin_summary_entity.dart';
import '../../../l10n/l10n.dart';
import '../../../l10n/localized_formatters.dart';
import '../../../services/location_service.dart';
import '../../providers/providers.dart';
import '../../widgets/note/note_list_card.dart';
import '../../widgets/note/note_sort_button.dart';
import '../../widgets/note/user_avatar_badge.dart';
import 'map_notes_error_messages.dart';
import 'map_pin_display.dart';

class MapNotesListScreen extends ConsumerWidget {
  final bool embedded;

  const MapNotesListScreen({super.key, this.embedded = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final sort = ref.watch(mapNotesSortProvider);
    final anchor = ref.watch(anchorPositionProvider);
    final livePosition = ref.watch(positionStreamProvider).valueOrNull;
    final searchCenter = ref.watch(mapSearchCenterProvider);
    final searchRadiusKm = ref.watch(mapSearchRadiusKmProvider);
    final effectiveCenter = anchor == null
        ? null
        : searchCenter ?? latLng(anchor.latitude, anchor.longitude);

    final body = anchor != null && effectiveCenter != null
        ? _PinList(
            queryUserLatitude: anchor.latitude,
            queryUserLongitude: anchor.longitude,
            currentPosition: livePosition ?? anchor,
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
      appBar: AppBar(
        title: Text(l10n.mapNotesTitle),
        actions: [
          NoteSortButton(
            selected: sort,
            provider: mapNotesSortProvider,
            options: const [
              NoteListSort.distance,
              NoteListSort.lastActivity,
              NoteListSort.mostLiked,
              NoteListSort.newest,
              NoteListSort.expiresSoonest,
            ],
            semanticIdentifier: 'action-sort-map-notes',
          ),
        ],
      ),
      body: body,
    );
  }
}

class _PinList extends ConsumerStatefulWidget {
  final double queryUserLatitude;
  final double queryUserLongitude;
  final Position currentPosition;
  final MapLatLng center;
  final double radiusKm;
  final Future<void> Function() onRefresh;

  const _PinList({
    required this.queryUserLatitude,
    required this.queryUserLongitude,
    required this.currentPosition,
    required this.center,
    required this.radiusKm,
    required this.onRefresh,
  });

  @override
  ConsumerState<_PinList> createState() => _PinListState();
}

class _PinListState extends ConsumerState<_PinList> {
  List<PinSummary>? _sourcePins;
  List<String> _orderedPlaceIds = const [];
  NoteListSort? _sort;

  @override
  void didUpdateWidget(covariant _PinList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.center != widget.center ||
        oldWidget.queryUserLatitude != widget.queryUserLatitude ||
        oldWidget.queryUserLongitude != widget.queryUserLongitude ||
        oldWidget.radiusKm != widget.radiusKm) {
      _sourcePins = null;
      _orderedPlaceIds = const [];
      _sort = null;
    }
  }

  List<MapPinDisplay> _orderedPins({
    required List<PinSummary> sourcePins,
    required List<MapPinDisplay> currentPins,
    required NoteListSort sort,
  }) {
    // Location changes are intentionally excluded here: they update each
    // pin's distance and access affordance, not the scroll position. Re-sort
    // only when data is fetched again or the user selects a different sort.
    if (!identical(_sourcePins, sourcePins) || _sort != sort) {
      _orderedPlaceIds = sortNoteList(
        currentPins,
        sort: sort,
        createdAt: (display) => display.pin.createdAt,
        lastActivityAt: (display) => display.pin.lastActivityAt,
        expiresAt: (display) => display.pin.expiresAt,
        likeCount: (display) => display.pin.likeCount,
        id: (display) => display.pin.placeId,
        distance: (display) => display.distanceMeters!,
      ).map((display) => display.pin.placeId).toList(growable: false);
      _sourcePins = sourcePins;
      _sort = sort;
    }

    // Map the current live display data by id, then rebuild it in the
    // previously chosen order. Removing each item also makes the remaining
    // entries below the set of newly arrived pins.
    final displayByPlaceId = {
      for (final display in currentPins) display.pin.placeId: display,
    };
    final orderedDisplays = <MapPinDisplay>[
      for (final placeId in _orderedPlaceIds) ?displayByPlaceId.remove(placeId),
    ];
    // A defensive fallback for a source update that mutates the same list
    // instance. Normal repository responses always take the branch above.
    orderedDisplays.addAll(displayByPlaceId.values);
    return orderedDisplays;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final sort = ref.watch(mapNotesSortProvider);
    final noteAccessRadiusMeters = ref.watch(noteAccessRadiusMetersProvider);
    final request = MapPinsRequest(
      center: widget.center,
      user: latLng(widget.queryUserLatitude, widget.queryUserLongitude),
      radiusKm: widget.radiusKm,
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

    return Column(
      children: [
        NoteSortStatus(sort: sort, semanticIdentifier: 'map-notes-sort-status'),
        Expanded(
          child: RefreshIndicator(
            onRefresh: widget.onRefresh,
            child: pinsAsync.when(
              loading: () => const _ScrollableStatusView(
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) =>
                  const _ScrollableStatusView(child: _MapNotesLoadErrorView()),
              data: (pins) {
                final currentPins = [
                  for (final pin in pins)
                    MapPinDisplay.fromLivePosition(
                      pin: pin,
                      position: widget.currentPosition,
                      accessRadiusMeters: noteAccessRadiusMeters.toDouble(),
                    ),
                ];
                if (currentPins.isEmpty) {
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
                            l10n.mapNoNotes,
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                final sorted = _orderedPins(
                  sourcePins: pins,
                  currentPins: currentPins,
                  sort: sort,
                );

                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
                  physics: const AlwaysScrollableScrollPhysics(),
                  itemCount: sorted.length,
                  findItemIndexCallback: (key) {
                    if (key is! ValueKey<String>) return null;
                    final index = sorted.indexWhere(
                      (display) => display.pin.placeId == key.value,
                    );
                    return index == -1 ? null : index;
                  },
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final display = sorted[index];
                    final pin = display.pin;
                    return Semantics(
                      key: ValueKey(pin.placeId),
                      identifier: 'map-note-card-${pin.placeId}',
                      button: display.canOpen,
                      enabled: display.canOpen,
                      child: _MapNoteTile(
                        display: display,
                        request: request,
                        userLatitude: widget.currentPosition.latitude,
                        userLongitude: widget.currentPosition.longitude,
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ),
      ],
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

class _MapNoteTile extends ConsumerStatefulWidget {
  final MapPinDisplay display;
  final MapPinsRequest request;
  final double userLatitude;
  final double userLongitude;

  const _MapNoteTile({
    required this.display,
    required this.request,
    required this.userLatitude,
    required this.userLongitude,
  });

  @override
  ConsumerState<_MapNoteTile> createState() => _MapNoteTileState();
}

class _MapNoteTileState extends ConsumerState<_MapNoteTile> {
  var _isOpening = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final l10n = context.l10n;
    final display = widget.display;
    final pin = display.pin;
    final color = parsePlaceColor(pin.colorHex);
    final distanceM = display.distanceMeters!;
    final distanceLabel = distanceM < 1000
        ? l10n.mapDistanceMeters(distanceM.round())
        : l10n.mapDistanceKilometers((distanceM / 1000).toStringAsFixed(1));
    return NoteListCard(
      avatarColor: color,
      avatarIcon: placeIconData(pin.icon),
      avatarImageStoragePath: pin.pinImageStoragePath,
      themeId: pin.themeId,
      avatarBadge: UserAvatarBadge(
        name: pin.creatorName,
        photoUrl: pin.creatorPhotoUrl,
        photoVersion: pin.creatorPhotoVersion,
      ),
      title: pin.title,
      subtitle: pin.subtitle,
      titleAccessory: _AccessStatusSignal(canOpen: display.canOpen),
      metadata: [
        if (pin.isFromFollowedAuthor)
          NoteListMeta(
            icon: Icons.person_pin_circle_outlined,
            label: l10n.mapFromFollowing,
            semanticLabel: l10n.mapFromFollowingSemantic,
            color: colorScheme.tertiary,
          ),
        if (pin.hasUnseenMessages)
          NoteListMeta(
            icon: Icons.fiber_new_outlined,
            label: l10n.newMessages,
            color: colorScheme.error,
          ),
        NoteListMeta(
          icon: Icons.near_me_outlined,
          label: distanceLabel,
          color: colorScheme.primary,
        ),
        NoteListMeta(
          icon: Icons.schedule_outlined,
          label: l10n.createdAt(
            formatNoteDateTime(
              pin.createdAt,
              locale: Localizations.localeOf(context).toLanguageTag(),
            ),
          ),
        ),
        NoteListMeta(
          icon: Icons.event_outlined,
          label: l10n.expiresAt(
            formatNoteDateTime(
              pin.expiresAt,
              locale: Localizations.localeOf(context).toLanguageTag(),
            ),
          ),
        ),
        if (pin.isClosed)
          NoteListMeta(
            icon: Icons.do_not_disturb_on_outlined,
            label: l10n.noteClosed,
            color: colorScheme.error,
          )
        else if (pin.isPrivate)
          NoteListMeta(
            icon: Icons.lock_outline,
            label: l10n.notePrivate,
            color: colorScheme.tertiary,
          ),
      ],
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _SummaryCount(
            icon: Icons.chat_bubble_outline,
            count: pin.messageCount,
          ),
          const SizedBox(width: 8),
          _SummaryCount(icon: Icons.favorite_border, count: pin.likeCount),
        ],
      ),
      onTap: display.canOpen && !_isOpening ? _openPin : null,
    );
  }

  Future<void> _openPin() async {
    if (_isOpening || !widget.display.canOpen) return;
    setState(() => _isOpening = true);

    final container = ProviderScope.containerOf(context, listen: false);
    try {
      await ref
          .read(noteOpenInterstitialGateProvider)
          .beforeNoteOpen(placeId: widget.display.pin.placeId);
      if (!mounted) return;
      await context.push<void>(
        '/note/${widget.display.pin.placeId}?title=${Uri.encodeComponent(widget.display.pin.title)}',
        extra: NoteAccessValidationRequest(
          placeId: widget.display.pin.placeId,
          latitude: widget.userLatitude,
          longitude: widget.userLongitude,
        ),
      );
      if (!mounted) return;
      container.invalidate(mapPinsProvider(widget.request));
    } finally {
      if (mounted) setState(() => _isOpening = false);
    }
  }
}

class _AccessStatusSignal extends StatelessWidget {
  final bool canOpen;

  const _AccessStatusSignal({required this.canOpen});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final color = canOpen
        ? Colors.green.shade700
        : Theme.of(context).colorScheme.error;
    final label = canOpen ? l10n.noteWithinRange : l10n.noteOutsideRange;

    return Semantics(
      container: true,
      label: label,
      child: Tooltip(
        message: canOpen ? l10n.noteOpenNow : l10n.noteMoveCloser,
        excludeFromSemantics: true,
        child: ExcludeSemantics(
          child: Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(color: color.withValues(alpha: 0.55), blurRadius: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SummaryCount extends StatelessWidget {
  final IconData icon;
  final int count;

  const _SummaryCount({required this.icon, required this.count});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: colorScheme.onSurfaceVariant),
        const SizedBox(width: 3),
        Text(
          '$count',
          style: theme.textTheme.labelMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      ],
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
    final l10n = context.l10n;
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
          Text(l10n.locationLoadFailed),
        ],
      ),
    );
  }
}

class _LocationDeniedView extends StatelessWidget {
  const _LocationDeniedView();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
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
            l10n.locationUnavailable,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 4),
          Text(
            l10n.locationUnavailableHelp,
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
