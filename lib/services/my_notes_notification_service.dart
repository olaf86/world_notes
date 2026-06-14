import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class MyNotesNotificationService {
  static const _nativeLaunchChannel = MethodChannel(
    'world_notes/notification_launch',
  );

  final FirebaseMessaging _messaging;
  final FirebaseFunctions _functions;
  final FirebaseAuth _auth;

  StreamSubscription<String>? _tokenRefreshSub;

  MyNotesNotificationService({
    required FirebaseMessaging messaging,
    required FirebaseFunctions functions,
    required FirebaseAuth auth,
  }) : _messaging = messaging,
       _functions = functions,
       _auth = auth;

  Future<bool> enableMyNotesNotifications() async {
    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );
    final granted = _isGranted(settings.authorizationStatus);
    if (!granted) return false;

    await _messaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );
    await registerCurrentToken();
    await _functions
        .httpsCallable('setMyNotesNotificationEnabled')
        .call<Map<String, dynamic>>({'enabled': true});
    return true;
  }

  Future<void> disableMyNotesNotifications() async {
    await _functions
        .httpsCallable('setMyNotesNotificationEnabled')
        .call<Map<String, dynamic>>({'enabled': false});
  }

  Future<void> registerCurrentToken() async {
    if (_auth.currentUser == null) return;
    final settings = await _messaging.getNotificationSettings();
    if (!_isGranted(settings.authorizationStatus)) return;

    final token = await _currentFcmToken();
    if (token == null || token.isEmpty) return;
    await _registerToken(token);
  }

  Future<void> deleteCurrentToken() async {
    if (_auth.currentUser == null) return;
    final token = await _currentFcmToken();
    if (token == null || token.isEmpty) return;
    await _functions.httpsCallable('deleteFcmToken').call<Map<String, dynamic>>(
      {'token': token},
    );
  }

  void startTokenRefreshHandling(Future<bool> Function() isEnabled) {
    _tokenRefreshSub ??= _messaging.onTokenRefresh.listen((token) async {
      if (_auth.currentUser == null) return;
      if (!await isEnabled()) return;
      await _registerToken(token);
    });
  }

  Future<String?> initialPlaceIdFromLaunch() async {
    final message = await _messaging.getInitialMessage();
    final placeId = placeIdFromMessage(message);
    if (placeId != null && placeId.isNotEmpty) return placeId;
    return _initialPlaceIdFromNativeLaunch();
  }

  Stream<String> get openedPlaceIds {
    return FirebaseMessaging.onMessageOpenedApp
        .map(placeIdFromMessage)
        .where((placeId) => placeId != null && placeId.isNotEmpty)
        .cast<String>();
  }

  Future<void> dispose() async {
    await _tokenRefreshSub?.cancel();
  }

  Future<void> _registerToken(String token) async {
    await _functions
        .httpsCallable('registerFcmToken')
        .call<Map<String, dynamic>>({'token': token, 'platform': _platform});
  }

  Future<String?> _currentFcmToken() async {
    if (_requiresApnsToken) {
      final apnsToken = await _messaging.getAPNSToken();
      if (apnsToken == null || apnsToken.isEmpty) return null;
    }
    return _messaging.getToken();
  }

  Future<String?> _initialPlaceIdFromNativeLaunch() async {
    if (defaultTargetPlatform != TargetPlatform.iOS) return null;
    try {
      final placeId = await _nativeLaunchChannel.invokeMethod<String>(
        'takeInitialPlaceId',
      );
      return placeId != null && placeId.isNotEmpty ? placeId : null;
    } on MissingPluginException {
      return null;
    }
  }

  static String? placeIdFromMessage(RemoteMessage? message) {
    final type = message?.data['type'];
    if (type != 'my_note_message' && type != 'nearby_note_message') {
      return null;
    }
    final placeId = message?.data['placeId'];
    return placeId is String && placeId.isNotEmpty ? placeId : null;
  }

  static bool _isGranted(AuthorizationStatus status) {
    return status == AuthorizationStatus.authorized ||
        status == AuthorizationStatus.provisional;
  }

  static String get _platform {
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => 'android',
      TargetPlatform.iOS => 'ios',
      TargetPlatform.macOS => 'macos',
      _ => 'unknown',
    };
  }

  static bool get _requiresApnsToken {
    return defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS;
  }
}
