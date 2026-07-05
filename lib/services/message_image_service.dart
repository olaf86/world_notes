import 'dart:async';
import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

import '../core/utils/image_upload_util.dart';

class MessageImageService {
  final FirebaseStorage _storage;
  final CacheManager cacheManager;
  final Map<String, Future<String>> _downloadUrls = {};
  final Map<String, Future<Uint8List?>> _imageBytes = {};

  MessageImageService({required FirebaseStorage storage})
    : _storage = storage,
      cacheManager = CacheManager(
        Config(
          'worldNotesMessageImages',
          stalePeriod: const Duration(days: 14),
          maxNrOfCacheObjects: 100,
        ),
      );

  Future<String> downloadUrl(String storagePath) {
    return _downloadUrls.putIfAbsent(
      storagePath,
      () => _storage.ref(storagePath).getDownloadURL(),
    );
  }

  Future<Uint8List?> imageBytes(
    String storagePath, {
    int maxSizeBytes = ImageUploadUtil.maxImageBytes,
  }) {
    return _imageBytes.putIfAbsent(
      storagePath,
      () => _storage.ref(storagePath).getData(maxSizeBytes),
    );
  }

  Future<void> clearCache() async {
    _downloadUrls.clear();
    _imageBytes.clear();
    await cacheManager.emptyCache();
  }

  void dispose() {
    unawaited(cacheManager.dispose());
  }
}
