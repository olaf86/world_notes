import '../entities/user_entity.dart';

abstract class AuthRepository {
  Stream<UserEntity?> get authStateChanges;
  Future<UserEntity> signInWithGoogle();
  Future<UserEntity> signInWithEmail(String email, String password);
  Future<UserEntity> signUpWithEmail(
    String email,
    String password,
    String name,
  );
  Future<UserEntity> updateDisplayName(String displayName);
  Future<void> signOut();
  UserEntity? get currentUser;
}
