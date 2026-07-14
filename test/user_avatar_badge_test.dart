import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:world_notes/presentation/widgets/note/user_avatar_badge.dart';

void main() {
  testWidgets('changes the image cache key when the photo version changes', (
    tester,
  ) async {
    const url = 'https://example.com/alice.png';

    await tester.pumpWidget(
      const MaterialApp(
        home: SizedBox.square(
          dimension: 24,
          child: UserAvatarBadge(name: 'Alice', photoUrl: url, photoVersion: 2),
        ),
      ),
    );

    final image = tester.widget<Image>(find.byType(Image));
    final provider = image.image as CachedNetworkImageProvider;
    expect(provider.url, url);
    expect(provider.cacheKey, '$url#v2');
  });
}
