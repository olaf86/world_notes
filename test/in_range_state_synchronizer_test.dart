import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:world_notes/services/in_range_state_synchronizer.dart';

void main() {
  test('coalesces concurrent duplicate states into one write', () async {
    final writes = <({String placeId, bool inRange})>[];
    final firstWrite = Completer<void>();
    final synchronizer = InRangeStateSynchronizer(({
      required placeId,
      required inRange,
    }) async {
      writes.add((placeId: placeId, inRange: inRange));
      await firstWrite.future;
    });

    final first = synchronizer.setState(placeId: 'place-1', inRange: true);
    final duplicate = synchronizer.setState(placeId: 'place-1', inRange: true);
    await Future<void>.delayed(Duration.zero);

    expect(writes, [(placeId: 'place-1', inRange: true)]);
    firstWrite.complete();
    expect(await first, isTrue);
    expect(await duplicate, isFalse);
    expect(writes, hasLength(1));
  });

  test('preserves the order of opposite transitions', () async {
    final writes = <bool>[];
    final synchronizer = InRangeStateSynchronizer(({
      required placeId,
      required inRange,
    }) async {
      writes.add(inRange);
    });

    await Future.wait([
      synchronizer.setState(placeId: 'place-1', inRange: true),
      synchronizer.setState(placeId: 'place-1', inRange: false),
    ]);

    expect(writes, [true, false]);
    expect(synchronizer.inRangePlaceIds, isEmpty);
  });

  test('can assume an initial outside state without writing it', () async {
    var writes = 0;
    final synchronizer = InRangeStateSynchronizer(({
      required placeId,
      required inRange,
    }) async {
      writes += 1;
    });

    expect(
      await synchronizer.setState(
        placeId: 'place-1',
        inRange: false,
        assumeIfUnknown: true,
      ),
      isFalse,
    );
    expect(writes, 0);
    expect(
      await synchronizer.setState(placeId: 'place-1', inRange: true),
      isTrue,
    );
    expect(writes, 1);
  });

  test(
    'confirms an assumed state only once when the server may differ',
    () async {
      var writes = 0;
      final synchronizer = InRangeStateSynchronizer(({
        required placeId,
        required inRange,
      }) async {
        writes += 1;
      });

      await synchronizer.setState(
        placeId: 'place-1',
        inRange: false,
        assumeIfUnknown: true,
      );
      final first = synchronizer.setState(
        placeId: 'place-1',
        inRange: false,
        confirmIfAssumed: true,
      );
      final duplicate = synchronizer.setState(
        placeId: 'place-1',
        inRange: false,
        confirmIfAssumed: true,
      );

      expect(await first, isTrue);
      expect(await duplicate, isFalse);
      expect(writes, 1);
    },
  );

  test('retries a state after a failed write', () async {
    var attempts = 0;
    final synchronizer = InRangeStateSynchronizer(({
      required placeId,
      required inRange,
    }) async {
      attempts += 1;
      if (attempts == 1) throw StateError('temporary failure');
    });

    await expectLater(
      synchronizer.setState(placeId: 'place-1', inRange: true),
      throwsStateError,
    );
    expect(
      await synchronizer.setState(placeId: 'place-1', inRange: true),
      isTrue,
    );
    expect(attempts, 2);
  });

  test('forgetAll makes the next matching event refresh the server', () async {
    var writes = 0;
    final synchronizer = InRangeStateSynchronizer(({
      required placeId,
      required inRange,
    }) async {
      writes += 1;
    });

    await synchronizer.setState(placeId: 'place-1', inRange: true);
    synchronizer.forgetAll();
    await synchronizer.setState(placeId: 'place-1', inRange: true);

    expect(writes, 2);
  });
}
