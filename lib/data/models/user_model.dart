import 'package:cloud_firestore/cloud_firestore.dart';
import '../../domain/entities/user_entity.dart';

class UserModel {
  final String id;
  final String name;
  final String? email;
  final String? photoUrl;
  final bool isPremium;

  UserModel({
    required this.id,
    required this.name,
    this.email,
    this.photoUrl,
    this.isPremium = false,
  });

  factory UserModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return UserModel.fromFirestoreData(doc.id, data);
  }

  factory UserModel.fromFirestoreData(String id, Map<String, dynamic> data) {
    return UserModel(
      id: id,
      name: data['displayName'] as String,
      email: data['email'] as String?,
      photoUrl: data['photoUrl'] as String?,
      isPremium: data['isPremium'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'displayName': name,
      'email': email,
      'photoUrl': photoUrl,
      'isPremium': isPremium,
    };
  }

  UserEntity toEntity() => UserEntity(
    id: id,
    name: name,
    email: email,
    photoUrl: photoUrl,
    isPremium: isPremium,
  );

  factory UserModel.fromEntity(UserEntity entity) => UserModel(
    id: entity.id,
    name: entity.name,
    email: entity.email,
    photoUrl: entity.photoUrl,
    isPremium: entity.isPremium,
  );
}
