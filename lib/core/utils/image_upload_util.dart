import 'dart:typed_data';

import 'package:flutter_image_compress/flutter_image_compress.dart';

/// Shared encoding rules for message image uploads.
abstract class ImageUploadUtil {
  ImageUploadUtil._();

  static const int maxImageBytes = 2 * 1024 * 1024;
  static const int maxDimension = 1920;
  static const int preferredQuality = 85;
  static const int fallbackQuality = 80;

  static String messageStoragePath({
    required String placeId,
    required String userId,
    required String messageId,
    required int imageIndex,
  }) {
    return 'images/messages/$placeId/$userId/$messageId/$imageIndex.webp';
  }

  static bool isWithinSizeLimit(int byteLength) {
    return byteLength <= maxImageBytes;
  }

  static Future<Uint8List> compressToWebP(Uint8List source) async {
    var result = await _compress(source, quality: preferredQuality);
    if (!isWithinSizeLimit(result.length)) {
      result = await _compress(source, quality: fallbackQuality);
    }
    if (!isWithinSizeLimit(result.length)) {
      throw const FormatException(
        'Compressed image is larger than the 2 MB limit.',
      );
    }
    return result;
  }

  static Future<Uint8List> _compress(
    Uint8List source, {
    required int quality,
  }) async {
    final result = await FlutterImageCompress.compressWithList(
      source,
      minWidth: maxDimension,
      minHeight: maxDimension,
      quality: quality,
      format: CompressFormat.webp,
      keepExif: false,
    );
    if (result.isEmpty) {
      throw const FormatException('Could not encode image as WebP.');
    }
    return result;
  }
}
