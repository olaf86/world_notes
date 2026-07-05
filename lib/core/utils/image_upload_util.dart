import 'dart:typed_data';

import 'package:flutter_image_compress/flutter_image_compress.dart';

/// Shared encoding rules for message image uploads.
abstract class ImageUploadUtil {
  ImageUploadUtil._();

  static const int maxImageBytes = 2 * 1024 * 1024;
  static const int maxDimension = 1920;
  static const int preferredQuality = 85;
  static const int fallbackQuality = 80;
  static const int pinThumbnailDimension = 320;
  static const int maxPinThumbnailBytes = 256 * 1024;
  static const int pinThumbnailQuality = 82;
  static const int pinThumbnailFallbackQuality = 72;

  static String messageStoragePath({
    required String placeId,
    required String userId,
    required String messageId,
  }) {
    return 'images/messages/$placeId/$userId/$messageId.webp';
  }

  static String pinThumbnailStoragePath({
    required String placeId,
    required String userId,
    required String imageId,
  }) {
    return 'images/pins/$placeId/$userId/$imageId.webp';
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

  static Future<Uint8List> compressPinThumbnailToWebP(Uint8List source) async {
    var result = await _compress(
      source,
      targetMaxDimension: pinThumbnailDimension,
      quality: pinThumbnailQuality,
    );
    if (result.length > maxPinThumbnailBytes) {
      result = await _compress(
        source,
        targetMaxDimension: pinThumbnailDimension,
        quality: pinThumbnailFallbackQuality,
      );
    }
    if (result.length > maxPinThumbnailBytes) {
      throw const FormatException(
        'Thumbnail image is larger than the 256 KB limit.',
      );
    }
    return result;
  }

  static Future<Uint8List> _compress(
    Uint8List source, {
    int targetMaxDimension = maxDimension,
    required int quality,
  }) async {
    final result = await FlutterImageCompress.compressWithList(
      source,
      minWidth: targetMaxDimension,
      minHeight: targetMaxDimension,
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
