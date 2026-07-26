import 'public_profile_entity.dart';

class UserBlock {
  final PublicProfile profile;
  final DateTime createdAt;

  const UserBlock({required this.profile, required this.createdAt});

  String get userId => profile.id;
}
