import 'dart:async';
import 'dart:io';
import 'package:purchases_flutter/purchases_flutter.dart';
import '../config/app_config.dart';

class SubscriptionService {
  static Future<void> initialize() async {
    final apiKey = Platform.isIOS
        ? AppConfig.revenueCatApiKeyIos
        : AppConfig.revenueCatApiKeyAndroid;

    if (apiKey.isEmpty) return;

    await Purchases.configure(PurchasesConfiguration(apiKey));
  }

  Future<bool> isPremium() async {
    try {
      final info = await Purchases.getCustomerInfo();
      return info.entitlements.active.containsKey(AppConfig.premiumEntitlementId);
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
          info.entitlements.active.containsKey(AppConfig.premiumEntitlementId),
        );
      }
    }

    controller = StreamController<bool>(
      onListen: () async {
        // Emit the current status right away.
        controller.add(await isPremium());
        // Register for future updates from the RevenueCat SDK.
        try {
          Purchases.addCustomerInfoUpdateListener(listener);
        } catch (_) {
          // RevenueCat not configured (e.g. API key empty in debug) — ignore.
        }
      },
      onCancel: () async {
        try {
          Purchases.removeCustomerInfoUpdateListener(listener);
        } catch (_) {}
        await controller.close();
      },
    );

    return controller.stream;
  }

  Future<List<Package>> getOfferings() async {
    try {
      final offerings = await Purchases.getOfferings();
      return offerings.current?.availablePackages ?? [];
    } catch (_) {
      return [];
    }
  }

  Future<bool> purchase(Package package) async {
    try {
      final result = await Purchases.purchase(
        PurchaseParams.package(package),
      );
      return result.customerInfo.entitlements.active
          .containsKey(AppConfig.premiumEntitlementId);
    } catch (_) {
      return false;
    }
  }

  Future<bool> restorePurchases() async {
    try {
      final info = await Purchases.restorePurchases();
      return info.entitlements.active.containsKey(AppConfig.premiumEntitlementId);
    } catch (_) {
      return false;
    }
  }

  Future<void> identifyUser(String userId) async {
    try {
      await Purchases.logIn(userId);
    } catch (_) {}
  }

  Future<void> logOut() async {
    try {
      await Purchases.logOut();
    } catch (_) {}
  }
}
