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
    final seedPhase = shaderSeed * math.pi * 2;
    final horizontalSegments = <(Offset, Offset)>[];
    final verticalSegments = <(Offset, Offset)>[];

    double random(double stream) {
      final value = math.sin(shaderSeed * 91.7 + stream * 12.9898) * 43758.5453;
      return value - value.floorToDouble();
    }

    double remix(double value) {
      final remixed = value * 7.31 + 0.17;
      return remixed - remixed.floorToDouble();
    }

    void paintRoute(
      List<Offset> points,
      Color color,
      List<(Offset, Offset)> segments,
    ) {
      final haloPaint = Paint()
        ..color = _color(color, 0.025)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
      final corePaint = Paint()
        ..color = _color(color, 0.085)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1;
      final path = Path()..moveTo(points.first.dx, points.first.dy);
      for (var index = 1; index < points.length; index++) {
        path.lineTo(points[index].dx, points[index].dy);
        segments.add((points[index - 1], points[index]));
      }
      canvas
        ..drawPath(path, haloPaint)
        ..drawPath(path, corePaint);
    }

    final omittedRow = (random(4) * 5).floor();
    for (var row = 0; row < 8; row++) {
      final first = random(row + 31);
      if (row % 5 == omittedRow) continue;
      final second = remix(first);
      final third = remix(second);
      final center =
          0.50 +
          (first - 0.5) * 0.42 +
          math.sin(_phase + first * math.pi * 2 + seedPhase) * 0.055;
      final direction = second < 0.5 ? -1.0 : 1.0;
      final step = (0.16 + third * 0.16) * direction;
      final before = (row + center - step * 0.5) / 8 * size.height;
      final after = (row + center + step * 0.5) / 8 * size.height;
      final bend =
          (0.18 +
              third * 0.64 +
              math.sin(_phase + second * math.pi * 2) * 0.055) *
          size.width;
      paintRoute(
        [
          Offset(0, before),
          Offset(bend, before),
          Offset(bend, after),
          Offset(size.width, after),
        ],
        colors[0],
        horizontalSegments,
      );
    }

    final omittedColumn = (random(5) * 5).floor();
    for (var column = 0; column < 5; column++) {
      final first = random(column + 73);
      if (column == omittedColumn) continue;
      final second = remix(first);
      final third = remix(second);
      final center =
          0.50 +
          (first - 0.5) * 0.42 +
          math.cos(_phase + first * math.pi * 2 + seedPhase) * 0.055;
      final direction = second < 0.5 ? -1.0 : 1.0;
      final step = (0.16 + third * 0.16) * direction;
      final before = (column + center - step * 0.5) / 5 * size.width;
      final after = (column + center + step * 0.5) / 5 * size.width;
      final bend =
          (0.16 +
              third * 0.68 +
              math.cos(_phase + second * math.pi * 2) * 0.055) *
          size.height;
      paintRoute(
        [
          Offset(before, 0),
          Offset(before, bend),
          Offset(after, bend),
          Offset(after, size.height),
        ],
        colors[1],
        verticalSegments,
      );
    }

    bool isHorizontal((Offset, Offset) segment) =>
        (segment.$1.dy - segment.$2.dy).abs() < 0.001;
    bool contains(double value, double first, double second) =>
        value >= math.min(first, second) && value <= math.max(first, second);

    final paintedJunctions = <String>{};
    for (final horizontalFamilySegment in horizontalSegments) {
      for (final verticalFamilySegment in verticalSegments) {
        if (isHorizontal(horizontalFamilySegment) ==
            isHorizontal(verticalFamilySegment)) {
          continue;
        }
        final horizontal = isHorizontal(horizontalFamilySegment)
            ? horizontalFamilySegment
            : verticalFamilySegment;
        final vertical = isHorizontal(horizontalFamilySegment)
            ? verticalFamilySegment
            : horizontalFamilySegment;
        final point = Offset(vertical.$1.dx, horizontal.$1.dy);
        if (!contains(point.dx, horizontal.$1.dx, horizontal.$2.dx) ||
            !contains(point.dy, vertical.$1.dy, vertical.$2.dy)) {
          continue;
        }
        final junctionKey = '${point.dx.round()}:${point.dy.round()}';
        if (!paintedJunctions.add(junctionKey)) continue;
        canvas.drawCircle(
          point,
          6,
          Paint()
            ..color = _color(colors[2], 0.10)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
        );
        canvas.drawCircle(point, 1.6, Paint()..color = _color(colors[2], 0.24));
      }
    }
  }

  void _paintEditorial(Canvas canvas, Size size) {
    final ink = palette.colorScheme.primary;
    final accent = palette.colorScheme.tertiary;
    final gap = math.max(28.0, size.shortestSide / 8);
    var row = 0;
    for (double y = gap / 2; y < size.height; y += gap) {
      final isMajor = row % 4 == 0;
      canvas.drawLine(
        Offset(size.width * 0.07, y),
        Offset(size.width * 0.94, y),
        Paint()
          ..color = _color(ink, isMajor ? 0.065 : 0.04)
          ..strokeWidth = 0.8,
      );
      row++;
    }

    canvas.drawLine(
      Offset(size.width * 0.105, 0),
      Offset(size.width * 0.105, size.height),
      Paint()
        ..color = _color(Color.lerp(ink, accent, 0.72)!, 0.095)
        ..strokeWidth = 1,
    );

    final pulse = 0.86 + math.sin(_phase) * 0.14;
    row = 0;
    for (double y = gap / 2; y < size.height; y += gap) {
      var column = 0;
      for (double x = gap / 2; x < size.width; x += gap) {
        if (x > size.width * 0.16 && x < size.width * 0.92) {
          final isAccent = (column + row) % 4 == 0;
          canvas.drawCircle(
            Offset(x, y),
            isAccent ? 1.4 : 0.8,
            Paint()..color = _color(accent, isAccent ? 0.065 * pulse : 0.025),
          );
        }
        column++;
      }
      row++;
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
