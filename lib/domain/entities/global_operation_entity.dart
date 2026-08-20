import '../../config/world_catalog.dart';

enum GlobalOperationStatus {
  pending('pending'),
  complete('complete'),
  failed('failed');

  const GlobalOperationStatus(this.wireValue);

  final String wireValue;

  static GlobalOperationStatus parse(Object? value) {
    for (final status in values) {
      if (status.wireValue == value) return status;
    }
    throw const FormatException('Global operation status is invalid.');
  }
}

/// Durable address persisted by the initiating client until terminal state.
final class GlobalOperationReference {
  GlobalOperationReference({
    required this.authorityWorld,
    required this.operationId,
  }) {
    if (operationId.isEmpty ||
        operationId.trim() != operationId ||
        operationId.contains('/')) {
      throw ArgumentError.value(
        operationId,
        'operationId',
        'Must be one non-empty document ID.',
      );
    }
  }

  final WorldId authorityWorld;
  final String operationId;

  @override
  bool operator ==(Object other) {
    return other is GlobalOperationReference &&
        other.authorityWorld == authorityWorld &&
        other.operationId == operationId;
  }

  @override
  int get hashCode => Object.hash(authorityWorld, operationId);
}

/// Client-visible progress for one accepted global command.
final class GlobalOperationEntity {
  const GlobalOperationEntity({
    required this.reference,
    required this.operationType,
    required this.entityId,
    required this.revision,
    required this.status,
    required this.acceptedAt,
    required this.requiredWorlds,
    required this.acknowledgedWorlds,
    this.completedAt,
    this.failureCode,
  });

  final GlobalOperationReference reference;
  final String operationType;
  final String entityId;
  final int revision;
  final GlobalOperationStatus status;
  final DateTime acceptedAt;
  final List<WorldId> requiredWorlds;
  final Set<WorldId> acknowledgedWorlds;
  final DateTime? completedAt;
  final String? failureCode;

  bool get isTerminal => status != GlobalOperationStatus.pending;
}
