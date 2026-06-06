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

  void _showMap() => setState(() => _showList = false);

  void _showNearbyList() => setState(() => _showList = true);

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 260),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        final isList = child.key == const ValueKey('nearby-list');
        final offset = isList ? const Offset(1, 0) : const Offset(-1, 0);
        return SlideTransition(
          position: Tween<Offset>(begin: offset, end: Offset.zero).animate(
            CurvedAnimation(parent: animation, curve: Curves.easeInOutCubic),
          ),
          child: child,
        );
      },
      child: _showList
          ? _NearbyList(onShowMap: _showMap)
          : _MapEntry(onShowList: _showNearbyList),
    );
  }
}

class _MapEntry extends StatelessWidget {
  final VoidCallback onShowList;

  const _MapEntry({required this.onShowList});

  @override
  Widget build(BuildContext context) {
    return MapScreen(key: const ValueKey('nearby-map'), onShowList: onShowList);
  }
}

class _NearbyList extends StatelessWidget {
  final VoidCallback onShowMap;

  const _NearbyList({required this.onShowMap});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const ValueKey('nearby-list'),
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Map',
          icon: const Icon(Icons.map_outlined),
          onPressed: onShowMap,
        ),
        title: const Text('Nearby Notes'),
      ),
      body: const PlaceListScreen(embedded: true),
    );
  }
}
