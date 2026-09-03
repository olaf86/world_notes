import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Renders a teardrop-style map marker (colored pin with a white icon glyph)
/// to a PNG byte array suitable for the native map SDKs.
class MarkerImage {
  /// Bitmap dimensions (device pixels). High-DPI so the result stays crisp
  /// when a platform map scales the bitmap.
  static const double _width = 96;
  static const double _height = 120;
  static const double _circleRadius = 36;
  static const double _circleCenterY = 40;
  static const double _tipY = 112;
  static const double _iconSize = 36;
  static const double _photoRadius = 28;

  static String cacheKey({
    required String namespace,
    required String iconName,
    required String colorHex,
    String? imageStoragePath,
    String variant = 'normal',
  }) {
    final base =
        '${namespace}_${iconName}_${colorHex.replaceAll('#', '')}_$variant';
    final imagePath = imageStoragePath?.trim();
    if (imagePath == null || imagePath.isEmpty) return base;

    final encodedPath = base64Url
        .encode(utf8.encode(imagePath))
        .replaceAll('=', '');
    return '${base}_photo_$encodedPath';
  }

  static Future<Uint8List> render({
    required IconData iconData,
    required Color color,
    Uint8List? imageBytes,
    double scale = 1.0,
    bool showFollowedAuthorRing = false,
    bool showUnseenDot = false,
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.scale(scale);
    ui.Codec? photoCodec;
    ui.Image? photoImage;

    final center = Offset(_width / 2, _circleCenterY);

    if (showFollowedAuthorRing) {
      // A soft discovery halo keeps the state visible against both detailed
      // and low-contrast map styles without changing the marker footprint.
      final discoveryHaloPaint = Paint()
        ..color = const Color(0xFFFFC857).withValues(alpha: 0.62)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 9
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);
      canvas.drawCircle(center, _circleRadius + 3, discoveryHaloPaint);
    }

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

    if (showFollowedAuthorRing) {
      final discoveryPaint = Paint()
        ..color = const Color(0xFFFFC857)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 7;
      canvas.drawCircle(center, _circleRadius + 3, discoveryPaint);
    }

    if (imageBytes == null) {
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
    } else {
      photoCodec = await ui.instantiateImageCodec(
        imageBytes,
        targetWidth: (_photoRadius * 2 * scale).round(),
        targetHeight: (_photoRadius * 2 * scale).round(),
      );
      try {
        final frame = await photoCodec.getNextFrame();
        photoImage = frame.image;
      } catch (_) {
        photoCodec.dispose();
        rethrow;
      }
      final photoRect = Rect.fromCircle(center: center, radius: _photoRadius);

      canvas.save();
      canvas.clipPath(Path()..addOval(photoRect));
      paintImage(
        canvas: canvas,
        rect: photoRect,
        image: photoImage,
        fit: BoxFit.cover,
      );
      canvas.restore();

      final photoRingPaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4;
      canvas.drawCircle(center, _photoRadius + 2, photoRingPaint);
    }

    if (showUnseenDot) {
      const dotCenter = Offset(78, 15);
      const dotColor = Color(0xFFE5484D);
      final dotHaloPaint = Paint()
        ..color = dotColor.withValues(alpha: 0.72)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);
      canvas.drawCircle(dotCenter, 15, dotHaloPaint);
      canvas.drawCircle(dotCenter, 14, Paint()..color = Colors.white);
      canvas.drawCircle(dotCenter, 10, Paint()..color = dotColor);

      // Use a white exclamation mark so the badge is clear without relying on
      // color alone. Thick strokes keep it visible when the map scales it down.
      final alertPaint = Paint()
        ..color = Colors.white
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(
        dotCenter.translate(0, -5),
        dotCenter.translate(0, 2),
        alertPaint,
      );
      canvas.drawCircle(dotCenter.translate(0, 6), 1.6, alertPaint);
    }

    final picture = recorder.endRecording();
    try {
      final img = await picture.toImage(
        (_width * scale).round(),
        (_height * scale).round(),
      );
      try {
        final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
        return byteData!.buffer.asUint8List();
      } finally {
        img.dispose();
      }
    } finally {
      picture.dispose();
      photoImage?.dispose();
      photoCodec?.dispose();
    }
  }
}
