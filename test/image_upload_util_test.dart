import 'package:flutter_test/flutter_test.dart';
import 'package:world_notes/core/utils/image_upload_util.dart';

void main() {
  group('ImageUploadUtil', () {
    test('builds a message-scoped WebP storage path', () {
      expect(
        ImageUploadUtil.messageStoragePath(
          placeId: 'place-1',
          userId: 'user-1',
          messageId: '0197a5e7-9b54-7d31-89c4-d4f3671a8c02',
        ),
        'images/messages/place-1/user-1/'
        '0197a5e7-9b54-7d31-89c4-d4f3671a8c02.webp',
      );
    });

    test('builds a note pin thumbnail WebP storage path', () {
      expect(
        ImageUploadUtil.pinThumbnailStoragePath(
          placeId: 'place-1',
          userId: 'user-1',
          imageId: '0197a5e7-9b54-7d31-89c4-d4f3671a8c02',
        ),
        'images/pins/place-1/user-1/'
        '0197a5e7-9b54-7d31-89c4-d4f3671a8c02.webp',
      );
    });

    test('checks the configured upload size limit', () {
      expect(
        ImageUploadUtil.isWithinSizeLimit(ImageUploadUtil.maxImageBytes),
        isTrue,
      );
      expect(
        ImageUploadUtil.isWithinSizeLimit(ImageUploadUtil.maxImageBytes + 1),
        isFalse,
      );
    });
  });
}
