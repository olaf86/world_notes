/// Shared limits and normalization for message image uploads.
abstract class ImageUploadUtil {
  ImageUploadUtil._();

  static const int maxImageBytes = 5 * 1024 * 1024;

  static const String defaultExtension = 'jpg';

  static const Map<String, String> _contentTypes = {
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'png': 'image/png',
    'gif': 'image/gif',
    'webp': 'image/webp',
    'heic': 'image/heic',
    'heif': 'image/heif',
  };

  static String extensionForFileName(String? fileName) {
    if (fileName == null) return defaultExtension;

    final cleanName = fileName.split(RegExp(r'[?#]')).first.trim();
    final dotIndex = cleanName.lastIndexOf('.');
    if (dotIndex < 0 || dotIndex == cleanName.length - 1) {
      return defaultExtension;
    }

    final rawExtension = cleanName.substring(dotIndex + 1).toLowerCase();
    if (!RegExp(r'^[a-z0-9]+$').hasMatch(rawExtension)) {
      return defaultExtension;
    }

    return _contentTypes.containsKey(rawExtension)
        ? rawExtension
        : defaultExtension;
  }

  static String contentTypeForExtension(String extension) {
    return _contentTypes[extension.toLowerCase()] ??
        _contentTypes[defaultExtension]!;
  }

  static String contentTypeForFileName(String? fileName) {
    return contentTypeForExtension(extensionForFileName(fileName));
  }

  static bool isWithinSizeLimit(int byteLength) {
    return byteLength <= maxImageBytes;
  }
}
