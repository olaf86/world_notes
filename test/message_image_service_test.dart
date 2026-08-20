import 'package:flutter_test/flutter_test.dart';
import 'package:world_notes/services/message_image_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('batches signed image access and caches URLs until expiry', () async {
    var calls = 0;
    final requestedBatches = <List<String>>[];
    final service = MessageImageService.forTesting(
      fetchBatch: (paths) async {
        calls += 1;
        requestedBatches.add(List.unmodifiable(paths));
        final expiresAt = DateTime.now().add(const Duration(hours: 24));
        return {
          'images': [
            for (final path in paths)
              {
                'storagePath': path,
                'status': 'available',
                'url': 'https://storage.example.test/$path?redacted=yes',
                'expiresAtMillis': expiresAt.millisecondsSinceEpoch,
              },
          ],
        };
      },
    );
    addTearDown(service.dispose);

    final urls = await Future.wait([
      service.downloadUrl('images/pins/place/alice/image-a.webp'),
      service.downloadUrl('images/pins/place/alice/image-b.webp'),
    ]);

    expect(calls, 1);
    expect(requestedBatches.single, hasLength(2));
    expect(urls, everyElement(startsWith('https://storage.example.test/')));
    expect(
      await service.downloadUrl('images/pins/place/alice/image-a.webp'),
      urls.first,
    );
    expect(calls, 1);
  });

  test('reports unavailable images without exposing server detail', () async {
    final service = MessageImageService.forTesting(
      fetchBatch: (paths) async => {
        'images': [
          for (final path in paths)
            {'storagePath': path, 'status': 'unavailable'},
        ],
      },
    );
    addTearDown(service.dispose);

    await expectLater(
      service.downloadUrl('images/pins/place/alice/hidden.webp'),
      throwsA(isA<StateError>()),
    );
  });

  test('namespaces downloaded byte cache keys by world', () {
    Future<Map<String, dynamic>> unused(List<String> _) async => {};
    final asia = MessageImageService.forTesting(
      fetchBatch: unused,
      cacheNamespace: 'asia',
    );
    final europe = MessageImageService.forTesting(
      fetchBatch: unused,
      cacheNamespace: 'europe',
    );
    addTearDown(asia.dispose);
    addTearDown(europe.dispose);

    const path = 'images/pins/place/alice/image.webp';
    expect(asia.cacheKey(path), 'asia:$path');
    expect(europe.cacheKey(path), 'europe:$path');
    expect(asia.cacheKey(path), isNot(europe.cacheKey(path)));
  });
}
