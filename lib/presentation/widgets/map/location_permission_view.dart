import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../../../l10n/app_localizations.dart';

/// Full-screen placeholder shown when the position stream errors with a
/// permission-denied state. Offers a retry button (re-runs the request flow)
/// or, if denial is permanent, an "Open Settings" deep link.
class LocationPermissionView extends StatelessWidget {
  final bool permanentlyDenied;
  final VoidCallback onRetry;

  const LocationPermissionView({
    super.key,
    required this.permanentlyDenied,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
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
                  l10n.locationPermissionTitle,
                  style: Theme.of(context).textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  l10n.locationPermissionMessage,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                if (permanentlyDenied)
                  FilledButton.icon(
                    onPressed: Geolocator.openAppSettings,
                    icon: const Icon(Icons.settings_outlined),
                    label: Text(l10n.locationPermissionOpenSettings),
                  )
                else
                  FilledButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.location_on_outlined),
                    label: Text(l10n.locationPermissionOpenSettings),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
