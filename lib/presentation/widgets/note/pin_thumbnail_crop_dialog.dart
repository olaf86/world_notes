import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../../core/utils/image_upload_util.dart';

class PinThumbnailCropDialog extends StatefulWidget {
  final Uint8List imageBytes;

  const PinThumbnailCropDialog({super.key, required this.imageBytes});

  @override
  State<PinThumbnailCropDialog> createState() => _PinThumbnailCropDialogState();
}

class _PinThumbnailCropDialogState extends State<PinThumbnailCropDialog> {
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
        throw const FormatException('Could not render thumbnail preview.');
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
        const SnackBar(
          content: Text('WebP encoding is not supported on this device.'),
          duration: Duration(seconds: 4),
        ),
      );
    } finally {
      if (mounted) setState(() => _encoding = false);
    }
  }

  void _resetCrop() {
    _transformController.value = Matrix4.identity();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Map pin image'),
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
                        minScale: 1,
                        maxScale: 4,
                        panEnabled: true,
                        scaleEnabled: true,
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
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Drag and pinch to choose the part shown in the pin.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _encoding ? null : _resetCrop,
          child: const Text('Reset'),
        ),
        TextButton(
          onPressed: _encoding ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _encoding ? null : _useCrop,
          child: _encoding
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Use Image'),
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
