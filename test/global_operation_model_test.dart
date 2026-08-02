import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:world_notes/config/bootstrap_world_catalog.dart';
import 'package:world_notes/config/world_catalog.dart';
import 'package:world_notes/data/models/global_operation_model.dart';
import 'package:world_notes/domain/entities/global_operation_entity.dart';

void main() {
  final reference = GlobalOperationReference(
    authorityWorld: const WorldId('asia'),
    operationId: '00000000-0000-700a-800b-000000000001',
  );

  test('parses pending progress from the authority operation', () {
    final operation = GlobalOperationModel.fromData(
      reference: reference,
      documentId: reference.operationId,
      data: _pendingData(reference),
      catalog: bootstrapWorldCatalog,
    );

    expect(operation.status, GlobalOperationStatus.pending);
    expect(operation.requiredWorlds, const [
      WorldId('asia'),
      WorldId('europe'),
    ]);
    expect(operation.acknowledgedWorlds, {const WorldId('asia')});
    expect(operation.isTerminal, isFalse);
  });

  test('rejects completion before every required world acknowledges', () {
    final invalid = _pendingData(reference)
      ..['status'] = 'complete'
      ..['completedAt'] = Timestamp.fromMillisecondsSinceEpoch(2000);

    expect(
      () => GlobalOperationModel.fromData(
        reference: reference,
        documentId: reference.operationId,
        data: invalid,
        catalog: bootstrapWorldCatalog,
      ),
      throwsFormatException,
    );
  });
}

Map<String, dynamic> _pendingData(GlobalOperationReference reference) {
  final acceptedAt = Timestamp.fromMillisecondsSinceEpoch(1000);
  return {
    'operationId': reference.operationId,
    'operationType': 'testOperation',
    'entityId': 'test-entity',
    'revision': 1,
    'authorityWorld': reference.authorityWorld.value,
    'status': 'pending',
    'acceptedAt': acceptedAt,
    'requiredWorlds': ['asia', 'europe'],
    'worldAcks': {
      'asia': {'revision': 1, 'acknowledgedAt': acceptedAt},
    },
  };
}
