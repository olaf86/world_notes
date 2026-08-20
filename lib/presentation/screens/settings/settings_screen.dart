import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/map_style.dart';
import '../../../config/world_catalog.dart';
import '../../../l10n/app_locale.dart';
import '../../../l10n/l10n.dart';
import '../../../l10n/presentation_labels.dart';
import '../../providers/providers.dart';
import '../../world_labels.dart';
import '../../widgets/my_notes_notification_controls.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final usesAppleMaps = MapStyle.usesAppleMaps;
    final styles = MapStyle.availableForCurrentPlatform;
    final currentStyle = ref
        .watch(mapStyleProvider)
        .effectiveForCurrentPlatform;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const _LanguageSection(),
          const SizedBox(height: 24),
          const _ContentWorldSection(),
          const SizedBox(height: 24),
          Text(
            l10n.settingsMapStyleTitle,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          ...styles.map(
            (style) => _MapStyleTile(
              style: style,
              usesAppleMaps: usesAppleMaps,
              isSelected: style == currentStyle,
              onTap: () => ref.read(mapStyleProvider.notifier).setStyle(style),
            ),
          ),
          const SizedBox(height: 24),
          const _MyNotesNotificationsSection(),
          const SizedBox(height: 24),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.block_outlined),
            title: Text(l10n.blockedUsersTitle),
            subtitle: Text(l10n.blockedUsersDescription),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/settings/blocked-users'),
          ),
          const _AdPrivacySection(),
        ],
      ),
    );
  }
}

class _ContentWorldSection extends ConsumerStatefulWidget {
  const _ContentWorldSection();

  @override
  ConsumerState<_ContentWorldSection> createState() =>
      _ContentWorldSectionState();
}

class _ContentWorldSectionState extends ConsumerState<_ContentWorldSection> {
  bool _switching = false;

  Future<void> _showWorldPicker() async {
    if (_switching) return;
    final catalog = ref.read(worldCatalogProvider);
    final selectedWorld = ref.read(selectedWorldProvider);
    final worlds = catalog.worlds
        .where((world) => world.contentAccessEnabled)
        .toList(growable: false);
    final nextWorld = await showModalBottomSheet<WorldId>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) {
        final l10n = sheetContext.l10n;
        return SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                  child: Text(
                    l10n.settingsContentWorldTitle,
                    style: Theme.of(sheetContext).textTheme.titleLarge,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
                  child: Text(l10n.settingsContentWorldDescription),
                ),
                RadioGroup<WorldId>(
                  groupValue: selectedWorld,
                  onChanged: (value) {
                    if (value != null) Navigator.pop(sheetContext, value);
                  },
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final world in worlds)
                        RadioListTile<WorldId>(
                          value: WorldId(world.worldId),
                          title: Text(localizedWorldName(l10n, world)),
                          subtitle: Text(localizedWorldLocation(l10n, world)),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (nextWorld == null || nextWorld == selectedWorld) return;

    setState(() => _switching = true);
    try {
      await ref.read(selectedWorldProvider.notifier).selectWorld(nextWorld);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.settingsContentWorldSwitchFailed)),
      );
    } finally {
      if (mounted) setState(() => _switching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final selectedWorld = ref.watch(selectedWorldProvider);
    final world = ref
        .watch(worldCatalogProvider)
        .requireContentWorld(selectedWorld);

    return ListTile(
      key: const ValueKey('content-world-setting-tile'),
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.public_outlined),
      title: Text(
        l10n.settingsContentWorldTitle,
        style: Theme.of(
          context,
        ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
      ),
      subtitle: Text(
        '${localizedWorldName(l10n, world)} · '
        '${localizedWorldLocation(l10n, world)}',
      ),
      trailing: _switching
          ? const SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.chevron_right),
      onTap: _switching ? null : _showWorldPicker,
    );
  }
}

class _AdPrivacySection extends ConsumerStatefulWidget {
  const _AdPrivacySection();

