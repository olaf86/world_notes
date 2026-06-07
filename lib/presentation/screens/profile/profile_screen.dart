import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:purchases_ui_flutter/purchases_ui_flutter.dart';

import '../../../config/app_config.dart';
import '../../../services/subscription_service.dart';
import '../../providers/providers.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  Future<void> _editNickname(
    BuildContext context,
    WidgetRef ref,
    String currentName,
  ) async {
    final controller = TextEditingController(text: currentName);
    var saving = false;

    final nextName = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Edit nickname'),
          content: TextField(
            controller: controller,
            autofocus: true,
            enabled: !saving,
            maxLength: 20,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(labelText: 'Nickname'),
            onSubmitted: (_) async {
              final value = controller.text.trim();
              if (value.isEmpty) return;
              setDialogState(() => saving = true);
              Navigator.pop(ctx, value);
            },
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: saving
                  ? null
                  : () {
                      final value = controller.text.trim();
                      if (value.isEmpty) return;
                      setDialogState(() => saving = true);
                      Navigator.pop(ctx, value);
                    },
              child: saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();

    if (nextName == null || nextName == currentName) return;

    try {
      await ref.read(authRepositoryProvider).updateDisplayName(nextName);
      ref.invalidate(authStateProvider);
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Nickname updated.')));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to update nickname: $e')));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userAsync = ref.watch(authStateProvider);
    final isPremiumAsync = ref.watch(isPremiumProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      body: userAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (user) {
          if (user == null) return const SizedBox();

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Center(
                child: Column(
                  children: [
                    CircleAvatar(
                      radius: 48,
                      backgroundImage: user.photoUrl != null
                          ? CachedNetworkImageProvider(user.photoUrl!)
                          : null,
                      child: user.photoUrl == null
                          ? Text(
                              user.name.isNotEmpty
                                  ? user.name[0].toUpperCase()
                                  : '?',
                              style: const TextStyle(fontSize: 32),
                            )
                          : null,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      user.name,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () => _editNickname(context, ref, user.name),
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      label: const Text('Edit nickname'),
                    ),
                    if (user.email != null)
                      Text(
                        user.email!,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    const SizedBox(height: 8),
                    isPremiumAsync.when(
                      loading: () => const SizedBox(),
                      error: (e, st) => const SizedBox(),
                      data: (isPremium) => isPremium
                          ? Column(
                              children: [
                                Chip(
                                  label: const Text('PRO'),
                                  avatar: const Icon(Icons.star, size: 16),
                                  backgroundColor: Theme.of(
                                    context,
                                  ).colorScheme.primaryContainer,
                                ),
                                if (SubscriptionService.isConfigured)
                                  TextButton(
                                    onPressed: () =>
                                        RevenueCatUI.presentCustomerCenter(),
                                    child: const Text('Manage Subscription'),
                                  ),
                              ],
                            )
                          : OutlinedButton.icon(
                              onPressed: () => context.push('/subscription'),
                              icon: const Icon(Icons.star_outline),
                              label: const Text('Upgrade to PRO'),
                            ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.star_outline),
                title: const Text(AppConfig.proPlanName),
                subtitle: const Text(
                  'Remove ads, keep 200 notes, and unlock PRO features',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/subscription'),
              ),
              if (SubscriptionService.isConfigured) ...[
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.manage_accounts_outlined),
                  title: const Text('Manage Subscription'),
                  subtitle: const Text('Billing, cancellation & support'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => RevenueCatUI.presentCustomerCenter(),
                ),
              ],
              const Divider(),
              ListTile(
                leading: Icon(
                  Icons.logout,
                  color: Theme.of(context).colorScheme.error,
                ),
                title: Text(
                  'Sign Out',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                onTap: () async {
                  await ref.read(authRepositoryProvider).signOut();
                  await ref.read(subscriptionServiceProvider).logOut();
                },
              ),
            ],
          );
        },
      ),
    );
  }
}
