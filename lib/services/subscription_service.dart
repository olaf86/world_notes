import 'dart:async';
import 'dart:io';
import 'package:purchases_flutter/purchases_flutter.dart';
import '../config/app_config.dart';

class SubscriptionService {
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
    } catch (_) {
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
    }

    controller = StreamController<bool>(
      onListen: () async {
        // Emit the current status right away.
        controller.add(await isPremium());
        // Register for future updates from the RevenueCat SDK.
        if (_configured) {
          Purchases.addCustomerInfoUpdateListener(listener);
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
    } catch (_) {
      return [];
    }
  }

  Future<bool> purchase(Package package) async {
    if (!_configured) return false;
    try {
      final result = await Purchases.purchase(PurchaseParams.package(package));
      return result.customerInfo.entitlements.active.containsKey(
        AppConfig.proEntitlementId,
      );
    } catch (_) {
      return false;
    }
  }

  Future<bool> restorePurchases() async {
    if (!_configured) return false;
    try {
      final info = await Purchases.restorePurchases();
      return info.entitlements.active.containsKey(AppConfig.proEntitlementId);
    } catch (_) {
      return false;
    }
  }

  Future<void> identifyUser(String userId) async {
    if (!_configured) return;
    try {
      await Purchases.logIn(userId);
    } catch (_) {}
  }

  Future<void> logOut() async {
    if (!_configured) return;
    try {
      await Purchases.logOut();
    } catch (_) {}
  }
}
