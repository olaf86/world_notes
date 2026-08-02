import 'package:cloud_firestore/cloud_firestore.dart';

import '../../config/world_catalog.dart';
import '../../domain/entities/global_operation_entity.dart';

final class GlobalOperationModel {
  const GlobalOperationModel._();

  static GlobalOperationEntity fromFirestore({
    required GlobalOperationReference reference,
    required DocumentSnapshot<Map<String, dynamic>> snapshot,
    required WorldCatalog catalog,
  }) {
    final data = snapshot.data();
    if (data == null) {
      throw StateError('Global operation no longer exists.');
    }
    return fromData(
      reference: reference,
      documentId: snapshot.id,
      data: data,
      catalog: catalog,
    );
  }

  static GlobalOperationEntity fromData({
    required GlobalOperationReference reference,
    required String documentId,
    required Map<String, dynamic> data,
    required WorldCatalog catalog,
  }) {
    if (documentId != reference.operationId ||
        data['operationId'] != reference.operationId ||
        data['authorityWorld'] != reference.authorityWorld.value) {
      throw const FormatException('Global operation route is invalid.');
    }

    final operationType = _string(data['operationType'], 'operationType');
    final entityId = _string(data['entityId'], 'entityId');
    final revision = data['revision'];
    if (revision is! int || revision <= 0) {
      throw const FormatException('Global operation revision is invalid.');
    }
    final acceptedAt = _timestamp(data['acceptedAt'], 'acceptedAt');
    final completedAt = data['completedAt'] == null
        ? null
        : _timestamp(data['completedAt'], 'completedAt');
    final failureCode = data['failureCode'] == null
        ? null
        : _string(data['failureCode'], 'failureCode');
    final requiredWorlds = _worldList(
      data['requiredWorlds'],
      catalog,
      'requiredWorlds',
    );
    final worldAcks = data['worldAcks'];
    if (worldAcks is! Map) {
      throw const FormatException('Global operation acknowledgements invalid.');
    }
    final acknowledgedWorlds = <WorldId>{};
    for (final key in worldAcks.keys) {
      if (key is! String) {
        throw const FormatException(
          'Global operation acknowledgement world is invalid.',
        );
      }
      final worldId = WorldId(key);
      catalog.requireWorld(worldId);
      if (!requiredWorlds.contains(worldId)) {
        throw const FormatException(
          'Global operation acknowledgement is out of scope.',
        );
      }
      final acknowledgement = worldAcks[key];
      if (acknowledgement is! Map ||
          acknowledgement['revision'] != revision ||
          acknowledgement['acknowledgedAt'] is! Timestamp) {
        throw const FormatException(
          'Global operation acknowledgement is invalid.',
        );
      }
      acknowledgedWorlds.add(worldId);
    }

    final status = GlobalOperationStatus.parse(data['status']);
    final allAcknowledged = requiredWorlds.every(acknowledgedWorlds.contains);
    if (status == GlobalOperationStatus.pending &&
        (completedAt != null || failureCode != null || allAcknowledged)) {
      throw const FormatException('Pending operation cannot be completed.');
    }
    if (status == GlobalOperationStatus.complete &&
        (completedAt == null || failureCode != null || !allAcknowledged)) {
      throw const FormatException('Completed operation fields are invalid.');
    }
    if (status == GlobalOperationStatus.failed &&
        (completedAt == null || failureCode == null)) {
      throw const FormatException('Terminal operation must be completed.');
    }
    if (completedAt != null && completedAt.compareTo(acceptedAt) < 0) {
      throw const FormatException('Global operation timestamps are invalid.');
    }

    return GlobalOperationEntity(
      reference: reference,
      operationType: operationType,
      entityId: entityId,
      revision: revision,
      status: status,
      acceptedAt: acceptedAt.toDate(),
      requiredWorlds: List.unmodifiable(requiredWorlds),
      acknowledgedWorlds: Set.unmodifiable(acknowledgedWorlds),
      completedAt: completedAt?.toDate(),
      failureCode: failureCode,
    );
  }
}

String _string(Object? value, String field) {
  if (value is! String || value.isEmpty) {
    throw FormatException('Global operation $field is invalid.');
  }
  return value;
}

Timestamp _timestamp(Object? value, String field) {
  if (value is! Timestamp) {
    throw FormatException('Global operation $field is invalid.');
  }
  return value;
}

List<WorldId> _worldList(Object? value, WorldCatalog catalog, String field) {
  if (value is! List || value.isEmpty) {
    throw FormatException('Global operation $field is invalid.');
  }
  final result = <WorldId>[];
  for (final item in value) {
    if (item is! String) {
      throw FormatException('Global operation $field is invalid.');
    }
    final worldId = WorldId(item);
    catalog.requireWorld(worldId);
    if (result.contains(worldId)) {
      throw FormatException('Global operation $field contains duplicates.');
    }
    result.add(worldId);
  }
  return result;
}
