import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:world_notes/config/world_catalog.dart';
import 'package:world_notes/domain/entities/global_operation_entity.dart';
import 'package:world_notes/domain/repositories/global_operation_repository.dart';
import 'package:world_notes/services/global_operation_observer.dart';

void main() {
  const storageKey = 'global_operations_v1:test-user';

  test('persists pending work and forgets it after completion', () async {
    SharedPreferences.setMockInitialValues(const {});
    final preferences = await SharedPreferences.getInstance();
    final repository = _FakeGlobalOperationRepository();
    addTearDown(repository.dispose);
    final errors = <Object>[];
    final observer = GlobalOperationObserver(
      userId: 'test-user',
      repository: repository,
      preferences: preferences,
      reportError: (error, _) async => errors.add(error),
    );
    addTearDown(observer.dispose);
    const authority = WorldId('asia');
    final reference = GlobalOperationReference(
      authorityWorld: authority,
      operationId: '00000000-0000-700a-800b-000000000001',
    );

    await observer.track(reference);
    expect(repository.watched, [reference]);
    expect(
      jsonDecode(preferences.getString(storageKey)!) as List,
      hasLength(1),
    );

    repository.add(_operation(reference, GlobalOperationStatus.pending));
    await pumpEventQueue();
    expect(preferences.containsKey(storageKey), isTrue);

    repository.add(_operation(reference, GlobalOperationStatus.complete));
    await pumpEventQueue();
    expect(preferences.containsKey(storageKey), isFalse);
    expect(errors, isEmpty);
  });

  test('restores a remembered authority route after app relaunch', () async {
    final stored = jsonEncode([
      {
        'authorityWorld': 'europe',
        'operationId': '00000000-0000-700a-800b-000000000002',
      },
    ]);
    SharedPreferences.setMockInitialValues({storageKey: stored});
    final preferences = await SharedPreferences.getInstance();
    final repository = _FakeGlobalOperationRepository();
    addTearDown(repository.dispose);
    final observer = GlobalOperationObserver(
      userId: 'test-user',
      repository: repository,
      preferences: preferences,
      reportError: (_, _) async {},
    );
    addTearDown(observer.dispose);

    await observer.start();

    expect(repository.watched, hasLength(1));
    expect(repository.watched.single.authorityWorld, const WorldId('europe'));
  });

  test('tracks only pending callable responses', () async {
    SharedPreferences.setMockInitialValues(const {});
    final preferences = await SharedPreferences.getInstance();
    final repository = _FakeGlobalOperationRepository();
    addTearDown(repository.dispose);
    final observer = GlobalOperationObserver(
      userId: 'test-user',
      repository: repository,
      preferences: preferences,
      reportError: (_, _) async {},
    );
    addTearDown(observer.dispose);

    await observer.trackAcceptedResponse({
      'authorityWorld': 'asia',
      'operationId': '00000000-0000-700a-800b-000000000003',
      'status': 'complete',
    });
    expect(repository.watched, isEmpty);

    await observer.trackAcceptedResponse({
      'authorityWorld': 'asia',
      'operationId': '00000000-0000-700a-800b-000000000004',
      'status': 'pending',
    });
    expect(repository.watched, hasLength(1));
  });
}

GlobalOperationEntity _operation(
  GlobalOperationReference reference,
  GlobalOperationStatus status,
) {
  return GlobalOperationEntity(
    reference: reference,
    operationType: 'testOperation',
    entityId: 'test-entity',
    revision: 1,
    status: status,
    acceptedAt: DateTime.utc(2026),
    requiredWorlds: const [WorldId('asia')],
    acknowledgedWorlds: {const WorldId('asia')},
    completedAt: status == GlobalOperationStatus.pending
        ? null
        : DateTime.utc(2026, 1, 1, 0, 1),
  );
}

final class _FakeGlobalOperationRepository
    implements GlobalOperationRepository {
  final _controller = StreamController<GlobalOperationEntity>.broadcast();
  final List<GlobalOperationReference> watched = [];

  @override
  Stream<GlobalOperationEntity> watchOperation(
    GlobalOperationReference reference,
  ) {
    watched.add(reference);
    return _controller.stream;
  }

  void add(GlobalOperationEntity operation) => _controller.add(operation);

  Future<void> dispose() => _controller.close();
}
