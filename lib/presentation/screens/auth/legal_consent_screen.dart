import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../config/app_config.dart';
import '../../../l10n/l10n.dart';
import '../../providers/providers.dart';
import '../../utils/legal_document_launcher.dart';
import '../../widgets/app_language_picker.dart';

class LegalConsentScreen extends ConsumerStatefulWidget {
  const LegalConsentScreen({super.key, this.continuation});

  final String? continuation;

  @override
  ConsumerState<LegalConsentScreen> createState() => _LegalConsentScreenState();
}

class _LegalConsentScreenState extends ConsumerState<LegalConsentScreen> {
  bool _agreed = false;
  bool _submitting = false;
  bool _failed = false;

  Future<void> _accept() async {
    if (!_agreed || _submitting) return;
    setState(() {
      _submitting = true;
      _failed = false;
    });
    try {
      final user = ref.read(authStateProvider).valueOrNull;
      if (user == null) throw StateError('Authentication is required.');
      await ref
          .read(legalAcceptanceRepositoryProvider)
          .acceptCurrent(
            userId: user.id,
            locale: Localizations.localeOf(context).toLanguageTag(),
          );
      ref.invalidate(legalAcceptanceProvider);
      final acceptance = await ref.read(legalAcceptanceProvider.future);
      final accepted = acceptance?.matches(
        serviceTermsVersion: AppConfig.currentServiceTermsVersion,
        privacyPolicyVersion: AppConfig.currentPrivacyPolicyVersion,
      );
      if (accepted != true) {
        throw StateError('Legal acceptance was not persisted.');
      }
      if (!mounted) return;
      final destination = widget.continuation;
      context.go(
        destination != null && destination.startsWith('/')
            ? destination
            : '/map',
      );
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _signOut() async {
    if (_submitting) return;
    await ref.read(authRepositoryProvider).signOut();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final acceptance = ref.watch(legalAcceptanceProvider);
    if (acceptance.isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Semantics(
      identifier: 'screen-legal-consent',
      child: Scaffold(
        appBar: AppBar(
          actions: const [AppLanguagePickerButton(showSelectedLanguage: false)],
        ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
                children: [
                  Icon(
                    Icons.handshake_outlined,
                    size: 56,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    l10n.legalConsentTitle,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    l10n.legalConsentIntro,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 24),
                  _LegalHighlight(
                    icon: Icons.people_outline,
                    text: l10n.legalConsentCommunityHighlight,
                  ),
                  _LegalHighlight(
                    icon: Icons.location_on_outlined,
                    text: l10n.legalConsentLocationHighlight,
                  ),
                  _LegalHighlight(
                    icon: Icons.shield_outlined,
                    text: l10n.legalConsentModerationHighlight,
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 4,
                    children: [
                      TextButton(
                        onPressed: () => openLegalDocument(
                          context,
                          AppConfig.serviceTermsUrl,
                        ),
                        child: Text(l10n.serviceTerms),
                      ),
                      TextButton(
                        onPressed: () => openLegalDocument(
                          context,
                          AppConfig.privacyPolicyUrl,
                        ),
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
                  CheckboxListTile(
                    key: const ValueKey('legal-consent-checkbox'),
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: _agreed,
                    onChanged: _submitting
                        ? null
                        : (value) => setState(() => _agreed = value ?? false),
                    title: Text(l10n.legalConsentAgreement),
                  ),
                  if (acceptance.hasError || _failed) ...[
                    const SizedBox(height: 8),
                    Text(
                      l10n.legalConsentSubmitFailed,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Semantics(
                    identifier: 'action-accept-legal-documents',
                    child: FilledButton(
                      onPressed: _agreed && !_submitting ? _accept : null,
                      child: _submitting
                          ? const SizedBox.square(
                              dimension: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(l10n.legalConsentContinue),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _submitting ? null : _signOut,
                    child: Text(l10n.signOut),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LegalHighlight extends StatelessWidget {
  const _LegalHighlight({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 22, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}
