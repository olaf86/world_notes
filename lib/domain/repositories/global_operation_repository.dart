import '../entities/global_operation_entity.dart';

abstract interface class GlobalOperationRepository {
  Stream<GlobalOperationEntity> watchOperation(
    GlobalOperationReference reference,
  );
}
