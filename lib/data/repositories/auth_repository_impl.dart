import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/entities/user_entity.dart';
import '../../domain/repositories/auth_repository.dart';
import '../../services/my_notes_notification_service.dart';
import '../../services/subscription_service.dart';
import '../models/user_model.dart';

class AuthRepositoryImpl implements AuthRepository {
  final FirebaseAuth _auth;
  final GoogleSignIn _googleSignIn;
  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;
  final MyNotesNotificationService _myNotesNotificationService;
  final SubscriptionService _subscriptionService;

  AuthRepositoryImpl({
    required FirebaseAuth auth,
    required GoogleSignIn googleSignIn,
    required FirebaseFirestore firestore,
    required FirebaseFunctions functions,
    required MyNotesNotificationService myNotesNotificationService,
    required SubscriptionService subscriptionService,
  }) : _auth = auth,
       _googleSignIn = googleSignIn,
       _firestore = firestore,
       _functions = functions,
       _myNotesNotificationService = myNotesNotificationService,
       _subscriptionService = subscriptionService;

  @override
  Stream<UserEntity?> get authStateChanges {
    return _auth.authStateChanges().asyncMap((firebaseUser) async {
      if (firebaseUser == null) return null;
      return _fetchOrCreateUser(firebaseUser);
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
    return _fetchOrCreateUser(result.user!);
  }

  @override
  Future<UserEntity> signInWithEmail(String email, String password) async {
    final result = await _auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
    return _fetchOrCreateUser(result.user!);
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
    return _fetchOrCreateUser(result.user!);
  }

  @override
  Future<UserEntity> updateDisplayName(String displayName) async {
    final firebaseUser = _auth.currentUser;
    if (firebaseUser == null) {
      throw StateError('No signed-in user.');
    }

    await _functions
        .httpsCallable('updateDisplayName')
        .call<Map<String, dynamic>>({'displayName': displayName});
    await firebaseUser.reload();
    return _fetchOrCreateUser(_auth.currentUser ?? firebaseUser);
  }

  @override
  Future<void> signOut() async {
    try {
      await _myNotesNotificationService.deleteCurrentToken();
    } catch (error, stack) {
      debugPrint('FCM token cleanup during sign-out failed: $error\n$stack');
      // Token cleanup is best-effort; never trap the user in a signed-in state.
    }
    await Future.wait([_auth.signOut(), _googleSignIn.signOut()]);
  }

  Future<UserEntity> _fetchOrCreateUser(User firebaseUser) async {
    final docRef = _firestore.collection('users').doc(firebaseUser.uid);
    final doc = await docRef.get();

    late UserEntity entity;
    if (doc.exists) {
      entity = UserModel.fromFirestore(doc).toEntity();
    } else {
      final newUser = UserModel(
        id: firebaseUser.uid,
        name: firebaseUser.displayName ?? 'User',
        email: firebaseUser.email,
        photoUrl: firebaseUser.photoURL,
      );
      await docRef.set(newUser.toFirestore());
      entity = newUser.toEntity();
    }

    await _subscriptionService.identifyUser(entity.id);
    return entity;
  }
}
