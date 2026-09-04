import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../core/theme/note_themes.dart';
import '../../../domain/entities/note_theme.dart';

/// A subtle decorative layer that gives each non-standard note theme its own
/// sense of motion. It deliberately paints no content for the standard theme.
///
/// Set [animate] to false for compact surfaces such as list cards and theme
/// previews. When the platform requests reduced motion, the layer also falls
/// back to a still composition.
class NoteThemeMotionBackground extends StatefulWidget {
  final NoteThemeId themeId;
  final NoteThemePalette palette;
  final bool animate;
  final double opacityScale;

  const NoteThemeMotionBackground({
    super.key,
    required this.themeId,
    required this.palette,
    this.animate = true,
    this.opacityScale = 1,
  });

  @override
  State<NoteThemeMotionBackground> createState() =>
      _NoteThemeMotionBackgroundState();
}

class _NoteThemeMotionBackgroundState extends State<NoteThemeMotionBackground>
    with SingleTickerProviderStateMixin {
  // Complete a loop quickly enough for the background motion to register at a
  // glance while keeping the movement calm behind note content. Repaints are
  // capped at 30 fps to avoid tracking 60/120 Hz displays unnecessarily.
  static const _animationDurationSeconds = 14;
  static const _targetRepaintsPerSecond = 30;
  static const _animationSteps =
      _animationDurationSeconds * _targetRepaintsPerSecond;

  // Static previews and reduced-motion mode use a balanced frame 18% into the
  // same loop. This is a normalized position, not seconds or opacity.
  static const _stillProgress = 0.18;

  late final double _shaderSeed = math.Random().nextDouble();
  ui.FragmentShader? _fragmentShader;
  bool _shaderRequested = false;

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: _animationDurationSeconds),
    value: _stillProgress,
  );

  @override
  void initState() {
    super.initState();
    _requestShaderIfNeeded();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncAnimation();
  }

  @override
  void didUpdateWidget(NoteThemeMotionBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.themeId != widget.themeId ||
        oldWidget.animate != widget.animate) {
      _syncAnimation();
    }
    _requestShaderIfNeeded();
  }

  void _requestShaderIfNeeded() {
    if (_shaderRequested || widget.themeId == NoteThemeId.standard) return;
    _shaderRequested = true;
    unawaited(_loadShader());
  }

  Future<void> _loadShader() async {
    try {
      final program = await NoteThemeShaderProgram.load();
      if (!mounted) return;
      setState(() => _fragmentShader = program.fragmentShader());
    } catch (error, stackTrace) {
      // Runtime shaders may be unavailable on a renderer or during a test.
      // Retain the Canvas painter as a safe visual fallback.
      assert(() {
        debugPrint('Note theme shader unavailable: $error\n$stackTrace');
        return true;
      }());
    }
  }

  void _syncAnimation() {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final shouldAnimate =
        widget.animate &&
        widget.themeId != NoteThemeId.standard &&
        !reduceMotion;
    if (shouldAnimate) {
      if (!_controller.isAnimating) _controller.repeat();
    } else {
      _controller
        ..stop()
        ..value = _stillProgress;
    }
  }

  @override
  void dispose() {
    _fragmentShader?.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.themeId == NoteThemeId.standard) {
      return const SizedBox.expand();
    }

    Widget paint(double progress) => IgnorePointer(
      child: ExcludeSemantics(
        child: RepaintBoundary(
          child: CustomPaint(
            key: ValueKey('note-theme-motion-${widget.themeId.name}'),
            painter: NoteThemeMotionPainter(
              themeId: widget.themeId,
              palette: widget.palette,
              progress: progress,
              shaderSeed: _shaderSeed,
              opacityScale: widget.opacityScale,
              fragmentShader: _fragmentShader,
            ),
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );

    if (!_controller.isAnimating) return paint(_stillProgress);
    return AnimatedBuilder(
      animation: _controller,
      // Quantizing the slow background to 30 fps avoids repainting it at the
      // full 60/120 Hz display rate without making the motion look stepped.
      builder: (_, _) => paint(
        (_controller.value * _animationSteps).floor() / _animationSteps,
      ),
    );
  }
}

@visibleForTesting
class NoteThemeShaderProgram {
  static const assetKey = 'shaders/note_theme_background.frag';
  static Future<ui.FragmentProgram>? _program;

  static Future<ui.FragmentProgram> load() =>
      _program ??= ui.FragmentProgram.fromAsset(assetKey);
}

@visibleForTesting
class NoteThemeMotionPainter extends CustomPainter {
  final NoteThemeId themeId;
  final NoteThemePalette palette;
  final double progress;
  final double shaderSeed;
  final double opacityScale;
  final ui.FragmentShader? fragmentShader;

  const NoteThemeMotionPainter({
    required this.themeId,
    required this.palette,
    required this.progress,
    required this.shaderSeed,
    required this.opacityScale,
    this.fragmentShader,
  });

  double get _phase => progress * math.pi * 2;

  Color _color(Color color, double opacity) =>
      color.withValues(alpha: (opacity * opacityScale).clamp(0, 1).toDouble());

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    if (fragmentShader != null && themeId != NoteThemeId.standard) {
      _paintFragmentShader(canvas, size);
      return;
    }
    switch (themeId) {
      case NoteThemeId.standard:
        return;
      case NoteThemeId.aurora:
        _paintAurora(canvas, size);
      case NoteThemeId.citrus:
        _paintCitrus(canvas, size);
      case NoteThemeId.botanical:
        _paintBotanical(canvas, size);
      case NoteThemeId.neon:
        _paintNeon(canvas, size);
      case NoteThemeId.editorial:
        _paintEditorial(canvas, size);
    }
  }

  void _paintFragmentShader(Canvas canvas, Size size) {
    final shader = fragmentShader!;
    var uniform = 0;
    shader
      ..setFloat(uniform++, size.width)
      ..setFloat(uniform++, size.height)
      ..setFloat(uniform++, progress)
      ..setFloat(uniform++, shaderSeed)
      ..setFloat(uniform++, themeId.index.toDouble())
      ..setFloat(uniform++, opacityScale);

    void setColor(Color color) {
      shader
        ..setFloat(uniform++, color.r)
        ..setFloat(uniform++, color.g)
        ..setFloat(uniform++, color.b)
        ..setFloat(uniform++, color.a);
    }

    setColor(palette.colorScheme.primary);
    setColor(palette.colorScheme.secondary);
    setColor(palette.colorScheme.tertiary);
    canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
  }

  void _paintAurora(Canvas canvas, Size size) {
    final colors = [
      palette.colorScheme.primary,
      palette.colorScheme.tertiary,
      palette.colorScheme.secondary,
    ];
    for (var index = 0; index < colors.length; index++) {
      final wave = _phase + index * 1.8;
      final y = size.height * (0.18 + index * 0.28);
      final path = Path()
        ..moveTo(-size.width * 0.24, y + math.sin(wave) * size.height * 0.06)
        ..cubicTo(
          size.width * 0.12,
          y + math.cos(wave) * size.height * 0.12,
          size.width * 0.56,
          y - math.sin(wave * 0.8) * size.height * 0.11,
          size.width * 1.24,
          y + math.cos(wave * 0.7) * size.height * 0.07,
        );
      canvas.drawPath(
        path,
        Paint()
          ..color = _color(colors[index], 0.065)
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(16, size.shortestSide * 0.11)
          ..strokeCap = StrokeCap.round,
      );
    }

    for (var index = 0; index < 7; index++) {
      final x = _wrap(0.08 + index * 0.17 + progress * 0.08) * size.width;
      final y = _wrap(0.14 + index * 0.31 - progress * 0.04) * size.height;
      canvas.drawCircle(
        Offset(x, y),
        index.isEven ? 1.7 : 1.1,
        Paint()..color = _color(palette.colorScheme.primary, 0.18),
      );
    }
  }

  void _paintCitrus(Canvas canvas, Size size) {
    final shortest = size.shortestSide;
    final colors = [
      palette.colorScheme.primary,
      palette.colorScheme.tertiary,
      palette.colorScheme.secondary,
    ];
    for (var index = 0; index < 6; index++) {
      final x = _wrap(0.06 + index * 0.23 + progress * 0.06) * size.width;
      final y = _wrap(0.12 + index * 0.29 - progress * 0.1) * size.height;
      final radius = math.max(8.0, shortest * (0.055 + (index % 3) * 0.018));
      final center = Offset(x, y);
      final color = colors[index % colors.length];
      canvas.drawCircle(center, radius, Paint()..color = _color(color, 0.055));
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..color = _color(color, 0.13)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2,
      );
      final spokePaint = Paint()
        ..color = _color(color, 0.1)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8;
      for (var spoke = 0; spoke < 3; spoke++) {
        final angle = _phase * 0.12 + spoke * math.pi * 2 / 3;
        canvas.drawLine(
          center,
          center + Offset(math.cos(angle), math.sin(angle)) * radius,
          spokePaint,
        );
      }
    }
  }

  void _paintBotanical(Canvas canvas, Size size) {
    final shortest = size.shortestSide;
    for (var index = 0; index < 7; index++) {
      final x = _wrap(0.03 + index * 0.19 + progress * 0.035) * size.width;
      final y = _wrap(0.08 + index * 0.27 - progress * 0.07) * size.height;
      final leafLength = math.max(
        14.0,
        shortest * (0.09 + (index % 2) * 0.025),
      );
      final leafWidth = leafLength * 0.43;
      final sway = math.sin(_phase + index * 0.9) * 0.16;
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(-0.7 + (index % 4) * 0.46 + sway);
      final leaf = Path()
        ..moveTo(0, 0)
        ..quadraticBezierTo(leafLength * 0.48, -leafWidth, leafLength, 0)
        ..quadraticBezierTo(leafLength * 0.48, leafWidth, 0, 0)
        ..close();
      final color = index.isEven
          ? palette.colorScheme.primary
          : palette.colorScheme.tertiary;
      canvas.drawPath(leaf, Paint()..color = _color(color, 0.075));
      canvas.drawLine(
        Offset.zero,
        Offset(leafLength, 0),
        Paint()
          ..color = _color(color, 0.16)
          ..strokeWidth = 0.9,
      );
      canvas.restore();
    }
  }

  void _paintNeon(Canvas canvas, Size size) {
    final colors = [
      palette.colorScheme.primary,
      palette.colorScheme.secondary,
      palette.colorScheme.tertiary,
    ];
    final gridPaint = Paint()
      ..color = _color(colors.first, 0.055)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;
    final spacing = math.max(28.0, size.shortestSide * 0.14);
    final shift = progress * spacing;
    for (double y = -spacing + shift; y < size.height + spacing; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
    for (
      double x = -size.height - spacing + shift;
      x < size.width + spacing;
      x += spacing
    ) {
      canvas.drawLine(
        Offset(x, size.height),
        Offset(x + size.height * 0.32, 0),
        gridPaint,
      );
    }

    final orbit = _phase + shaderSeed * math.pi * 2;
    final centers = [
      Offset(
        size.width * (0.5 + math.sin(orbit) * 0.27),
        size.height * (0.47 + math.sin(orbit * 2) * 0.16),
      ),
      Offset(
        size.width * (0.5 - math.sin(orbit) * 0.27),
        size.height * (0.47 + math.sin(orbit * 2) * 0.16),
      ),
      Offset(
        size.width * (0.5 + math.cos(orbit) * 0.20),
        size.height * (0.47 + math.sin(orbit * 3 + 1.1) * 0.24),
      ),
    ];
    final radii = [0.12, 0.10, 0.075];
    final lobes = [3, 5, 4];
    for (var index = 0; index < centers.length; index++) {
      final path = _neonLoopPath(
        center: centers[index],
        radius: size.height * radii[index],
        lobes: lobes[index],
        phase: orbit * (index.isEven ? index + 1 : -1),
      );
      canvas.drawPath(
        path,
        Paint()
          ..color = _color(colors[index], 0.065)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 7
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7),
      );
      canvas.drawPath(
        path,
        Paint()
          ..color = _color(colors[index], 0.24)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4,
      );
    }
  }

  Path _neonLoopPath({
    required Offset center,
    required double radius,
    required int lobes,
    required double phase,
  }) {
    const segments = 40;
    final path = Path();
    for (var segment = 0; segment <= segments; segment++) {
      final angle = segment / segments * math.pi * 2;
      final shapedRadius =
          radius * (1 + math.sin(angle * lobes + phase) * 0.16);
      final point =
          center + Offset(math.cos(angle), math.sin(angle)) * shapedRadius;
      if (segment == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    return path..close();
  }

  void _paintEditorial(Canvas canvas, Size size) {
    final ink = palette.colorScheme.primary;
    final accent = palette.colorScheme.tertiary;
    final linePaint = Paint()
      ..color = _color(ink, 0.075)
      ..strokeWidth = 0.85;
    final gap = math.max(34.0, size.shortestSide * 0.16);
    final shift = progress * gap;
    for (double y = -gap + shift; y < size.height + gap; y += gap) {
      final inset = ((y / gap).round().abs() % 3) * size.width * 0.08;
      canvas.drawLine(
        Offset(12 + inset, y),
        Offset(size.width - 12 - inset * 0.4, y),
        linePaint,
      );
    }

    for (var index = 0; index < 4; index++) {
      final x = _wrap(0.08 + index * 0.31 - progress * 0.045) * size.width;
      final y = _wrap(0.14 + index * 0.38 + progress * 0.055) * size.height;
      final width = math.max(18.0, size.shortestSide * (0.07 + index * 0.01));
      final rect = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(x, y),
          width: width,
          height: width * 0.62,
        ),
        const Radius.circular(2),
      );
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(math.sin(_phase + index) * 0.05);
      canvas.translate(-x, -y);
      canvas.drawRRect(
        rect,
        Paint()..color = _color(index.isEven ? ink : accent, 0.07),
      );
      canvas.drawRRect(
        rect,
        Paint()
          ..color = _color(index.isEven ? ink : accent, 0.13)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8,
      );
      canvas.restore();
    }
  }

  double _wrap(double value) => value - value.floorToDouble();

  @override
  bool shouldRepaint(NoteThemeMotionPainter oldDelegate) =>
      oldDelegate.themeId != themeId ||
      oldDelegate.palette != palette ||
      oldDelegate.progress != progress ||
      oldDelegate.shaderSeed != shaderSeed ||
      oldDelegate.opacityScale != opacityScale ||
      oldDelegate.fragmentShader != fragmentShader;
}
