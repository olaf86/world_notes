import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:world_notes/core/utils/marker_image.dart';

void main() {
  testWidgets('renders emphasized marker states at the stable marker size', (
    tester,
  ) async {
    final result = await tester.runAsync(() async {
      final normal = await MarkerImage.render(
        iconData: Icons.place,
        color: Colors.green,
      );
      final emphasized = await MarkerImage.render(
        iconData: Icons.place,
        color: Colors.green,
        showFollowedAuthorRing: true,
        showUnseenDot: true,
      );
      final photo = await MarkerImage.render(
        iconData: Icons.place,
        color: Colors.green,
        imageBytes: normal,
        showUnseenDot: true,
      );

      final codec = await ui.instantiateImageCodec(emphasized);
      try {
        final frame = await codec.getNextFrame();
        try {
          return (
            normal: normal,
            emphasized: emphasized,
            photo: photo,
            width: frame.image.width,
            height: frame.image.height,
          );
        } finally {
          frame.image.dispose();
        }
      } finally {
        codec.dispose();
      }
    });

    expect(result, isNotNull);
    final rendered = result!;
    expect(rendered.emphasized, isNot(orderedEquals(rendered.normal)));
    expect(rendered.photo, isNotEmpty);
    expect(rendered.width, 96);
    expect(rendered.height, 120);
  });
}
