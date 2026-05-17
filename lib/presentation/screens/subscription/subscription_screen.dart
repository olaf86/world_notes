import 'package:flutter/material.dart';
import 'package:purchases_ui_flutter/purchases_ui_flutter.dart';

import '../../../services/subscription_service.dart';

/// Displays the RevenueCat Paywall so users can subscribe to World Notes Premium.
///
/// Falls back to a simple message when the RevenueCat SDK is not configured
/// (e.g. no API key in debug builds).
class SubscriptionScreen extends StatelessWidget {
  const SubscriptionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    if (!SubscriptionService.isConfigured) {
      return Scaffold(
        appBar: AppBar(title: const Text('Premium')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Subscription service is not available in this build.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    return Scaffold(
      body: PaywallView(
        onPurchaseCompleted: (customerInfo, storeTransaction) {
          if (context.mounted) Navigator.of(context).pop();
        },
        onRestoreCompleted: (customerInfo) {
          if (context.mounted) Navigator.of(context).pop();
        },
        onDismiss: () {
          if (context.mounted) Navigator.of(context).pop();
        },
      ),
    );
  }
}
