import 'package:flutter/material.dart';
import 'package:purchases_ui_flutter/purchases_ui_flutter.dart';

import '../../../config/app_config.dart';
import '../../../services/subscription_service.dart';

/// Displays the RevenueCat Paywall so users can subscribe to World Notes PRO.
///
/// Falls back to a simple message when the RevenueCat SDK is not configured
/// (e.g. no API key in debug builds).
class SubscriptionScreen extends StatelessWidget {
  const SubscriptionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    if (!SubscriptionService.isConfigured) {
      return Scaffold(
        appBar: AppBar(title: const Text(AppConfig.proPlanName)),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              '${AppConfig.proPlanName} is not available in this build.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    return Scaffold(
      body: PaywallView(
        customVariables: {
          'plan_name': const CustomVariableValue.string(AppConfig.proPlanName),
          'monthly_price': CustomVariableValue.string(
            AppConfig.proMonthlyPriceLabel,
          ),
          'yearly_price': CustomVariableValue.string(
            AppConfig.proYearlyPriceLabel,
          ),
          'yearly_launch_price': CustomVariableValue.string(
            AppConfig.proYearlyLaunchPriceLabel,
          ),
          'free_note_limit': CustomVariableValue.number(
            AppConfig.freeNoteLimit.toDouble(),
          ),
          'pro_note_limit': CustomVariableValue.number(
            AppConfig.proNoteLimit.toDouble(),
          ),
        },
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
