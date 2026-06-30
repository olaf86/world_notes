import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../config/notification_navigation.dart';

class MyNotesNotificationService {
  static const _nativeLaunchChannel = MethodChannel(
    'world_notes/notification_launch',
  );

  final FirebaseMessaging _messaging;
  final FirebaseFunctions _functions;
  final FirebaseAuth _auth;
  final FirebaseCrashlytics _crashlytics;

  StreamSubscription<String>? _tokenRefreshSubscription;
  StreamSubscription<User?>? _authStateSubscription;
  StreamSubscription<NotificationPlaceRoute>? _messageOpenSubscription;
  final _openedPlaceRoutes =
      StreamController<NotificationPlaceRoute>.broadcast();

  MyNotesNotificationService({
    required FirebaseMessaging messaging,
    required FirebaseFunctions functions,
    required FirebaseAuth auth,
    required FirebaseCrashlytics crashlytics,
  }) : _messaging = messaging,
       _functions = functions,
       _auth = auth,
       _crashlytics = crashlytics {
    _startNotificationOpenHandling();
  }

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
    await registerCurrentToken(reportUnavailableToken: true);
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

  Future<void> setMessagePreviewEnabled(bool enabled) async {
    await _functions
        .httpsCallable('setMyNotesNotificationPreviewEnabled')
        .call<Map<String, dynamic>>({'enabled': enabled});
  }

  Future<void> registerCurrentToken({
    bool reportUnavailableToken = false,
  }) async {
    if (_auth.currentUser == null) {
      await _logRegistrationDiagnostic(
        'Registration skipped because no authenticated user is available.',
      );
      return;
    }
    final settings = await _messaging.getNotificationSettings();
    await _logRegistrationDiagnostic(
      'Notification authorization status: '
      '${settings.authorizationStatus.name}.',
    );
    if (!_isGranted(settings.authorizationStatus)) {
      await _logRegistrationDiagnostic(
        'Registration skipped because notification permission is not granted.',
      );
      return;
    }

    final tokenResult = await _currentFcmToken();
    final token = tokenResult.token;
    if (token == null || token.isEmpty) {
      if (reportUnavailableToken) {
        await _reportTokenUnavailable(tokenResult.unavailableStage);
      }
      return;
    }
    await _logRegistrationDiagnostic(
      'FCM token acquired; starting server registration.',
    );
    await _registerToken(token);
    await _logRegistrationDiagnostic('FCM token registration completed.');
  }

  Future<void> deleteCurrentToken() async {
    if (_auth.currentUser == null) return;
    final token = (await _currentFcmToken()).token;
    if (token == null || token.isEmpty) return;
    await _functions.httpsCallable('deleteFcmToken').call<Map<String, dynamic>>(
      {'token': token},
    );
  }

  void startRegistrationSync() {
    _authStateSubscription ??= _auth.authStateChanges().listen((user) {
      if (user == null) return;
      unawaited(_registerCurrentTokenInBackground('authentication change'));
    });
    _tokenRefreshSubscription ??= _messaging.onTokenRefresh.listen((token) {
      unawaited(_registerRefreshedToken(token));
    });
  }

  Future<NotificationPlaceRoute?> initialPlaceRouteFromLaunch() async {
    final message = await _messaging.getInitialMessage();
    final route = placeRouteFromMessage(message);
    if (route != null) return route;
    return _initialPlaceRouteFromNativeLaunch();
  }

  Stream<NotificationPlaceRoute> get openedPlaceRoutes {
    return _openedPlaceRoutes.stream;
  }

  Future<void> dispose() async {
    await _authStateSubscription?.cancel();
    await _tokenRefreshSubscription?.cancel();
    await _messageOpenSubscription?.cancel();
    _nativeLaunchChannel.setMethodCallHandler(null);
    await _openedPlaceRoutes.close();
  }

  Future<void> _registerCurrentTokenInBackground(String reason) async {
    try {
      await registerCurrentToken();
    } catch (error, stack) {
      await _reportRegistrationError(reason, error, stack);
    }
  }

  Future<void> _registerRefreshedToken(String token) async {
    if (_auth.currentUser == null) return;
    try {
      final settings = await _messaging.getNotificationSettings();
      if (!_isGranted(settings.authorizationStatus)) return;
      await _registerToken(token);
    } catch (error, stack) {
      await _reportRegistrationError('FCM token refresh', error, stack);
    }
  }

  Future<void> _reportRegistrationError(
    String reason,
    Object error,
    StackTrace stack,
  ) async {
    debugPrint('FCM token registration failed after $reason: $error\n$stack');
    try {
      await _crashlytics.setCustomKey('fcm_registration_trigger', reason);
      await _crashlytics.setCustomKey('fcm_registration_platform', _platform);
      await _crashlytics.recordError(
        error,
        stack,
        reason: 'FCM token registration failed: $reason',
        fatal: false,
      );
    } catch (crashlyticsError, crashlyticsStack) {
      debugPrint(
        'Could not report FCM registration failure to Crashlytics: '
        '$crashlyticsError\n$crashlyticsStack',
      );
    }
  }

