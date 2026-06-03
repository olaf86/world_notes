import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Renders a teardrop-style map marker (colored pin with a white icon glyph)
/// to a PNG byte array suitable for [MapLibreMapController.addImage].
///
/// Stadia Maps' default sprite sheet doesn't ship a generic "marker" icon,
/// so we build our own per (icon, color) combination and register it with
/// the map controller on demand.
class MarkerImage {
  /// Bitmap dimensions (device pixels). High-DPI so the result stays crisp
  /// when MapLibre scales via [SymbolOptions.iconSize].
  static const double _width = 96;
  static const double _height = 120;
  static const double _circleRadius = 36;
  static const double _circleCenterY = 40;
  static const double _tipY = 112;
  static const double _iconSize = 36;

  static Future<Uint8List> render({
    required IconData iconData,
    required Color color,
    double scale = 1.0,
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.scale(scale);

    final center = Offset(_width / 2, _circleCenterY);

    // Drop shadow under the pin.
    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.25)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
    canvas.drawCircle(center.translate(0, 3), _circleRadius, shadowPaint);

    // Pin tail (curved triangle ending at the tip).
    final tailPath = Path()
      ..moveTo(center.dx - 16, center.dy + _circleRadius - 8)
      ..quadraticBezierTo(
        center.dx,
        _tipY + 12,
        center.dx + 16,
        center.dy + _circleRadius - 8,
      )
      ..close();
    final fillPaint = Paint()..color = color;
    canvas.drawPath(tailPath, fillPaint);

    // Head circle.
    canvas.drawCircle(center, _circleRadius, fillPaint);

    // White ring inside the circle for contrast.
    final ringPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    canvas.drawCircle(center, _circleRadius - 1.5, ringPaint);

    // Icon glyph in the center.
    final textPainter = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(iconData.codePoint),
        style: TextStyle(
          fontSize: _iconSize,
          fontFamily: iconData.fontFamily,
          package: iconData.fontPackage,
          color: Colors.white,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(
        center.dx - textPainter.width / 2,
        center.dy - textPainter.height / 2,
      ),
    );

    final picture = recorder.endRecording();
    final img = await picture.toImage(
      (_width * scale).round(),
      (_height * scale).round(),
    );
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }
}
