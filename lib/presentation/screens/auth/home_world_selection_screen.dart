import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../config/app_config.dart';
import '../../../config/world_catalog.dart';
import '../../../l10n/l10n.dart';
import '../../../l10n/app_locale.dart';
import '../../providers/providers.dart';
import '../../utils/legal_document_launcher.dart';
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
  bool _acceptedLegalDocuments = false;

  Future<void> _confirm() async {
    final selectedWorld = _selectedWorld;
    if (selectedWorld == null || !_acceptedLegalDocuments || _submitting) {
      return;
    }
    setState(() {
      _submitting = true;
      _submissionFailed = false;
    });
    try {
      final user = ref.read(authStateProvider).valueOrNull;
      if (user == null) throw StateError('Authentication is required.');
      final languagePreference = ref.read(appLanguagePreferenceProvider);
      await ref
          .read(accountBootstrapServiceProvider)
          .assignHome(
            selectedWorld,
            languagePreference: languagePreference.storageValue,
            resolvedLocale: noticeLocaleTag(Localizations.localeOf(context)),
            legalAcceptanceLocale: Localizations.localeOf(
              context,
            ).toLanguageTag(),
          );
      await ref
          .read(legalAcceptanceRepositoryProvider)
          .rememberCurrent(user.id);
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
            const SizedBox(height: 16),
            CheckboxListTile(
              key: const ValueKey('home-world-legal-consent'),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _acceptedLegalDocuments,
              onChanged: _submitting
                  ? null
                  : (value) => setState(
                      () => _acceptedLegalDocuments = value ?? false,
                    ),
              title: Text(l10n.legalConsentAgreement),
              subtitle: Wrap(
                spacing: 4,
                runSpacing: 0,
                children: [
                  TextButton(
                    onPressed: () =>
                        openLegalDocument(context, AppConfig.serviceTermsUrl),
                    child: Text(l10n.serviceTerms),
                  ),
                  TextButton(
                    onPressed: () =>
                        openLegalDocument(context, AppConfig.privacyPolicyUrl),
                    child: Text(l10n.privacyPolicy),
                  ),
                  TextButton(
                    onPressed: () => openLegalDocument(
                      context,
                      AppConfig.appleStandardEulaUrl,
                    ),
                    child: Text(l10n.appleStandardEula),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed:
                  _selectedWorld == null ||
                      !_acceptedLegalDocuments ||
                      _submitting
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
