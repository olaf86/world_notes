import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:uuid/uuid.dart';

import '../../domain/entities/user_entity.dart';
import '../../domain/repositories/auth_repository.dart';
import '../../services/subscription_service.dart';
import '../../services/global_operation_observer.dart';
import '../../services/world_firebase_clients.dart';

typedef HomeFunctionsProvider = Future<WorldFunctionsClient> Function();

class AuthRepositoryImpl implements AuthRepository {
  final FirebaseAuth _auth;
  final GoogleSignIn _googleSignIn;
  final HomeFunctionsProvider _functionsProvider;
  final SubscriptionService _subscriptionService;
  final Uuid _uuid = const Uuid();

  AuthRepositoryImpl({
    required FirebaseAuth auth,
    required GoogleSignIn googleSignIn,
    required HomeFunctionsProvider functionsProvider,
    required SubscriptionService subscriptionService,
  }) : _auth = auth,
       _googleSignIn = googleSignIn,
       _functionsProvider = functionsProvider,
       _subscriptionService = subscriptionService;

  @override
  Stream<UserEntity?> get authStateChanges {
    return _auth.authStateChanges().asyncMap((firebaseUser) async {
      if (firebaseUser == null) return null;
      await _subscriptionService.identifyUser(firebaseUser.uid);
      return _toEntity(firebaseUser);
    });
  }

  @override
  UserEntity? get currentUser {
    final firebaseUser = _auth.currentUser;
    if (firebaseUser == null) return null;
    return UserEntity(
      id: firebaseUser.uid,
      name: firebaseUser.displayName ?? 'User',
      email: firebaseUser.email,
      photoUrl: firebaseUser.photoURL,
    );
  }

  @override
  Future<UserEntity> signInWithGoogle() async {
    final googleUser = await _googleSignIn.signIn();
    if (googleUser == null) throw Exception('Google sign in cancelled');

    final googleAuth = await googleUser.authentication;
    final credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );

    final result = await _auth.signInWithCredential(credential);
    await _subscriptionService.identifyUser(result.user!.uid);
    return _toEntity(result.user!);
  }

  @override
  Future<UserEntity> signInWithEmail(String email, String password) async {
    final result = await _auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
    await _subscriptionService.identifyUser(result.user!.uid);
    return _toEntity(result.user!);
  }

  @override
  Future<UserEntity> signUpWithEmail(
    String email,
    String password,
    String name,
  ) async {
    final result = await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
    await result.user!.updateDisplayName(name);
    await _subscriptionService.identifyUser(result.user!.uid);
    return _toEntity(result.user!);
  }

  @override
  Future<UserEntity> updateDisplayName(String displayName) async {
    final firebaseUser = _auth.currentUser;
    if (firebaseUser == null) {
      throw StateError('No signed-in user.');
    }

    final functions = await _functionsProvider();
    final response = await functions
        .httpsCallable('updateDisplayName')
        .call<Map<String, dynamic>>({
          'displayName': displayName,
          'operationId': _uuid.v7(),
        });
    await handleAcceptedGlobalOperation(
      response: response.data,
      policy: GlobalOperationObservationPolicy.none,
      observer: null,
    );
    await firebaseUser.reload();
    return _toEntity(_auth.currentUser ?? firebaseUser);
  }

  @override
  Future<void> signOut() async {
    await Future.wait([_auth.signOut(), _googleSignIn.signOut()]);
  }

  UserEntity _toEntity(User firebaseUser) => UserEntity(
    id: firebaseUser.uid,
    name: firebaseUser.displayName ?? 'User',
    email: firebaseUser.email,
    photoUrl: firebaseUser.photoURL,
  );
}
