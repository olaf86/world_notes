import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/utils/pattern_lock_util.dart';

class PatternLockInput extends StatefulWidget {
  final ValueChanged<List<int>>? onChanged;
  final ValueChanged<List<int>>? onCompleted;
  final VoidCallback? onTooLong;
  final int maxLength;
  final double size;
  final List<int> initialPath;

  const PatternLockInput({
    super.key,
    this.onChanged,
    this.onCompleted,
    this.onTooLong,
    this.maxLength = PatternLockUtil.maxLength,
    this.size = 280,
    this.initialPath = const [],
  });

  @override
  State<PatternLockInput> createState() => _PatternLockInputState();
}

class _PatternLockInputState extends State<PatternLockInput> {
  late List<int> _path;
  Offset? _pointer;
  bool _tooLongNotified = false;

  @override
  void initState() {
    super.initState();
    _path = List.of(widget.initialPath);
  }

  void _start(Offset position, Size size) {
    final node = _hitTest(position, size);
    if (node == null) return;
    setState(() {
      _path = [node];
      _pointer = position;
      _tooLongNotified = false;
    });
    widget.onChanged?.call(List.unmodifiable(_path));
  }

  void _update(Offset position, Size size) {
    if (_path.isEmpty) {
      _start(position, size);
      return;
    }

    final node = _hitTest(position, size);
    setState(() => _pointer = position);
    if (node == null || node == _path.last) return;
    if (!PatternLockUtil.areAdjacent(_path.last, node)) return;
    if (_path.length >= widget.maxLength) {
      if (!_tooLongNotified) {
        _tooLongNotified = true;
        widget.onTooLong?.call();
      }
      return;
    }

    setState(() => _path = [..._path, node]);
    widget.onChanged?.call(List.unmodifiable(_path));
  }

  void _end() {
    setState(() => _pointer = null);
    if (_path.isNotEmpty) {
      widget.onCompleted?.call(List.unmodifiable(_path));
    }
  }

  int? _hitTest(Offset position, Size size) {
    final centers = _nodeCenters(size);
    final hitRadius = math.max(24.0, size.shortestSide / 10);
    for (var i = 0; i < centers.length; i++) {
      if ((position - centers[i]).distance <= hitRadius) return i;
    }
    return null;
  }

  static List<Offset> _nodeCenters(Size size) {
    final side = size.shortestSide;
    final origin = Offset((size.width - side) / 2, (size.height - side) / 2);
    final step = side / 4;
    return [
      for (var row = 0; row < 3; row++)
        for (var col = 0; col < 3; col++)
          origin + Offset(step * (col + 1), step * (row + 1)),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox.square(
        dimension: widget.size,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final size = constraints.biggest;
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanStart: (details) => _start(details.localPosition, size),
              onPanUpdate: (details) => _update(details.localPosition, size),
              onPanEnd: (_) => _end(),
              onPanCancel: _end,
              onTapDown: (details) => _start(details.localPosition, size),
              onTapUp: (_) => _end(),
              child: CustomPaint(
                painter: _PatternLockPainter(
                  path: _path,
                  pointer: _pointer,
                  colorScheme: Theme.of(context).colorScheme,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _PatternLockPainter extends CustomPainter {
  final List<int> path;
  final Offset? pointer;
  final ColorScheme colorScheme;

  const _PatternLockPainter({
    required this.path,
    required this.pointer,
    required this.colorScheme,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final centers = _PatternLockInputState._nodeCenters(size);
    final segmentCounts = <String, int>{};
    final nodeCounts = <int, int>{};

    for (final node in path) {
      nodeCounts[node] = (nodeCounts[node] ?? 0) + 1;
    }

    for (var i = 1; i < path.length; i++) {
      final a = path[i - 1];
      final b = path[i];
      final key = a < b ? '$a-$b' : '$b-$a';
      final count = (segmentCounts[key] ?? 0) + 1;
      segmentCounts[key] = count;
      final paint = Paint()
        ..color = _colorForCount(count)
        ..strokeWidth = 7
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(centers[a], centers[b], paint);
    }

    if (path.isNotEmpty && pointer != null) {
      final last = centers[path.last];
      final paint = Paint()
        ..color = colorScheme.primary.withValues(alpha: 0.28)
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(last, pointer!, paint);
    }

    for (var i = 0; i < centers.length; i++) {
      final count = nodeCounts[i] ?? 0;
      final selected = count > 0;
      final fill = Paint()
        ..color = selected
            ? _colorForCount(count)
            : colorScheme.surfaceContainerHighest;
      final border = Paint()
        ..color = selected ? colorScheme.onPrimary : colorScheme.outlineVariant
        ..style = PaintingStyle.stroke
        ..strokeWidth = selected ? 3 : 2;

      canvas.drawCircle(centers[i], 22, fill);
      canvas.drawCircle(centers[i], 22, border);
      if (selected) {
        canvas.drawCircle(
          centers[i],
          7,
          Paint()..color = colorScheme.onPrimary.withValues(alpha: 0.92),
        );
      }
    }
  }

  Color _colorForCount(int count) {
    final hsl = HSLColor.fromColor(colorScheme.primary);
    final hue = (hsl.hue + (count - 1) * 28) % 360;
    final lightness = (hsl.lightness + math.min(count - 1, 8) * 0.035).clamp(
      0.32,
      0.72,
    );
    return hsl.withHue(hue).withLightness(lightness).toColor();
  }

  @override
  bool shouldRepaint(covariant _PatternLockPainter oldDelegate) {
    return oldDelegate.path != path ||
        oldDelegate.pointer != pointer ||
        oldDelegate.colorScheme != colorScheme;
  }
}
