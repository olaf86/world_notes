import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import '../../providers/providers.dart';

class SubscriptionScreen extends ConsumerStatefulWidget {
  const SubscriptionScreen({super.key});

  @override
  ConsumerState<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends ConsumerState<SubscriptionScreen> {
  List<Package> _packages = [];
  bool _loading = true;
  bool _purchasing = false;

  @override
  void initState() {
    super.initState();
    _loadOfferings();
  }

  Future<void> _loadOfferings() async {
    final packages =
        await ref.read(subscriptionServiceProvider).getOfferings();
    if (mounted) {
      setState(() {
        _packages = packages;
        _loading = false;
      });
    }
  }

  Future<void> _purchase(Package package) async {
    setState(() => _purchasing = true);
    final success =
        await ref.read(subscriptionServiceProvider).purchase(package);
    if (mounted) {
      setState(() => _purchasing = false);
      if (success) {
        ref.invalidate(isPremiumProvider);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Welcome to Premium!')),
        );
        Navigator.of(context).pop();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Purchase failed. Try again.')),
        );
      }
    }
  }

  Future<void> _restore() async {
    setState(() => _purchasing = true);
    final success =
        await ref.read(subscriptionServiceProvider).restorePurchases();
    if (mounted) {
      setState(() => _purchasing = false);
      if (success) {
        ref.invalidate(isPremiumProvider);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Purchases restored!')),
        );
        Navigator.of(context).pop();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No purchases to restore.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Premium')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Icon(
                  Icons.star_rounded,
                  size: 72,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(height: 16),
                Text(
                  'World Notes Premium',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                _FeatureRow(
                  icon: Icons.block,
                  title: 'Ad-free experience',
                  subtitle: 'Browse the map without interruptions',
                ),
                _FeatureRow(
                  icon: Icons.map_outlined,
                  title: 'Extended search radius',
                  subtitle: 'Find notes up to 20km away',
                ),
                _FeatureRow(
                  icon: Icons.color_lens_outlined,
                  title: 'Premium themes & icons',
                  subtitle: 'Customize your notes with exclusive styles',
                ),
                _FeatureRow(
                  icon: Icons.cloud_upload_outlined,
                  title: 'Photo attachments',
                  subtitle: 'Attach photos to your messages',
                ),
                const SizedBox(height: 32),
                if (_packages.isEmpty)
                  Center(
                    child: Text(
                      'No plans available',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  )
                else
                  ..._packages.map((package) => _PackageCard(
                        package: package,
                        onPurchase: _purchasing ? null : () => _purchase(package),
                      )),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: _purchasing ? null : _restore,
                  child: const Text('Restore Purchases'),
                ),
                const SizedBox(height: 8),
                Text(
                  'Subscriptions auto-renew. Cancel anytime in App Store / Google Play settings.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _FeatureRow({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              icon,
              color: Theme.of(context).colorScheme.onPrimaryContainer,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PackageCard extends StatelessWidget {
  final Package package;
  final VoidCallback? onPurchase;

  const _PackageCard({required this.package, required this.onPurchase});

  @override
  Widget build(BuildContext context) {
    final product = package.storeProduct;
    final isAnnual = package.packageType == PackageType.annual;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        product.title,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      if (isAnnual)
                        Container(
                          margin: const EdgeInsets.only(top: 4),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.tertiaryContainer,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            'Best Value',
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onTertiaryContainer,
                                ),
                          ),
                        ),
                    ],
                  ),
                ),
                Text(
                  product.priceString,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: onPurchase,
              child: Text('Subscribe${isAnnual ? ' Yearly' : ' Monthly'}'),
            ),
          ],
        ),
      ),
    );
  }
}
