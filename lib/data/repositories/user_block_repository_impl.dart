import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../../domain/entities/public_profile_entity.dart';
import '../../domain/entities/user_block_entity.dart';
import '../../domain/repositories/user_block_repository.dart';
import '../models/public_profile_model.dart';
import '../models/user_block_model.dart';

class UserBlockRepositoryImpl implements UserBlockRepository {
  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;

  UserBlockRepositoryImpl({
    required FirebaseFirestore firestore,
    required FirebaseFunctions functions,
  }) : _firestore = firestore,
       _functions = functions;

  CollectionReference _blocksOf(String blockerUserId) => _firestore
      .collection('users')
      .doc(blockerUserId)
      .collection('blockedUsers');

  @override
  Stream<Set<String>> watchBlockedUserIds(String blockerUserId) {
    return _blocksOf(
      blockerUserId,
    ).snapshots().map((snapshot) => {for (final doc in snapshot.docs) doc.id});
  }

  @override
  Stream<bool> watchIsBlocked({
    required String blockerUserId,
    required String blockedUserId,
  }) {
    return _blocksOf(
      blockerUserId,
    ).doc(blockedUserId).snapshots().map((snapshot) => snapshot.exists);
  }

  @override
  Stream<List<UserBlock>> watchBlockedUsers(String blockerUserId) {
    return _blocksOf(blockerUserId)
        .orderBy('createdAt', descending: true)
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
                createdAt: block.createdAt,
              ),
          ];
        });
  }

  @override
  Future<void> setBlocked({
    required String targetUserId,
    required bool blocked,
  }) async {
    await _functions.httpsCallable('setUserBlock').call<void>({
      'targetUserId': targetUserId,
      'blocked': blocked,
    });
  }
}