  Future<void> _registerToken(String token) async {
    await _functions
        .httpsCallable('registerFcmToken')
        .call<Map<String, dynamic>>({'token': token, 'platform': _platform});
  }

  Future<({String? token, String? unavailableStage})> _currentFcmToken() async {
    if (_requiresApnsToken) {
      await _logRegistrationDiagnostic('Requesting the current APNs token.');
      final apnsToken = await _messaging.getAPNSToken();
      if (apnsToken == null || apnsToken.isEmpty) {
        await _logRegistrationDiagnostic('APNs token is not available yet.');
        return (token: null, unavailableStage: 'apns_token');
      }
      await _logRegistrationDiagnostic('APNs token acquired.');
    }
    await _logRegistrationDiagnostic('Requesting the current FCM token.');
    final token = await _messaging.getToken();
    await _logRegistrationDiagnostic(
      token == null || token.isEmpty
          ? 'FCM token is not available yet.'
          : 'FCM token acquired.',
    );
    return (
      token: token,
      unavailableStage: token == null || token.isEmpty ? 'fcm_token' : null,
    );
  }

  Future<void> _logRegistrationDiagnostic(String message) async {
    final logMessage = '[MyNotesNotification] $message';
    debugPrint(logMessage);
    try {
      await _crashlytics.log(logMessage);
    } catch (error, stack) {
      debugPrint(
        '[MyNotesNotification] Could not write Crashlytics breadcrumb: '
        '$error\n$stack',
      );
    }
  }

  Future<void> _reportTokenUnavailable(String? stage) async {
    final unavailableStage = stage ?? 'unknown';
    final message =
        'FCM registration stopped because $unavailableStage was unavailable.';
    await _logRegistrationDiagnostic(message);
    try {
      await _crashlytics.setCustomKey('fcm_registration_platform', _platform);
      await _crashlytics.setCustomKey(
        'fcm_registration_failure',
        unavailableStage,
      );
      await _crashlytics.recordError(
        StateError(message),
        StackTrace.current,
        reason: message,
        fatal: false,
      );
    } catch (error, stack) {
      debugPrint(
        '[MyNotesNotification] Could not report unavailable token: '
        '$error\n$stack',
      );
    }
  }

  Future<NotificationPlaceRoute?> _initialPlaceRouteFromNativeLaunch() async {
    if (defaultTargetPlatform != TargetPlatform.iOS) return null;
    try {
      final payload = await _nativeLaunchChannel.invokeMethod<dynamic>(
        'takeInitialPlaceId',
      );
      return placeRouteFromNativeLaunch(payload);
    } on MissingPluginException {
      return null;
    }
  }

  void _startNotificationOpenHandling() {
    _messageOpenSubscription ??= FirebaseMessaging.onMessageOpenedApp
        .map(placeRouteFromMessage)
        .where((route) => route != null)
        .cast<NotificationPlaceRoute>()
        .listen(_openedPlaceRoutes.add);

    if (defaultTargetPlatform != TargetPlatform.iOS) return;
    _nativeLaunchChannel.setMethodCallHandler((call) async {
      if (call.method != 'notificationLaunchPlaceId') return null;
      final route = placeRouteFromNativeLaunch(call.arguments);
      if (route != null) {
        debugPrint(
          'Opened notification launch placeId from iOS: '
          '${route.placeId} (readOnly=${route.readOnly})',
        );
        _openedPlaceRoutes.add(route);
      }
      return null;
    });
  }

  static NotificationPlaceRoute? placeRouteFromMessage(RemoteMessage? message) {
    return placeRouteFromMessageData(message?.data);
  }

  static NotificationPlaceRoute? placeRouteFromMessageData(
    Map<String, dynamic>? data,
  ) {
    final type = data?['type'];
    final placeId = data?['placeId'];
    if (placeId is! String || placeId.isEmpty) return null;

    return switch (type) {
      'my_note_message' => NotificationPlaceRoute(
        placeId: placeId,
        readOnly: true,
      ),
      'nearby_note_message' => NotificationPlaceRoute(placeId: placeId),
      _ => null,
    };
  }

  static NotificationPlaceRoute? placeRouteFromNativeLaunch(dynamic payload) {
    if (payload is String && payload.isNotEmpty) {
      return NotificationPlaceRoute(placeId: payload, readOnly: true);
    }
    if (payload is! Map) return null;

    final placeId = payload['placeId'];
    if (placeId is! String || placeId.isEmpty) return null;
    return NotificationPlaceRoute(
      placeId: placeId,
      readOnly: payload['readOnly'] == true,
    );
  }

  static String? placeIdFromMessage(RemoteMessage? message) {
    return placeRouteFromMessage(message)?.placeId;
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
