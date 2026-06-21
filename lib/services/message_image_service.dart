import 'dart:async';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

class MessageImageService {
  final FirebaseStorage _storage;
  final CacheManager cacheManager;
  final Map<String, Future<String>> _downloadUrls = {};

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

  Future<void> clearCache() async {
    _downloadUrls.clear();
    await cacheManager.emptyCache();
  }

  void dispose() {
    unawaited(cacheManager.dispose());
  }
}
