import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../../../l10n/app_localizations.dart';
import '../../../services/location_service.dart';

/// Full-screen placeholder shown when the position stream errors with a
/// location availability issue.
class LocationPermissionView extends StatelessWidget {
  final LocationAvailabilityIssue issue;
  final VoidCallback onRetry;

  const LocationPermissionView({
    super.key,
    required this.issue,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final content = _contentFor(l10n);
    return Scaffold(
      backgroundColor: colorScheme.surfaceContainerLow,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.location_off_outlined,
                  size: 72,
                  color: colorScheme.primary,
                ),
                const SizedBox(height: 24),
                Text(
                  content.title,
                  style: Theme.of(context).textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  content.message,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                FilledButton.icon(
                  onPressed: content.onPressed,
                  icon: Icon(content.icon),
                  label: Text(content.actionLabel),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  _LocationUnavailableContent _contentFor(AppLocalizations l10n) {
    return switch (issue) {
      LocationAvailabilityIssue.permissionDenied => _LocationUnavailableContent(
        title: l10n.locationPermissionTitle,
        message: l10n.locationPermissionMessage,
        actionLabel: l10n.locationPermissionAllow,
        icon: Icons.location_on_outlined,
        onPressed: onRetry,
      ),
      LocationAvailabilityIssue.permissionPermanentlyDenied =>
        _LocationUnavailableContent(
          title: l10n.locationPermissionTitle,
          message: l10n.locationPermissionMessage,
          actionLabel: l10n.locationPermissionOpenSettings,
          icon: Icons.settings_outlined,
          onPressed: Geolocator.openAppSettings,
        ),
      LocationAvailabilityIssue.serviceDisabled => _LocationUnavailableContent(
        title: l10n.locationServiceDisabledTitle,
        message: l10n.locationServiceDisabledMessage,
        actionLabel: l10n.locationServiceOpenSettings,
        icon: Icons.settings_outlined,
        onPressed: Geolocator.openLocationSettings,
      ),
    };
  }
}

class _LocationUnavailableContent {
  final String title;
  final String message;
  final String actionLabel;
  final IconData icon;
  final VoidCallback onPressed;

  const _LocationUnavailableContent({
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.icon,
    required this.onPressed,
  });
}
