import 'package:flutter_test/flutter_test.dart';
import 'package:world_notes/core/utils/image_upload_util.dart';

void main() {
  group('ImageUploadUtil', () {
    test('normalizes supported extensions', () {
      expect(ImageUploadUtil.extensionForFileName('photo.JPG'), 'jpg');
      expect(ImageUploadUtil.extensionForFileName('image.jpeg'), 'jpeg');
      expect(ImageUploadUtil.extensionForFileName('image.png'), 'png');
      expect(ImageUploadUtil.extensionForFileName('image.webp'), 'webp');
      expect(ImageUploadUtil.extensionForFileName('image.heic'), 'heic');
    });

    test('falls back to jpg for missing or unsupported extensions', () {
      expect(ImageUploadUtil.extensionForFileName(null), 'jpg');
      expect(ImageUploadUtil.extensionForFileName('photo'), 'jpg');
      expect(ImageUploadUtil.extensionForFileName('photo.tiff'), 'jpg');
      expect(ImageUploadUtil.extensionForFileName('photo.jp*g'), 'jpg');
    });

    test('returns standard image content types', () {
      expect(ImageUploadUtil.contentTypeForFileName('photo.jpg'), 'image/jpeg');
      expect(ImageUploadUtil.contentTypeForFileName('photo.png'), 'image/png');
      expect(
        ImageUploadUtil.contentTypeForFileName('photo.webp'),
        'image/webp',
      );
      expect(
        ImageUploadUtil.contentTypeForFileName('photo.tiff'),
        'image/jpeg',
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
