import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:world_notes/presentation/widgets/note/image_grid_layout.dart';

void main() {
  testWidgets('stretches the first item to the full height for three images', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox.square(
              dimension: 280,
              child: ImageGridLayout(
                itemCount: 3,
                itemBuilder: (_, index) => AspectRatio(
                  key: ValueKey('image-$index'),
                  aspectRatio: 2,
                  child: ColoredBox(color: Colors.blue),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    final gridRect = tester.getRect(find.byType(ImageGridLayout));
    final firstImageRect = tester.getRect(
      find.byKey(const ValueKey('image-0')),
    );

    expect(firstImageRect.top, gridRect.top);
    expect(firstImageRect.bottom, gridRect.bottom);
  });
}
