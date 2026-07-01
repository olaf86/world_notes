import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/material.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
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
        onPurchaseError: (error) => _reportPaywallError('purchase', error),
        onRestoreCompleted: (customerInfo) {
          if (context.mounted) Navigator.of(context).pop();
        },
        onRestoreError: (error) => _reportPaywallError('restore', error),
        onDismiss: () {
          if (context.mounted) Navigator.of(context).pop();
        },
      ),
    );
  }
}

Future<void> _reportPaywallError(String action, PurchasesError error) async {
  final message =
      '[RevenueCat Paywall] $action failed: '
      'code=${error.code}, '
      'readableCode=${error.readableErrorCode}, '
      'message=${error.message}, '
      'underlying=${error.underlyingErrorMessage}';
  debugPrint(message);
  try {
    await FirebaseCrashlytics.instance.log(message);
    await FirebaseCrashlytics.instance.recordError(StateError(message), null);
  } catch (_) {}
}
