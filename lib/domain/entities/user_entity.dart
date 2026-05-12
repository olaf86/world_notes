class UserEntity {
  final String id;
  final String name;
  final String? email;
  final String? photoUrl;
  final bool isPremium;

  const UserEntity({
    required this.id,
    required this.name,
    this.email,
    this.photoUrl,
    this.isPremium = false,
  });

  UserEntity copyWith({
    String? id,
    String? name,
    String? email,
    String? photoUrl,
    bool? isPremium,
  }) {
    return UserEntity(
      id: id ?? this.id,
      name: name ?? this.name,
      email: email ?? this.email,
      photoUrl: photoUrl ?? this.photoUrl,
      isPremium: isPremium ?? this.isPremium,
    );
  }
}
