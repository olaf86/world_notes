import '../../config/world_catalog.dart';
import '../../domain/entities/global_operation_entity.dart';
import '../../domain/repositories/global_operation_repository.dart';
import '../../services/world_firebase_clients.dart';
import '../models/global_operation_model.dart';

final class GlobalOperationRepositoryImpl implements GlobalOperationRepository {
  const GlobalOperationRepositoryImpl({
    required WorldCatalog catalog,
    required WorldFirebaseClientCache clients,
  }) : _catalog = catalog,
       _clients = clients;

  final WorldCatalog _catalog;
  final WorldFirebaseClientCache _clients;

  @override
  Stream<GlobalOperationEntity> watchOperation(
    GlobalOperationReference reference,
  ) {
    final world = _catalog.requireWorld(reference.authorityWorld);
    final firestore = _clients.forWorld(world).firestore;
    return firestore
        .collection('globalOperations')
        .doc(reference.operationId)
        .snapshots()
        .map(
          (snapshot) => GlobalOperationModel.fromFirestore(
            reference: reference,
            snapshot: snapshot,
            catalog: _catalog,
          ),
        );
  }
}
