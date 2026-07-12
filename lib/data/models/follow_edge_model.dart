import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/entities/follow_entity.dart';

class FollowEdgeModel {
  final String id;
  final String followerUid;
  final String followeeUid;
  final DateTime createdAt;

  const FollowEdgeModel({
    required this.id,
    required this.followerUid,
    required this.followeeUid,
    required this.createdAt,
  });

  factory FollowEdgeModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data()! as Map<String, dynamic>;
    return FollowEdgeModel(
      id: doc.id,
      followerUid: data['followerUid'] as String,
      followeeUid: data['followeeUid'] as String,
      createdAt: (data['createdAt'] as Timestamp).toDate(),
    );
  }

  FollowEdge toEntity() => FollowEdge(
    id: id,
    followerUid: followerUid,
    followeeUid: followeeUid,
    createdAt: createdAt,
  );
}