  @override
  ConsumerState<_AdPrivacySection> createState() => _AdPrivacySectionState();
}

class _AdPrivacySectionState extends ConsumerState<_AdPrivacySection> {
  bool _opening = false;

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(adPrivacyStatusProvider).valueOrNull;
    if (status?.privacyOptionsRequired != true) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Ad Privacy',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.privacy_tip_outlined),
            title: const Text('Manage privacy choices'),
            subtitle: const Text(
              'Review or change how your information is used for ads.',
            ),
            trailing: _opening
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.chevron_right),
            onTap: _opening ? null : _showPrivacyOptions,
          ),
        ],
      ),
    );
  }

  Future<void> _showPrivacyOptions() async {
    setState(() => _opening = true);
    try {
      await ref.read(adPrivacyServiceProvider).showPrivacyOptions();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open privacy choices: $error')),
      );
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }
}

class _MyNotesNotificationsSection extends StatelessWidget {
  const _MyNotesNotificationsSection();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.l10n.settingsNotificationsTitle,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        const MyNotesNotificationSwitchTile(),
        const MyNotesNotificationPreviewSwitchTile(),
      ],
    );
  }
}

class _LanguageSection extends ConsumerStatefulWidget {
  const _LanguageSection();

  @override
  ConsumerState<_LanguageSection> createState() => _LanguageSectionState();
}

class _LanguageSectionState extends ConsumerState<_LanguageSection> {
  bool _updating = false;

  Future<void> _showLanguagePicker() async {
    if (_updating) return;
    final selected = ref.read(appLanguagePreferenceProvider);
    final preference = await showModalBottomSheet<AppLanguagePreference>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) {
        final l10n = sheetContext.l10n;
        return SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                  child: Text(
                    l10n.settingsLanguageTitle,
                    style: Theme.of(sheetContext).textTheme.titleLarge,
                  ),
                ),
                RadioGroup<AppLanguagePreference>(
                  groupValue: selected,
                  onChanged: (value) {
                    if (value != null) Navigator.pop(sheetContext, value);
                  },
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: AppLanguagePreference.values.map((preference) {
                      final description = preference.localizedDescription(l10n);
                      return RadioListTile<AppLanguagePreference>(
                        value: preference,
                        title: Text(preference.localizedLabel(l10n)),
                        subtitle: description == null
                            ? null
                            : Text(description),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    await _setPreference(preference);
  }

  Future<void> _setPreference(AppLanguagePreference? preference) async {
    if (_updating || preference == null) return;
    setState(() => _updating = true);
    try {
      await ref
          .read(appLanguagePreferenceProvider.notifier)
          .setPreference(preference);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.settingsLanguageUpdateFailed)),
        );
      }
    } finally {
      if (mounted) setState(() => _updating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final selected = ref.watch(appLanguagePreferenceProvider);

    return ListTile(
      key: const ValueKey('language-setting-tile'),
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.language_outlined),
      title: Text(
        l10n.settingsLanguageTitle,
        style: Theme.of(
          context,
        ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
      ),
      subtitle: Text(selected.localizedLabel(l10n)),
      trailing: _updating
          ? const SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.chevron_right),
      onTap: _updating ? null : _showLanguagePicker,
    );
  }
}

class _MapStyleTile extends StatelessWidget {
  final MapStyle style;
  final bool usesAppleMaps;
  final bool isSelected;
  final VoidCallback onTap;

