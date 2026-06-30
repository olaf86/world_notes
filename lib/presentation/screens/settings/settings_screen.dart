import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../config/regions.dart';
import '../../../core/map_style.dart';
import '../../../services/my_notes_notification_service.dart';
import '../../providers/providers.dart';
import '../../widgets/my_notes_notification_controls.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usesAppleMaps = MapStyle.usesAppleMaps;
    final styles = MapStyle.availableForCurrentPlatform;
    final currentStyle = ref
        .watch(mapStyleProvider)
        .effectiveForCurrentPlatform;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Map Style',
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
          const _RegionSection(),
          const SizedBox(height: 24),
          const _MyNotesNotificationsSection(),
          if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) ...[
            const SizedBox(height: 24),
            const _PushNotificationDiagnosticsSection(),
          ],
        ],
      ),
    );
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
          'Notifications',
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

class _PushNotificationDiagnosticsSection extends ConsumerWidget {
  const _PushNotificationDiagnosticsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final diagnostic = ref.watch(apnsRegistrationDiagnosticProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Push Notification Diagnostics',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            IconButton(
              tooltip: 'Refresh diagnostics',
              onPressed: () =>
                  ref.invalidate(apnsRegistrationDiagnosticProvider),
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        Text(
          'Shows whether iOS successfully registered this device with APNs. '
          'No notification token is displayed.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        diagnostic.when(
          loading: () => const LinearProgressIndicator(),
          error: (error, _) => ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.error_outline),
            title: const Text('Could not load APNs status'),
            subtitle: Text('$error'),
          ),
          data: (value) => _ApnsDiagnosticTile(diagnostic: value),
        ),
      ],
    );
  }
}

class _ApnsDiagnosticTile extends StatelessWidget {
  final ApnsRegistrationDiagnostic diagnostic;

  const _ApnsDiagnosticTile({required this.diagnostic});

  @override
  Widget build(BuildContext context) {
    final (label, icon, color) = switch (diagnostic.state) {
      ApnsRegistrationState.succeeded => (
        'Registered',
        Icons.check_circle_outline,
        Colors.green,
      ),
      ApnsRegistrationState.failed => (
        'Registration failed',
        Icons.error_outline,
        Theme.of(context).colorScheme.error,
      ),
      ApnsRegistrationState.pending => (
        'Registration pending',
        Icons.schedule,
        Colors.orange,
      ),
      ApnsRegistrationState.unknown => (
        'No registration result yet',
        Icons.help_outline,
        Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    };
    final updatedAt = diagnostic.updatedAt;
    final details = <String>[];
    if (diagnostic.message case final message?) {
      details.add(message);
    }
    if (updatedAt != null) {
      details.add(
        'Updated ${DateFormat.yMd().add_jms().format(updatedAt.toLocal())}',
      );
    }

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: color),
      title: Text(label),
      subtitle: details.isEmpty ? null : Text(details.join('\n')),
    );
  }
}

/// Data-region selector: "Auto" (nearest to your location) or a pinned region
/// for travellers. Only regions where the backend is deployed are offered.
class _RegionSection extends ConsumerWidget {
  const _RegionSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final override = ref.watch(regionPreferenceProvider);
    final effective = ref.watch(effectiveRegionProvider);
    final available = Regions.available;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Data Region',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Choose which region serves your requests. Auto picks the closest to '
          'your current location — handy to override while travelling.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),

        RadioGroup<String?>(
          groupValue: override,
          onChanged: (value) =>
              ref.read(regionPreferenceProvider.notifier).setOverride(value),
          child: Column(
            children: [
              // Auto option.
              RadioListTile<String?>(
                value: null,
                contentPadding: EdgeInsets.zero,
                title: const Text('Auto (nearest)'),
                subtitle: Text(
                  'Currently: ${Regions.byId(effective)?.label ?? effective}',
                ),
              ),

              // Explicit regions.
              ...available.map(
                (r) => RadioListTile<String?>(
                  value: r.id,
                  contentPadding: EdgeInsets.zero,
                  title: Text(r.label),
                ),
              ),
            ],
          ),
        ),
      ],
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
                          style.label(usesAppleMaps: usesAppleMaps),
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      style.description(usesAppleMaps: usesAppleMaps),
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
