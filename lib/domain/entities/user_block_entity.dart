import 'public_profile_entity.dart';

class UserBlock {
  final PublicProfile profile;
  final DateTime updatedAt;

  const UserBlock({required this.profile, required this.updatedAt});

  String get userId => profile.id;
}
