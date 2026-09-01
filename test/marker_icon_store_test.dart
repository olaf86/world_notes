import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:world_notes/domain/entities/pin_summary_entity.dart';
import 'package:world_notes/presentation/screens/map/marker_icon_store.dart';

void main() {
  test('shares the concurrency cap across overlapping preparations', () async {
    final store = MarkerIconStore<String>(maxConcurrent: 2);
    var active = 0;
    var maxActive = 0;

    Future<String> load(PinSummary pin) async {
      active += 1;
      if (active > maxActive) maxActive = active;
      await Future<void>.delayed(const Duration(milliseconds: 2));
      active -= 1;
      return pin.placeId;
    }

    await Future.wait([
      store.prepare(
        [_pin('a'), _pin('b'), _pin('c')],
        isCurrent: () => true,
        load: load,
      ),
      store.prepare(
        [_pin('d'), _pin('e'), _pin('f')],
        isCurrent: () => true,
        load: load,
      ),
    ]);

    expect(maxActive, 2);
  });

  test('shares an in-flight icon build for the same cache key', () async {
    final store = MarkerIconStore<String>();
    final completer = Completer<String>();
    var buildCount = 0;

    Future<String> build() {
      buildCount += 1;
      return completer.future;
    }

    final first = store.cached('shared', build);
    final second = store.cached('shared', build);
    expect(buildCount, 1);

    completer.complete('icon');
    expect(await Future.wait([first, second]), ['icon', 'icon']);
  });
}

PinSummary _pin(String id) {
  final now = DateTime(2026);
  return PinSummary(
    placeId: id,
    latitude: 35.68,
    longitude: 139.76,
    title: 'Pin $id',
    colorHex: '#4CAF50',
    icon: 'place',
    creatorName: 'Alice',
    creatorPhotoVersion: 1,
    messageCount: 0,
    likeCount: 0,
    visitorCount: 0,
    createdAt: now,
    lastActivityAt: now,
    expiresAt: now.add(const Duration(days: 1)),
    isPrivate: false,
    isClosed: false,
    footprintEnabled: false,
    access: PinAccess.openable,
  );
}
