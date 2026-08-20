import 'dart:async';
import 'dart:io';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import '../config/app_config.dart';

typedef ServerEntitlementSynchronizer = Future<void> Function();

class SubscriptionService {
  SubscriptionService({
    ServerEntitlementSynchronizer? serverEntitlementSynchronizer,
  }) : _serverEntitlementSynchronizer = serverEntitlementSynchronizer;

  final ServerEntitlementSynchronizer? _serverEntitlementSynchronizer;
  Future<void>? _synchronizingEntitlement;

  /// Whether the RevenueCat SDK has been successfully configured.
  /// All SDK calls must be gated on this flag — calling any Purchases method
  /// before configure() triggers a Swift fatalError that Dart cannot catch.
  static bool _configured = false;

  static bool get isConfigured => _configured;

  static Future<void> initialize() async {
    final apiKey = Platform.isIOS
        ? AppConfig.revenueCatApiKeyIos
        : AppConfig.revenueCatApiKeyAndroid;

    if (apiKey.isEmpty) return;

    await Purchases.configure(PurchasesConfiguration(apiKey));
    _configured = true;
  }

  Future<bool> isPremium() async {
    if (!_configured) return false;
    try {
      final info = await Purchases.getCustomerInfo();
      return info.entitlements.active.containsKey(AppConfig.proEntitlementId);
    } catch (error, stack) {
      await _reportRevenueCatError('checking premium status', error, stack);
      return false;
    }
  }

  /// Emits the current premium status immediately, then re-emits on every
  /// RevenueCat [CustomerInfo] update (e.g. after purchase or restore).
  ///
  /// Uses [Purchases.addCustomerInfoUpdateListener] / [removeCustomerInfoUpdateListener]
  /// since the RevenueCat Flutter SDK v10 exposes a callback API rather than a stream.
  Stream<bool> get isPremiumStream {
    late StreamController<bool> controller;

    void listener(CustomerInfo info) {
      if (!controller.isClosed) {
        controller.add(
          info.entitlements.active.containsKey(AppConfig.proEntitlementId),
        );
      }
      unawaited(syncEntitlement());
    }

    controller = StreamController<bool>(
      onListen: () async {
        // Emit the current status right away.
        controller.add(await isPremium());
        // Register for future updates from the RevenueCat SDK.
        if (_configured) {
          Purchases.addCustomerInfoUpdateListener(listener);
          unawaited(syncEntitlement());
        }
      },
      onCancel: () async {
        if (_configured) {
          Purchases.removeCustomerInfoUpdateListener(listener);
        }
        await controller.close();
      },
    );

    return controller.stream;
  }

  Future<List<Package>> getOfferings() async {
    if (!_configured) return [];
    try {
      final offerings = await Purchases.getOfferings();
      return offerings.current?.availablePackages ?? [];
    } catch (error, stack) {
      await _reportRevenueCatError('loading offerings', error, stack);
      return [];
    }
  }

  Future<bool> purchase(Package package) async {
    if (!_configured) return false;
    try {
      final result = await Purchases.purchase(PurchaseParams.package(package));
      final active = result.customerInfo.entitlements.active.containsKey(
        AppConfig.proEntitlementId,
      );
      await syncEntitlement();
      return active;
    } catch (error, stack) {
      await _reportRevenueCatError('purchasing package', error, stack);
      return false;
    }
  }

  Future<bool> restorePurchases() async {
    if (!_configured) return false;
    try {
      final info = await Purchases.restorePurchases();
      final active = info.entitlements.active.containsKey(
        AppConfig.proEntitlementId,
      );
      await syncEntitlement();
      return active;
    } catch (error, stack) {
      await _reportRevenueCatError('restoring purchases', error, stack);
      return false;
    }
  }

  Future<void> identifyUser(String userId) async {
    if (!_configured) return;
    try {
      await Purchases.logIn(userId);
      await syncEntitlement();
    } catch (error, stack) {
      await _reportRevenueCatError('identifying user', error, stack);
    }
  }

  Future<void> logOut() async {
    if (!_configured) return;
    try {
      await Purchases.logOut();
    } catch (error, stack) {
      await _reportRevenueCatError('logging out', error, stack);
    }
  }

  /// Asks the server to verify CustomerInfo and refresh every regional mirror.
  Future<void> syncEntitlement() {
    final synchronizer = _serverEntitlementSynchronizer;
    if (!_configured || synchronizer == null) {
      return Future.value();
    }
    return _synchronizingEntitlement ??= _runEntitlementSync(
      synchronizer,
    ).whenComplete(() => _synchronizingEntitlement = null);
  }

  Future<void> _runEntitlementSync(
    ServerEntitlementSynchronizer synchronizer,
  ) async {
    try {
      await synchronizer();
    } catch (error, stack) {
      await _reportRevenueCatError(
        'synchronizing server entitlement',
        error,
        stack,
      );
    }
  }

  static Future<void> _reportRevenueCatError(
    String operation,
    Object error,
    StackTrace stack,
  ) async {
    final message = _describeRevenueCatError(operation, error);
    debugPrint(message);
    try {
      await FirebaseCrashlytics.instance.log(message);
      await FirebaseCrashlytics.instance.recordError(error, stack);
    } catch (_) {}
  }

  static String _describeRevenueCatError(String operation, Object error) {
    if (error is PlatformException) {
      final code = PurchasesErrorHelper.getErrorCode(error);
      return '[RevenueCat] Error while $operation: '
          'code=${error.code} ($code), '
          'message=${error.message}, '
          'details=${error.details}';
    }
    return '[RevenueCat] Error while $operation: $error';
  }
}
