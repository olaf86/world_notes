import '../entities/user_entity.dart';

abstract class AuthRepository {
  Stream<UserEntity?> get authStateChanges;
  Future<UserEntity> signInWithGoogle();
  Future<UserEntity> signInWithApple();
  Future<UserEntity> signInWithEmail(String email, String password);
  Future<UserEntity> signUpWithEmail(
    String email,
    String password,
    String name,
  );
  Future<UserEntity> updateDisplayName(String displayName);
  bool get requiresPasswordForAccountDeletion;
  Future<void> deleteAccount({String? password});
  Future<void> signOut();
  UserEntity? get currentUser;
}
