import 'package:cloud_firestore/cloud_firestore.dart';

class UserBlockModel {
  final String blockedUserId;
  final DateTime updatedAt;

  const UserBlockModel({required this.blockedUserId, required this.updatedAt});

  factory UserBlockModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data()! as Map<String, dynamic>;
    return UserBlockModel(
      blockedUserId: data['blockedUid']! as String,
      updatedAt: (data['updatedAt'] as Timestamp).toDate(),
    );
  }
}
