import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/entities/note_list_sort.dart';
import '../../../l10n/l10n.dart';
import '../../providers/providers.dart';
import '../../widgets/note/note_sort_button.dart';
import 'map_notes_error_messages.dart';
import 'map_notes_list_screen.dart';
import 'map_screen.dart';

class MapNotesScreen extends ConsumerStatefulWidget {
  const MapNotesScreen({super.key});

  @override
  ConsumerState<MapNotesScreen> createState() => _MapNotesScreenState();
}

class _MapNotesScreenState extends ConsumerState<MapNotesScreen> {
  late final PageController _pageController;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _showMap() => _animateToPage(0);

  Future<void> _showMapNotes() => _animateToPage(1);

  Future<void> _animateToPage(int page) {
    return _pageController.animateToPage(
      page,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    // Watching here creates and preloads the ad while the user browses the
    // map, well before an eligible note-open action occurs.
    ref.watch(noteOpenInterstitialGateProvider);
    return PageView(
      controller: _pageController,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        _MapEntry(onShowList: _showMapNotes),
        _MapNotesList(onShowMap: _showMap),
      ],
    );
  }
}

class _MapEntry extends StatelessWidget {
  final VoidCallback onShowList;

  const _MapEntry({required this.onShowList});

  @override
  Widget build(BuildContext context) {
    return MapScreen(onShowList: onShowList);
  }
}

class _MapNotesList extends ConsumerWidget {
  final VoidCallback onShowMap;

  const _MapNotesList({required this.onShowMap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final anchor = ref.watch(anchorPositionProvider);
    final sort = ref.watch(mapNotesSortProvider);

    Future<void> refresh() async {
      if (anchor == null) return;
      final center =
          ref.read(mapSearchCenterProvider) ??
          latLng(anchor.latitude, anchor.longitude);
      final radiusKm = ref.read(mapSearchRadiusKmProvider);
      final provider = mapPinsProvider(
        MapPinsRequest(
          center: center,
          user: latLng(anchor.latitude, anchor.longitude),
          radiusKm: radiusKm,
        ),
      );
      ref.invalidate(provider);
      try {
        await ref.read(provider.future);
      } catch (error, stack) {
        await reportMapNotesError(
          crashlytics: ref.read(firebaseCrashlyticsProvider),
          operation: 'refresh list pins',
          error: error,
          stack: stack,
        );
        if (context.mounted) {
          showMapNotesRefreshErrorSnackBar(context);
        }
      }
    }

    return Semantics(
      identifier: 'screen-map-notes-list',
      child: Scaffold(
        appBar: AppBar(
          leading: Semantics(
            identifier: 'action-show-map',
            button: true,
            child: IconButton(
              tooltip: 'Map',
              icon: const Icon(Icons.map_outlined),
              onPressed: onShowMap,
            ),
          ),
          title: Text(context.l10n.mapNotesTitle),
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
            Semantics(
              identifier: 'action-refresh-map-notes-list',
              button: true,
              child: IconButton(
                tooltip: 'Refresh map notes',
                icon: const Icon(Icons.refresh_outlined),
                onPressed: anchor == null ? null : refresh,
              ),
            ),
          ],
        ),
        body: const MapNotesListScreen(embedded: true),
      ),
    );
  }
}