  const _MapStyleTile({
    required this.style,
    required this.usesAppleMaps,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected
                  ? colorScheme.primary
                  : colorScheme.outlineVariant,
              width: isSelected ? 2 : 1,
            ),
            color: isSelected
                ? colorScheme.primaryContainer.withAlpha(60)
                : colorScheme.surface,
          ),
          child: Row(
            children: [
              // Colour swatch preview
              ClipRRect(
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(11),
                  bottomLeft: Radius.circular(11),
                ),
                child: SizedBox(
                  width: 72,
                  height: 72,
                  child: _StylePreview(style: style),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(style.icon, size: 18, color: colorScheme.primary),
                        const SizedBox(width: 6),
                        Text(
                          _localizedMapStyleLabel(
                            l10n,
                            style,
                            usesAppleMaps: usesAppleMaps,
                          ),
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _localizedMapStyleDescription(
                        l10n,
                        style,
                        usesAppleMaps: usesAppleMaps,
                      ),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: isSelected
                    ? Icon(Icons.check_circle, color: colorScheme.primary)
                    : Icon(
                        Icons.circle_outlined,
                        color: colorScheme.outlineVariant,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _localizedMapStyleLabel(
  AppLocalizations l10n,
  MapStyle style, {
  required bool usesAppleMaps,
}) => switch (style) {
  MapStyle.auto => l10n.settingsMapStyleAuto,
  MapStyle.standard =>
    usesAppleMaps ? l10n.settingsMapStyleLight : l10n.settingsMapStyleStandard,
  MapStyle.dark => l10n.settingsMapStyleDark,
  MapStyle.pop => l10n.settingsMapStylePop,
};

String _localizedMapStyleDescription(
  AppLocalizations l10n,
  MapStyle style, {
  required bool usesAppleMaps,
}) => switch (style) {
  MapStyle.auto => l10n.settingsMapStyleAutoDescription,
  MapStyle.standard =>
    usesAppleMaps
        ? l10n.settingsMapStyleLightDescription
        : l10n.settingsMapStyleStandardDescription,
  MapStyle.dark => l10n.settingsMapStyleDarkDescription,
  MapStyle.pop => l10n.settingsMapStylePopDescription,
};

/// Simple painted preview that mimics the map's colour palette.
class _StylePreview extends StatelessWidget {
  final MapStyle style;
  const _StylePreview({required this.style});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _PreviewPainter(style));
  }
}

class _PreviewPainter extends CustomPainter {
  final MapStyle style;
  const _PreviewPainter(this.style);

  @override
  void paint(Canvas canvas, Size size) {
    // Background (land)
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = style.previewColor,
    );

    // Simulated road stripes
    final roadColor = switch (style) {
      MapStyle.auto => const Color(0xFFFFFFFF),
      MapStyle.standard => const Color(0xFFFFFFFF),
      MapStyle.dark => const Color(0xFF4A4A5E),
      MapStyle.pop => const Color(0xFFFFFFFF),
    };
    final roadPaint = Paint()
      ..color = roadColor
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(
      Offset(size.width * 0.15, size.height * 0.7),
      Offset(size.width * 0.85, size.height * 0.3),
      roadPaint,
    );
    canvas.drawLine(
      Offset(size.width * 0.1, size.height * 0.4),
      Offset(size.width * 0.6, size.height * 0.8),
      roadPaint..strokeWidth = 2,
    );

    // Simulated water patch
    final waterColor = switch (style) {
      MapStyle.auto => const Color(0xFFA9D2EA),
      MapStyle.standard => const Color(0xFFBFD8E8),
      MapStyle.dark => const Color(0xFF1A3040),
      MapStyle.pop => const Color(0xFF90CAF9),
    };
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(size.width * 0.75, size.height * 0.25),
        width: size.width * 0.35,
        height: size.height * 0.28,
      ),
      Paint()..color = waterColor,
    );

    // Pin dot
    final pinColor = switch (style) {
      MapStyle.auto => const Color(0xFFE53935),
      MapStyle.standard => const Color(0xFFE53935),
      MapStyle.dark => const Color(0xFFEF9A9A),
      MapStyle.pop => const Color(0xFFE53935),
    };
    canvas.drawCircle(
      Offset(size.width * 0.45, size.height * 0.55),
      5,
      Paint()..color = pinColor,
    );
  }

  @override
  bool shouldRepaint(_PreviewPainter old) => old.style != style;
}
