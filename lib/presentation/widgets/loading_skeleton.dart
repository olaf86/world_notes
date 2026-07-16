import 'package:flutter/material.dart';

/// Provides one lightweight pulse animation for all skeleton shapes below it.
/// The subtree is excluded from semantics because it contains no real content.
class SkeletonView extends StatefulWidget {
  final Widget child;

  const SkeletonView({super.key, required this.child});

  @override
  State<SkeletonView> createState() => _SkeletonViewState();
}

class _SkeletonViewState extends State<SkeletonView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final animationsDisabled =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (animationsDisabled) {
      _controller
        ..stop()
        ..value = 0.5;
    } else if (!_controller.isAnimating) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ExcludeSemantics(
      child: AnimatedBuilder(
        animation: _controller,
        child: widget.child,
        builder: (context, child) {
          final color = Color.lerp(
            colors.surfaceContainerHighest,
            colors.surfaceContainerLow,
            _controller.value,
          )!;
          return _SkeletonColor(color: color, child: child!);
        },
      ),
    );
  }
}

class _SkeletonColor extends InheritedWidget {
  final Color color;

  const _SkeletonColor({required this.color, required super.child});

  static Color of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<_SkeletonColor>()!.color;
  }

  @override
  bool updateShouldNotify(_SkeletonColor oldWidget) => color != oldWidget.color;
}

class SkeletonBox extends StatelessWidget {
  final double? width;
  final double height;
  final BorderRadius borderRadius;

  const SkeletonBox({
    super.key,
    this.width,
    required this.height,
    this.borderRadius = const BorderRadius.all(Radius.circular(8)),
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: _SkeletonColor.of(context),
          borderRadius: borderRadius,
        ),
      ),
    );
  }
}

class SkeletonListView extends StatelessWidget {
  final int itemCount;
  final EdgeInsetsGeometry padding;

  const SkeletonListView({
    super.key,
    this.itemCount = 6,
    this.padding = const EdgeInsets.symmetric(vertical: 8),
  });

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      physics: const NeverScrollableScrollPhysics(),
      padding: padding,
      itemCount: itemCount,
      separatorBuilder: (_, _) => const Divider(height: 1, indent: 72),
      itemBuilder: (_, _) => const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            SkeletonBox(
              width: 44,
              height: 44,
              borderRadius: BorderRadius.all(Radius.circular(22)),
            ),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FractionallySizedBox(
                    widthFactor: 0.65,
                    alignment: Alignment.centerLeft,
                    child: SkeletonBox(height: 14),
                  ),
                  SizedBox(height: 8),
                  FractionallySizedBox(
                    widthFactor: 0.9,
                    alignment: Alignment.centerLeft,
                    child: SkeletonBox(height: 11),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
