import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';

import '../../domain/entities/public_profile_entity.dart';
import '../../domain/entities/user_block_entity.dart';
import '../../domain/repositories/user_block_repository.dart';
import '../../services/world_firebase_clients.dart';
import '../../services/global_operation_observer.dart';
import '../models/public_profile_model.dart';
import '../models/user_block_model.dart';

class UserBlockRepositoryImpl implements UserBlockRepository {
  final FirebaseFirestore _firestore;
  final WorldFunctionsClient _functions;
  final GlobalOperationObserver? _operationObserver;
  final Uuid _uuid = const Uuid();

  UserBlockRepositoryImpl({
    required FirebaseFirestore firestore,
    required WorldFunctionsClient functions,
    required GlobalOperationObserver? operationObserver,
  }) : _firestore = firestore,
       _functions = functions,
       _operationObserver = operationObserver;

  CollectionReference _blocksOf(String blockerUserId) => _firestore
      .collection('users')
      .doc(blockerUserId)
      .collection('blockedUsers');

  @override
  Stream<Set<String>> watchBlockedUserIds(String blockerUserId) {
    return _blocksOf(blockerUserId)
        .where('isBlocked', isEqualTo: true)
        .snapshots()
        .map((snapshot) => {for (final doc in snapshot.docs) doc.id});
  }

  @override
  Stream<bool> watchIsBlocked({
    required String blockerUserId,
    required String blockedUserId,
  }) {
    return _blocksOf(blockerUserId)
        .where('blockedUid', isEqualTo: blockedUserId)
        .where('isBlocked', isEqualTo: true)
        .limit(1)
        .snapshots()
        .map((snapshot) => snapshot.docs.isNotEmpty);
  }

  @override
  Stream<List<UserBlock>> watchBlockedUsers(String blockerUserId) {
    return _blocksOf(blockerUserId)
        .where('isBlocked', isEqualTo: true)
        .orderBy('updatedAt', descending: true)
        .snapshots()
        .asyncMap((snapshot) async {
          final blockModels = snapshot.docs
              .map(UserBlockModel.fromFirestore)
              .toList();
          final profileDocs = await Future.wait(
            blockModels.map(
              (block) => _firestore
                  .collection('publicProfiles')
                  .doc(block.blockedUserId)
                  .get(),
            ),
          );
          final profiles = <String, PublicProfile>{
            for (final doc in profileDocs)
              if (doc.exists)
                doc.id: PublicProfileModel.fromFirestore(doc).toEntity(),
          };
          return [
            for (final block in blockModels)
              UserBlock(
                profile:
                    profiles[block.blockedUserId] ??
                    PublicProfile(
                      id: block.blockedUserId,
                      displayName: block.blockedUserId,
                      photoVersion: 1,
                    ),
                updatedAt: block.updatedAt,
              ),
          ];
        });
  }

  @override
  Future<void> setBlocked({
    required String targetUserId,
    required bool blocked,
  }) async {
    final response = await _functions
        .httpsCallable('setUserBlock')
        .call<Map<String, dynamic>>({
          'targetUserId': targetUserId,
          'blocked': blocked,
          'operationId': _uuid.v7(),
        });
    await handleAcceptedGlobalOperation(
      response: response.data,
      policy: GlobalOperationObservationPolicy.durable,
      observer: _operationObserver,
    );
  }
}
