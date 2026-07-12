import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/entities/public_profile_entity.dart';

class PublicProfileModel {
  final String id;
  final String displayName;
  final String? photoUrl;
  final int followerCount;
  final int followingCount;

  const PublicProfileModel({
    required this.id,
    required this.displayName,
    this.photoUrl,
    this.followerCount = 0,
    this.followingCount = 0,
  });

  factory PublicProfileModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data()! as Map<String, dynamic>;
    return PublicProfileModel.fromFirestoreData(doc.id, data);
  }

  factory PublicProfileModel.fromFirestoreData(
    String id,
    Map<String, dynamic> data,
  ) {
    return PublicProfileModel(
      id: id,
      displayName: data['displayName'] as String,
      photoUrl: data['photoUrl'] as String?,
      followerCount: data['followerCount'] as int,
      followingCount: data['followingCount'] as int,
    );
  }

  Map<String, dynamic> toOwnerFirestore({required bool includeCounts}) {
    return {
      'displayName': displayName,
      'photoUrl': photoUrl,
      if (includeCounts) ...{'followerCount': 0, 'followingCount': 0},
      'updatedAt': FieldValue.serverTimestamp(),
      if (includeCounts) 'createdAt': FieldValue.serverTimestamp(),
    };
  }

  PublicProfile toEntity() => PublicProfile(
    id: id,
    displayName: displayName,
    photoUrl: photoUrl,
    followerCount: followerCount,
    followingCount: followingCount,
  );

  factory PublicProfileModel.fromEntity(PublicProfile entity) {
    return PublicProfileModel(
      id: entity.id,
      displayName: entity.displayName,
      photoUrl: entity.photoUrl,
      followerCount: entity.followerCount,
      followingCount: entity.followingCount,
    );
  }
}
