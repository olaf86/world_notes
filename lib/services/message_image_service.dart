import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_cache_manager/flutter_cache_manager.dart';

import '../core/utils/image_upload_util.dart';
import 'world_firebase_clients.dart';

typedef ImageAccessBatchFetcher =
    Future<Map<String, dynamic>> Function(List<String> storagePaths);

class MessageImageService {
  static const signedUrlLifetime = Duration(hours: 24);
  static const _expirySafetyMargin = Duration(minutes: 1);
  static const _maxBatchSize = 50;

  final ImageAccessBatchFetcher _fetchBatch;
  final String _cacheNamespace;
  CacheManager? _cacheManager;
  final Map<String, _SignedImageUrl> _downloadUrls = {};
  final Map<String, Completer<String>> _pendingUrls = {};
  final Map<String, Future<Uint8List?>> _imageBytes = {};
  Timer? _batchTimer;
  bool _disposed = false;

  MessageImageService({required WorldFunctionsClient functions})
    : this._(
        cacheNamespace: functions.worldId.value,
        fetchBatch: (storagePaths) async {
          final result = await functions
              .httpsCallable('getImageAccessUrls')
              .call<Map<String, dynamic>>({'storagePaths': storagePaths});
          return result.data;
        },
      );

  MessageImageService.forTesting({
    required ImageAccessBatchFetcher fetchBatch,
    String cacheNamespace = 'test',
  }) : this._(cacheNamespace: cacheNamespace, fetchBatch: fetchBatch);

  MessageImageService._({
    required String cacheNamespace,
    required ImageAccessBatchFetcher fetchBatch,
  }) : _cacheNamespace = cacheNamespace,
       _fetchBatch = fetchBatch;

  CacheManager get cacheManager => _cacheManager ??= CacheManager(
    Config(
      'worldNotesMessageImages',
      stalePeriod: signedUrlLifetime,
      maxNrOfCacheObjects: 100,
    ),
  );

  String cacheKey(String storagePath) => '$_cacheNamespace:$storagePath';

  Future<String> downloadUrl(String storagePath) {
    if (_disposed) return Future.error(StateError('Image service disposed.'));
    final cached = _downloadUrls[storagePath];
    if (cached != null && cached.isUsable(DateTime.now())) {
      return Future.value(cached.url);
    }
    _downloadUrls.remove(storagePath);
    final existing = _pendingUrls[storagePath];
    if (existing != null) return existing.future;

    final completer = Completer<String>();
    _pendingUrls[storagePath] = completer;
    _batchTimer ??= Timer(Duration.zero, () {
      unawaited(_flushPendingUrls());
    });
    return completer.future;
  }

  Future<Uint8List?> imageBytes(
    String storagePath, {
    int maxSizeBytes = ImageUploadUtil.maxImageBytes,
  }) {
    final existing = _imageBytes[storagePath];
    if (existing != null) return existing;
    final future = () async {
      final key = cacheKey(storagePath);
      try {
        final url = await downloadUrl(storagePath);
        final file = await cacheManager.getSingleFile(url, key: key);
        final bytes = await file.readAsBytes();
        if (bytes.length > maxSizeBytes) {
          await cacheManager.removeFile(key);
          throw StateError('Signed image exceeds its allowed size.');
        }
        return bytes;
      } catch (error, stack) {
        _imageBytes.remove(storagePath);
        Error.throwWithStackTrace(
          StateError('The authorized image could not be loaded.'),
          stack,
        );
      }
    }();
    _imageBytes[storagePath] = future;
    return future;
  }

  Future<void> clearCache() async {
    _downloadUrls.clear();
    _imageBytes.clear();
    await _cacheManager?.emptyCache();
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _batchTimer?.cancel();
    _batchTimer = null;
    final error = StateError('Image service disposed.');
    for (final completer in _pendingUrls.values) {
      if (!completer.isCompleted) completer.completeError(error);
    }
    _pendingUrls.clear();
    final cache = _cacheManager;
    _cacheManager = null;
    if (cache != null) unawaited(cache.dispose());
  }

  Future<void> _flushPendingUrls() async {
    _batchTimer = null;
    if (_disposed || _pendingUrls.isEmpty) return;
    final pending = Map<String, Completer<String>>.from(_pendingUrls);
    _pendingUrls.clear();
    final paths = pending.keys.toList(growable: false);

    for (var offset = 0; offset < paths.length; offset += _maxBatchSize) {
      final batch = paths.skip(offset).take(_maxBatchSize).toList();
      try {
        final response = await _fetchBatch(batch);
        final rawImages = response['images'];
        if (rawImages is! List) {
          throw const FormatException('Image access response is invalid.');
        }
        final returned = <String>{};
        for (final rawImage in rawImages) {
          if (rawImage is! Map) {
            throw const FormatException('Image access item is invalid.');
          }
          final storagePath = rawImage['storagePath'];
          if (storagePath is! String || !batch.contains(storagePath)) {
            throw const FormatException('Image access route is invalid.');
          }
          if (!returned.add(storagePath)) {
            throw const FormatException('Duplicate image access result.');
          }
          final completer = pending[storagePath]!;
          if (rawImage['status'] != 'available') {
            completer.completeError(
              StateError('This image is no longer available.'),
            );
            continue;
          }
          final url = rawImage['url'];
          final expiresAtMillis = rawImage['expiresAtMillis'];
          if (url is! String ||
              !url.startsWith('https://') ||
              expiresAtMillis is! int) {
            throw const FormatException('Signed image URL is invalid.');
          }
          final signed = _SignedImageUrl(
            url: url,
            expiresAt: DateTime.fromMillisecondsSinceEpoch(expiresAtMillis),
          );
          _downloadUrls[storagePath] = signed;
          completer.complete(url);
        }
        for (final storagePath in batch.where(
          (path) => !returned.contains(path),
        )) {
          pending[storagePath]!.completeError(
            const FormatException('Image access result is missing.'),
          );
        }
      } catch (error, stack) {
        for (final storagePath in batch) {
          final completer = pending[storagePath]!;
          if (!completer.isCompleted) completer.completeError(error, stack);
        }
      }
    }
  }
}

final class _SignedImageUrl {
  const _SignedImageUrl({required this.url, required this.expiresAt});

  final String url;
  final DateTime expiresAt;

  bool isUsable(DateTime now) =>
      expiresAt.isAfter(now.add(MessageImageService._expirySafetyMargin));
}
