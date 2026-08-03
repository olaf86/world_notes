import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';

import '../../domain/entities/follow_entity.dart';
import '../../domain/entities/public_profile_entity.dart';
import '../../domain/repositories/follow_repository.dart';
import '../../services/world_firebase_clients.dart';
import '../../services/global_operation_observer.dart';
import '../models/follow_edge_model.dart';
import '../models/public_profile_model.dart';

class FollowRepositoryImpl implements FollowRepository {
  static const int defaultPageSize = 20;

  final FirebaseFirestore _firestore;
  final WorldFunctionsClient _functions;
  final Uuid _uuid = const Uuid();

  FollowRepositoryImpl({
    required FirebaseFirestore firestore,
    required WorldFunctionsClient functions,
  }) : _firestore = firestore,
       _functions = functions;

  CollectionReference get _edges => _firestore.collection('socialEdges');
  CollectionReference get _profiles => _firestore.collection('publicProfiles');

  @override
  Stream<PublicProfile?> watchPublicProfile(String userId) {
    return _profiles.doc(userId).snapshots().map((doc) {
      if (!doc.exists) return null;
      return PublicProfileModel.fromFirestore(doc).toEntity();
    });
  }

  @override
  Stream<bool> watchIsFollowing({
    required String followerUid,
    required String followeeUid,
  }) {
    return _edges
        .where('followerUid', isEqualTo: followerUid)
        .where('followeeUid', isEqualTo: followeeUid)
        .where('following', isEqualTo: true)
        .limit(1)
        .snapshots()
        .map((snapshot) => snapshot.docs.isNotEmpty);
  }

  @override
  Future<void> setFollowing({
    required String targetUserId,
    required bool following,
  }) async {
    final response = await _functions
        .httpsCallable('setUserFollow')
        .call<Map<String, dynamic>>({
          'targetUserId': targetUserId,
          'following': following,
          'operationId': _uuid.v7(),
        });
    await handleAcceptedGlobalOperation(
      response: response.data,
      policy: GlobalOperationObservationPolicy.none,
      observer: null,
    );
  }

  @override
  Future<FollowPage> listFollowing({
    required String userId,
    Object? cursor,
    int limit = defaultPageSize,
    Set<String> excludedUserIds = const {},
  }) {
    return _list(
      field: 'followerUid',
      userId: userId,
      profileIdFor: (edge) => edge.followeeUid,
      cursor: cursor,
      limit: limit,
      excludedUserIds: excludedUserIds,
    );
  }

  @override
  Future<FollowPage> listFollowers({
    required String userId,
    Object? cursor,
    int limit = defaultPageSize,
    Set<String> excludedUserIds = const {},
  }) {
    return _list(
      field: 'followeeUid',
      userId: userId,
      profileIdFor: (edge) => edge.followerUid,
      cursor: cursor,
      limit: limit,
      excludedUserIds: excludedUserIds,
    );
  }

  Future<FollowPage> _list({
    required String field,
    required String userId,
    required String Function(FollowEdge edge) profileIdFor,
    required Object? cursor,
    required int limit,
    required Set<String> excludedUserIds,
  }) async {
    Query query = _edges
        .where(field, isEqualTo: userId)
        .where('following', isEqualTo: true)
        .orderBy('createdAt', descending: true)
        .limit(limit);

    if (cursor != null) {
      query = query.startAfterDocument(cursor as DocumentSnapshot);
    }

    final snap = await query.get();
    final edges = snap.docs
        .map(FollowEdgeModel.fromFirestore)
        .map((model) => model.toEntity())
        .toList();
    final profileIds = {for (final edge in edges) profileIdFor(edge)};
    final profiles = await _loadProfiles(profileIds);
    final items = [
      for (final edge in edges)
        if (!excludedUserIds.contains(profileIdFor(edge)))
          FollowListItem(
            profile:
                profiles[profileIdFor(edge)] ??
                _missingProfile(profileIdFor(edge)),
            followedAt: edge.createdAt,
          ),
    ];

    return FollowPage(
      items: items,
      nextCursor: snap.docs.isEmpty ? null : snap.docs.last,
      hasMore: snap.docs.length == limit,
    );
  }

  Future<Map<String, PublicProfile>> _loadProfiles(Set<String> userIds) async {
    if (userIds.isEmpty) return const {};
    final docs = await Future.wait(
      userIds.map((uid) => _profiles.doc(uid).get()),
    );
    return {
      for (final doc in docs)
        if (doc.exists)
          doc.id: PublicProfileModel.fromFirestore(doc).toEntity(),
    };
  }

  PublicProfile _missingProfile(String userId) {
    return PublicProfile(id: userId, displayName: userId, photoVersion: 1);
  }
}

String socialEdgeId({
  required String followerUid,
  required String followeeUid,
}) {
  String token(String value) {
    return base64Url.encode(utf8.encode(value)).replaceAll('=', '');
  }

  return '${token(followerUid)}.${token(followeeUid)}';
}
