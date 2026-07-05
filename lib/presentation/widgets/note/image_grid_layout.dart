import 'package:flutter/widgets.dart';

class ImageGridLayout extends StatelessWidget {
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;

  const ImageGridLayout({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
  });

  @override
  Widget build(BuildContext context) {
    const gap = 2.0;
    final count = itemCount.clamp(0, 4).toInt();

    if (count == 1) return itemBuilder(context, 0);

    if (count == 2) {
      return Row(
        children: [
          Expanded(child: itemBuilder(context, 0)),
          const SizedBox(width: gap),
          Expanded(child: itemBuilder(context, 1)),
        ],
      );
    }

    if (count == 3) {
      return Row(
        children: [
          Expanded(child: itemBuilder(context, 0)),
          const SizedBox(width: gap),
          Expanded(
            child: Column(
              children: [
                Expanded(child: itemBuilder(context, 1)),
                const SizedBox(height: gap),
                Expanded(child: itemBuilder(context, 2)),
              ],
            ),
          ),
        ],
      );
    }

    return Column(
      children: [
        Expanded(
          child: Row(
            children: [
              Expanded(child: itemBuilder(context, 0)),
              const SizedBox(width: gap),
              Expanded(child: itemBuilder(context, 1)),
            ],
          ),
        ),
        const SizedBox(height: gap),
        Expanded(
          child: Row(
            children: [
              Expanded(child: itemBuilder(context, 2)),
              const SizedBox(width: gap),
              Expanded(child: itemBuilder(context, 3)),
            ],
          ),
        ),
      ],
    );
  }
}
