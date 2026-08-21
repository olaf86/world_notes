import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../../core/utils/image_upload_util.dart';
import '../../../l10n/l10n.dart';

class PinThumbnailCropDialog extends StatefulWidget {
  final Uint8List imageBytes;

  const PinThumbnailCropDialog({super.key, required this.imageBytes});

  @override
  State<PinThumbnailCropDialog> createState() => _PinThumbnailCropDialogState();
}

class _PinThumbnailCropDialogState extends State<PinThumbnailCropDialog> {
  static const double _minScale = 1;
  static const double _maxScale = 4;

  final _previewKey = GlobalKey();
  final _transformController = TransformationController();
  bool _encoding = false;

  @override
  void dispose() {
    _transformController.dispose();
    super.dispose();
  }

  Future<void> _useCrop() async {
    if (_encoding) return;
    final l10n = context.l10n;
    setState(() => _encoding = true);
    try {
      final boundary =
          _previewKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null) return;

      final size = boundary.size;
      final pixelRatio = ImageUploadUtil.pinThumbnailDimension / size.width;
      final image = await boundary.toImage(pixelRatio: pixelRatio);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) {
        throw FormatException(l10n.thumbnailRenderFailed);
      }
      final thumbnail = await ImageUploadUtil.compressPinThumbnailToWebP(
        data.buffer.asUint8List(),
      );
      if (mounted) Navigator.pop(context, thumbnail);
    } on FormatException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.message),
          duration: const Duration(seconds: 4),
        ),
      );
    } on UnsupportedError {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.webpUnsupported),
          duration: const Duration(seconds: 4),
        ),
      );
    } finally {
      if (mounted) setState(() => _encoding = false);
    }
  }

  void _resetCrop() {
    _transformController.value = Matrix4.identity();
  }

  void _zoomBy(double factor) {
    final currentScale = _transformController.value.getMaxScaleOnAxis();
    final targetScale = (currentScale * factor)
        .clamp(_minScale, _maxScale)
        .toDouble();
    final effectiveFactor = targetScale / currentScale;
    if (effectiveFactor == 1) return;

    final box = _previewKey.currentContext?.findRenderObject() as RenderBox?;
    final focalPoint = box?.size.center(Offset.zero) ?? Offset.zero;
    final matrix = _transformController.value.clone()
      ..translateByDouble(focalPoint.dx, focalPoint.dy, 0, 1)
      ..scaleByDouble(effectiveFactor, effectiveFactor, 1, 1)
      ..translateByDouble(-focalPoint.dx, -focalPoint.dy, 0, 1);
    _transformController.value = matrix;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(l10n.mapPinImageTitle),
      contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  RepaintBoundary(
                    key: _previewKey,
                    child: ClipRect(
                      child: InteractiveViewer(
                        transformationController: _transformController,
                        minScale: _minScale,
                        maxScale: _maxScale,
                        panEnabled: true,
                        scaleEnabled: true,
                        trackpadScrollCausesScale: true,
                        child: SizedBox.expand(
                          child: Image.memory(
                            widget.imageBytes,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                    ),
                  ),
                  IgnorePointer(
                    child: CustomPaint(
                      painter: _CircularCropOverlayPainter(
                        scrimColor: theme.colorScheme.surface.withValues(
                          alpha: 0.42,
                        ),
                        borderColor: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.mapPinCropInstruction,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: l10n.zoomOut,
                  onPressed: _encoding ? null : () => _zoomBy(0.8),
                  icon: const Icon(Icons.zoom_out),
                ),
                IconButton(
                  tooltip: l10n.zoomIn,
                  onPressed: _encoding ? null : () => _zoomBy(1.25),
                  icon: const Icon(Icons.zoom_in),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _encoding ? null : _resetCrop,
          child: Text(l10n.resetAction),
        ),
        TextButton(
          onPressed: _encoding ? null : () => Navigator.pop(context),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          onPressed: _encoding ? null : _useCrop,
          child: _encoding
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(l10n.useImageAction),
        ),
      ],
    );
  }
}

class _CircularCropOverlayPainter extends CustomPainter {
  final Color scrimColor;
  final Color borderColor;

  const _CircularCropOverlayPainter({
    required this.scrimColor,
    required this.borderColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final radius = size.shortestSide / 2;
    final center = Offset(size.width / 2, size.height / 2);
    final circle = Path()
      ..addOval(Rect.fromCircle(center: center, radius: radius));
    final overlay = Path()
      ..addRect(Offset.zero & size)
      ..addPath(circle, Offset.zero)
      ..fillType = PathFillType.evenOdd;

    canvas.drawPath(overlay, Paint()..color = scrimColor);
    canvas.drawCircle(
      center,
      radius - 1,
      Paint()
        ..color = borderColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
  }

  @override
  bool shouldRepaint(covariant _CircularCropOverlayPainter oldDelegate) {
    return oldDelegate.scrimColor != scrimColor ||
        oldDelegate.borderColor != borderColor;
  }
}
