import 'package:flutter/material.dart';

import '../place/place_list_screen.dart';
import 'map_screen.dart';

class NearbyScreen extends StatefulWidget {
  const NearbyScreen({super.key});

  @override
  State<NearbyScreen> createState() => _NearbyScreenState();
}

class _NearbyScreenState extends State<NearbyScreen> {
  var _showList = false;

  @override
  Widget build(BuildContext context) {
    if (_showList) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Nearby Notes'),
          actions: [
            IconButton(
              tooltip: 'Map',
              icon: const Icon(Icons.map_outlined),
              onPressed: () => setState(() => _showList = false),
            ),
          ],
        ),
        body: const PlaceListScreen(embedded: true),
      );
    }

    return Stack(
      children: [
        const MapScreen(),
        Positioned(
          top: MediaQuery.paddingOf(context).top + 12,
          left: 12,
          child: Material(
            elevation: 2,
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(24),
            child: IconButton(
              tooltip: 'List',
              icon: const Icon(Icons.list_alt_outlined),
              color: Theme.of(context).colorScheme.primary,
              onPressed: () => setState(() => _showList = true),
            ),
          ),
        ),
      ],
    );
  }
}
