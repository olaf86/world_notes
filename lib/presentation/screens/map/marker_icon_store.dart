import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;

import '../../../domain/entities/pin_summary_entity.dart';

/// Owns the lifecycle of prepared marker icons independently of a map view.
///
/// The shared limiter applies across overlapping pin generations, so a stale
/// generation finishing in the background cannot exceed the configured cap
/// together with the latest generation.
class MarkerIconStore<T> {
  static const int defaultMaxConcurrent = 4;

  MarkerIconStore({int maxConcurrent = defaultMaxConcurrent})
    : _limiter = _AsyncLimiter(maxConcurrent);

  final _iconsByCacheKey = <String, T>{};
  final _pendingIconsByCacheKey = <String, Future<T>>{};
  final _preparedIconsByPlaceId = <String, T>{};
  final _AsyncLimiter _limiter;

  T? preparedFor(String placeId) => _preparedIconsByPlaceId[placeId];

  void retainPlaces(Iterable<PinSummary> pins) {
    final placeIds = pins.map((pin) => pin.placeId).toSet();
    _preparedIconsByPlaceId.removeWhere(
      (placeId, _) => !placeIds.contains(placeId),
    );
  }

  Future<T> cached(String cacheKey, Future<T> Function() build) async {
    final cached = _iconsByCacheKey[cacheKey];
    if (cached != null) return cached;
    final pending = _pendingIconsByCacheKey[cacheKey];
    if (pending != null) return pending;

    final future = build();
    _pendingIconsByCacheKey[cacheKey] = future;
    try {
      final icon = await future;
      _iconsByCacheKey[cacheKey] = icon;
      return icon;
    } finally {
      if (identical(_pendingIconsByCacheKey[cacheKey], future)) {
        _pendingIconsByCacheKey.remove(cacheKey);
      }
    }
  }

  Future<void> prepare(
    Iterable<PinSummary> pins, {
    required bool Function() isCurrent,
    required Future<T> Function(PinSummary pin) load,
    FutureOr<void> Function()? afterBatch,
  }) async {
    final pending = pins.toList(growable: false);
    final batchSize = _limiter.maxConcurrent;
    for (var offset = 0; offset < pending.length; offset += batchSize) {
      final end = math.min(offset + batchSize, pending.length);
      await Future.wait(
        pending
            .sublist(offset, end)
            .map(
              (pin) => _limiter.run(() async {
                if (!isCurrent()) return;
                final icon = await load(pin);
                if (isCurrent()) _preparedIconsByPlaceId[pin.placeId] = icon;
              }),
            ),
        eagerError: true,
      );
      if (isCurrent()) await afterBatch?.call();
    }
  }
}

class _AsyncLimiter {
  _AsyncLimiter(this.maxConcurrent) {
    if (maxConcurrent < 1) {
      throw ArgumentError.value(
        maxConcurrent,
        'maxConcurrent',
        'Must be at least 1.',
      );
    }
  }

  final int maxConcurrent;
  final Queue<Completer<void>> _waiters = Queue<Completer<void>>();
  int _active = 0;

  Future<R> run<R>(Future<R> Function() action) async {
    if (_active >= maxConcurrent) {
      final waiter = Completer<void>();
      _waiters.add(waiter);
      await waiter.future;
    } else {
      _active += 1;
    }
    try {
      return await action();
    } finally {
      if (_waiters.isNotEmpty) {
        // Transfer this occupied slot directly to the next waiter. Keeping
        // [_active] unchanged prevents a newcomer from stealing the slot
        // before the resumed waiter gets to run.
        _waiters.removeFirst().complete();
      } else {
        _active -= 1;
      }
    }
  }
}
