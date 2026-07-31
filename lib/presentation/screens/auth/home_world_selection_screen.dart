import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../config/world_catalog.dart';
import '../../providers/providers.dart';

/// One-time selection of the account's immutable authority world.
class HomeWorldSelectionScreen extends ConsumerStatefulWidget {
  const HomeWorldSelectionScreen({super.key});

  @override
  ConsumerState<HomeWorldSelectionScreen> createState() =>
      _HomeWorldSelectionScreenState();
}

class _HomeWorldSelectionScreenState
    extends ConsumerState<HomeWorldSelectionScreen> {
  WorldId? _selectedWorld;
  bool _submitting = false;
  String? _error;

  Future<void> _confirm() async {
    final selectedWorld = _selectedWorld;
    if (selectedWorld == null || _submitting) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ref.read(accountBootstrapServiceProvider).assignHome(selectedWorld);
      await ref.read(firebaseAuthProvider).currentUser?.getIdToken(true);
      ref.invalidate(homeAssignmentProvider);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final assignment = ref.watch(homeAssignmentProvider);
    final worlds = ref
        .watch(worldCatalogProvider)
        .worlds
        .where((world) => world.homeAssignmentEnabled)
        .toList(growable: false);

    if (assignment.isLoading || assignment.valueOrNull != null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_selectedWorld == null && worlds.isNotEmpty) {
      _selectedWorld = WorldId(worlds.first.worldId);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Choose your home world')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              'Your home world keeps your account data close to you.',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            Text(
              'This choice cannot be changed later. You can still visit '
              'other prepared worlds without moving your home.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 24),
            RadioGroup<WorldId>(
              groupValue: _selectedWorld,
              onChanged: _submitting
                  ? (_) {}
                  : (value) => setState(() => _selectedWorld = value),
              child: Column(
                children: [
                  for (final world in worlds)
                    RadioListTile<WorldId>(
                      value: WorldId(world.worldId),
                      title: Text(_worldName(world)),
                      subtitle: Text(world.firestoreLocation),
                      enabled: !_submitting,
                    ),
                ],
              ),
            ),
            if (worlds.isEmpty)
              const Text('No home world is currently available.'),
            if (assignment.hasError || _error != null) ...[
              const SizedBox(height: 16),
              Text(
                _error ?? 'Could not load your account setup.',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _selectedWorld == null || _submitting
                  ? null
                  : _confirm,
              child: _submitting
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Set as my permanent home'),
            ),
          ],
        ),
      ),
    );
  }
}

String _worldName(WorldCatalogEntry world) {
  return switch (world.displayNameKey) {
    'world.asia' => 'Asia',
    'world.northAmerica' => 'North America',
    'world.europe' => 'Europe',
    _ => world.worldId,
  };
}
