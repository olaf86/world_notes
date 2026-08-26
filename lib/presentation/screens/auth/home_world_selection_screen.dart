import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../config/world_catalog.dart';
import '../../../l10n/l10n.dart';
import '../../providers/providers.dart';
import '../../world_labels.dart';
import '../../widgets/app_language_picker.dart';

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
  bool _submissionFailed = false;

  Future<void> _confirm() async {
    final selectedWorld = _selectedWorld;
    if (selectedWorld == null || _submitting) return;
    setState(() {
      _submitting = true;
      _submissionFailed = false;
    });
    try {
      final languagePreference = ref.read(appLanguagePreferenceProvider);
      await ref
          .read(accountBootstrapServiceProvider)
          .assignHome(
            selectedWorld,
            languagePreference: languagePreference.storageValue,
          );
      await ref.read(subscriptionServiceProvider).syncEntitlement();
      await ref.read(firebaseAuthProvider).currentUser?.getIdToken(true);
      ref.invalidate(homeAssignmentProvider);
    } catch (_) {
      if (mounted) setState(() => _submissionFailed = true);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
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
      appBar: AppBar(
        title: Text(l10n.homeWorldSelectionTitle),
        actions: const [AppLanguagePickerButton(showSelectedLanguage: false)],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              l10n.homeWorldSelectionIntro,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            Text(
              l10n.homeWorldSelectionPermanentWarning,
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
                      title: Text(localizedWorldName(l10n, world)),
                      subtitle: Text(localizedWorldLocation(l10n, world)),
                      enabled: !_submitting,
                    ),
                ],
              ),
            ),
            if (worlds.isEmpty) Text(l10n.homeWorldSelectionUnavailable),
            if (assignment.hasError || _submissionFailed) ...[
              const SizedBox(height: 16),
              Text(
                _submissionFailed
                    ? l10n.homeWorldSelectionSubmitFailed
                    : l10n.homeWorldSelectionLoadFailed,
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
                  : Text(l10n.homeWorldSelectionConfirm),
            ),
          ],
        ),
      ),
    );
  }
}
