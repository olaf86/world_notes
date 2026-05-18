import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/map_style.dart';
import '../../providers/providers.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentStyle = ref.watch(mapStyleProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Map Style',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 12),
          ...MapStyle.values.map(
            (style) => _MapStyleTile(
              style: style,
              isSelected: style == currentStyle,
              onTap: () => ref.read(mapStyleProvider.notifier).setStyle(style),
            ),
          ),
        ],
      ),
    );
  }
}

class _MapStyleTile extends StatelessWidget {
  final MapStyle style;
  final bool isSelected;
  final VoidCallback onTap;

  const _MapStyleTile({
    required this.style,
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
                          style.label,
                          style: Theme.of(context)
                              .textTheme
                              .titleSmall
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      style.description,
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
                    : Icon(Icons.circle_outlined,
                        color: colorScheme.outlineVariant),
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
    return CustomPaint(
      painter: _PreviewPainter(style),
    );
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
