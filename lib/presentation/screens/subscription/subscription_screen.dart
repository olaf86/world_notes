import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:purchases_ui_flutter/purchases_ui_flutter.dart';

import '../../../config/app_config.dart';
import '../../../services/subscription_service.dart';

/// Displays the RevenueCat Paywall so users can subscribe to World Notes PRO.
///
/// Falls back to a simple message when the RevenueCat SDK is not configured
/// (e.g. no API key in debug builds).
class SubscriptionScreen extends StatefulWidget {
  const SubscriptionScreen({super.key});

  @override
  State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen> {
  late Future<Offering> _offeringFuture;

  @override
  void initState() {
    super.initState();
    _offeringFuture = _loadCurrentOffering();
  }

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

    return FutureBuilder<Offering>(
      future: _offeringFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return Scaffold(
            appBar: AppBar(title: const Text(AppConfig.proPlanName)),
            body: const Center(child: CircularProgressIndicator()),
          );
        }

        final offering = snapshot.data;
        if (snapshot.hasError || offering == null) {
          return _SubscriptionSetupErrorView(
            message: _displayError(snapshot.error),
            onRetry: () {
              setState(() {
                _offeringFuture = _loadCurrentOffering();
              });
            },
          );
        }

        return _RevenueCatPaywall(offering: offering);
      },
    );
  }

  Future<Offering> _loadCurrentOffering() async {
    try {
      final offerings = await Purchases.getOfferings();
      final current = offerings.current;
      if (current == null) {
        final knownOfferings = offerings.all.keys.join(', ');
        throw StateError(
          'RevenueCat current offering is not configured. '
          'Available offerings: ${knownOfferings.isEmpty ? 'none' : knownOfferings}.',
        );
      }

      final returnedProductIds = current.availablePackages
          .map((package) => package.storeProduct.identifier)
          .toSet();
      if (returnedProductIds.isEmpty) {
        throw StateError(
          'RevenueCat offering "${current.identifier}" has no available '
          'packages. Check that App Store Connect products are Ready to '
          'Submit and attached to this RevenueCat offering.',
        );
      }

      final missingProductIds = _expectedProductIds
          .where((productId) => !returnedProductIds.contains(productId))
          .toList();
      if (missingProductIds.isNotEmpty) {
        throw StateError(
          'RevenueCat offering "${current.identifier}" is missing expected '
          'products: ${missingProductIds.join(', ')}. '
          'Returned products: ${returnedProductIds.join(', ')}.',
        );
      }

      return current;
    } catch (error, stack) {
      await _reportSubscriptionSetupError(
        'loading current offering',
        error,
        stack,
      );
      rethrow;
    }
  }
}

class _RevenueCatPaywall extends StatelessWidget {
  const _RevenueCatPaywall({required this.offering});

  final Offering offering;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PaywallView(
        offering: offering,
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
        onPurchaseError: (error) =>
            _handlePaywallError(context, 'purchase', error),
        onRestoreCompleted: (customerInfo) {
          if (context.mounted) Navigator.of(context).pop();
        },
        onRestoreError: (error) =>
            _handlePaywallError(context, 'restore', error),
        onDismiss: () {
          if (context.mounted) Navigator.of(context).pop();
        },
      ),
    );
  }
}

class _SubscriptionSetupErrorView extends StatelessWidget {
  const _SubscriptionSetupErrorView({
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text(AppConfig.proPlanName)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(
                  Icons.error_outline,
                  size: 40,
                  color: Theme.of(context).colorScheme.error,
                ),
                const SizedBox(height: 16),
                Text(
                  '${AppConfig.proPlanName} is temporarily unavailable.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                SelectableText(message, textAlign: TextAlign.center),
                const SizedBox(height: 24),
                FilledButton(onPressed: onRetry, child: const Text('Retry')),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

const _expectedProductIds = <String>{
  AppConfig.proMonthlyProductId,
  AppConfig.proYearlyProductId,
};

Future<void> _handlePaywallError(
  BuildContext context,
  String action,
  PurchasesError error,
) async {
  await _reportPaywallError(action, error);
  if (!context.mounted) return;
  ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(_paywallErrorMessage(action, error))));
}

Future<void> _reportPaywallError(String action, PurchasesError error) async {
  final message = _paywallErrorMessage(action, error);
  debugPrint(message);
  try {
    final crashlytics = FirebaseCrashlytics.instance;
    await crashlytics.log(message);
    await crashlytics.setCustomKey('revenuecat_paywall_error', message);
    await crashlytics.recordError(StateError(message), StackTrace.current);
    await crashlytics.sendUnsentReports();
  } catch (_) {}
}

Future<void> _reportSubscriptionSetupError(
  String action,
  Object error,
  StackTrace stack,
) async {
  final message = '[RevenueCat Setup] $action failed: ${_displayError(error)}';
  debugPrint(message);
  try {
    final crashlytics = FirebaseCrashlytics.instance;
    await crashlytics.log(message);
    await crashlytics.setCustomKey('revenuecat_setup_error', message);
    await crashlytics.recordError(error, stack);
    await crashlytics.sendUnsentReports();
  } catch (_) {}
}

String _paywallErrorMessage(String action, PurchasesError error) {
  return '[RevenueCat Paywall] $action failed: '
      'code=${error.code}, '
      'readableCode=${error.readableErrorCode}, '
      'message=${error.message}, '
      'underlying=${error.underlyingErrorMessage}';
}

String _displayError(Object? error) {
  if (error == null) return 'Unknown subscription setup error.';
  if (error is StateError) return error.message;
  if (error is PlatformException) {
    final code = PurchasesErrorHelper.getErrorCode(error);
    return 'RevenueCat error ${error.code} ($code): '
        '${error.message ?? 'No message.'} '
        '${error.details ?? ''}';
  }
  return error.toString();
}
