import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/entities/follow_entity.dart';

class FollowEdgeModel {
  final String id;
  final String followerUid;
  final String followeeUid;
  final int revision;
  final DateTime createdAt;
  final DateTime updatedAt;

  const FollowEdgeModel({
    required this.id,
    required this.followerUid,
    required this.followeeUid,
    required this.revision,
    required this.createdAt,
    required this.updatedAt,
  });

  factory FollowEdgeModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data()! as Map<String, dynamic>;
    if (data['following'] != true) {
      throw const FormatException('Follow list contains an inactive edge.');
    }
    return FollowEdgeModel(
      id: doc.id,
      followerUid: data['followerUid'] as String,
      followeeUid: data['followeeUid'] as String,
      revision: data['revision'] as int,
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      updatedAt: (data['updatedAt'] as Timestamp).toDate(),
    );
  }

  FollowEdge toEntity() => FollowEdge(
    id: id,
    followerUid: followerUid,
    followeeUid: followeeUid,
    createdAt: createdAt,
  );
}
