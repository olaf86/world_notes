import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/providers.dart';
import 'map_notes_list_screen.dart';
import 'map_screen.dart';

class MapNotesScreen extends StatefulWidget {
  const MapNotesScreen({super.key});

  @override
  State<MapNotesScreen> createState() => _MapNotesScreenState();
}

class _MapNotesScreenState extends State<MapNotesScreen> {
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
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not refresh map notes: $e')),
          );
        }
      }
    }

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Map',
          icon: const Icon(Icons.map_outlined),
          onPressed: onShowMap,
        ),
        title: const Text('Map Notes'),
        actions: [
          IconButton(
            tooltip: 'Refresh map notes',
            icon: const Icon(Icons.refresh_outlined),
            onPressed: anchor == null ? null : refresh,
          ),
        ],
      ),
      body: const MapNotesListScreen(embedded: true),
    );
  }
}
