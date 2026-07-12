import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../../domain/entities/follow_entity.dart';
import '../../domain/entities/public_profile_entity.dart';
import '../../domain/repositories/follow_repository.dart';
import '../models/follow_edge_model.dart';
import '../models/public_profile_model.dart';

class FollowRepositoryImpl implements FollowRepository {
  static const int defaultPageSize = 20;

  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;

  FollowRepositoryImpl({
    required FirebaseFirestore firestore,
    required FirebaseFunctions functions,
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
        .doc(socialEdgeId(followerUid: followerUid, followeeUid: followeeUid))
        .snapshots()
        .map((doc) => doc.exists);
  }

  @override
  Future<void> setFollowing({
    required String targetUserId,
    required bool following,
  }) async {
    await _functions.httpsCallable('setUserFollow').call<void>({
      'targetUserId': targetUserId,
      'following': following,
    });
  }

  @override
  Future<FollowPage> listFollowing({
    required String userId,
    Object? cursor,
    int limit = defaultPageSize,
  }) {
    return _list(
      field: 'followerUid',
      userId: userId,
      profileIdFor: (edge) => edge.followeeUid,
      cursor: cursor,
      limit: limit,
    );
  }

  @override
  Future<FollowPage> listFollowers({
    required String userId,
    Object? cursor,
    int limit = defaultPageSize,
  }) {
    return _list(
      field: 'followeeUid',
      userId: userId,
      profileIdFor: (edge) => edge.followerUid,
      cursor: cursor,
      limit: limit,
    );
  }

  Future<FollowPage> _list({
    required String field,
    required String userId,
    required String Function(FollowEdge edge) profileIdFor,
    required Object? cursor,
    required int limit,
  }) async {
    Query query = _edges
        .where(field, isEqualTo: userId)
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
    return PublicProfile(id: userId, displayName: userId);
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
