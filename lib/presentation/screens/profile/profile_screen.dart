import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:purchases_ui_flutter/purchases_ui_flutter.dart';

import '../../../l10n/l10n.dart';
import '../../../services/subscription_service.dart';
import '../../providers/providers.dart';
import '../../widgets/app_alert_dialog.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  Future<void> _editNickname(
    BuildContext context,
    WidgetRef ref,
    String currentName,
  ) async {
    final l10n = context.l10n;
    final controller = TextEditingController(text: currentName);
    var saving = false;

    final nextName = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AppAlertDialog(
          title: Text(l10n.editNickname),
          content: TextField(
            controller: controller,
            autofocus: true,
            enabled: !saving,
            maxLength: 20,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(labelText: l10n.nicknameLabel),
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
              child: Text(l10n.commonCancel),
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
                  : Text(l10n.commonSave),
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
      ).showSnackBar(SnackBar(content: Text(l10n.nicknameUpdated)));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.nicknameUpdateFailed(e))));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final userAsync = ref.watch(authStateProvider);
    final isPremiumAsync = ref.watch(isPremiumProvider);
    final adminClaim = ref.watch(adminClaimProvider);

    return Semantics(
      identifier: 'screen-profile',
      child: Scaffold(
        appBar: AppBar(
          title: Text(l10n.profileTitle),
          actions: [
            IconButton(
              icon: const Icon(Icons.settings_outlined),
              tooltip: l10n.settingsTitle,
              onPressed: () => context.push('/settings'),
            ),
          ],
        ),
        body: userAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text(l10n.commonError(e))),
          data: (user) {
            if (user == null) return const SizedBox();
            final publicProfileAsync = ref.watch(
              publicProfileProvider(user.id),
            );
            final publicProfile = publicProfileAsync.valueOrNull;

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
                        label: Text(l10n.editNickname),
                      ),
                      if (user.email != null)
                        Text(
                          user.email!,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                        ),
                      const SizedBox(height: 16),
                      _ProfileSocialCounts(
                        followerCount: publicProfile?.followerCount ?? 0,
                        followingCount: publicProfile?.followingCount ?? 0,
                        onFollowersTap: () =>
                            context.push('/users/${user.id}/followers'),
                        onFollowingTap: () =>
                            context.push('/users/${user.id}/following'),
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
                                      child: Text(l10n.manageSubscription),
                                    ),
                                ],
                              )
                            : Semantics(
                                identifier: 'action-upgrade-to-pro',
                                button: true,
                                child: OutlinedButton.icon(
                                  onPressed: () =>
                                      context.push('/subscription'),
                                  icon: const Icon(Icons.star_outline),
                                  label: Text(l10n.upgradeToPro),
                                ),
                              ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.star_outline),
                  title: Text(l10n.proPlanName),
                  subtitle: Text(l10n.proBenefitsSummary),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/subscription'),
                ),
                if (SubscriptionService.isConfigured) ...[
                  const Divider(),
                  ListTile(
                    leading: const Icon(Icons.manage_accounts_outlined),
                    title: Text(l10n.manageSubscription),
                    subtitle: Text(l10n.subscriptionManagementSummary),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => RevenueCatUI.presentCustomerCenter(),
                  ),
                ],
                adminClaim.maybeWhen(
                  data: (isAdmin) {
                    if (!isAdmin) return const SizedBox.shrink();
                    return Column(
                      children: [
                        const Divider(),
                        ListTile(
                          leading: const Icon(Icons.admin_panel_settings),
                          title: Text(l10n.moderation),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => context.push('/admin/moderation'),
                        ),
                      ],
                    );
                  },
                  orElse: () => const SizedBox.shrink(),
                ),
                const Divider(),
                ListTile(
                  leading: Icon(
                    Icons.logout,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  title: Text(
                    l10n.signOut,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                  onTap: () async {
                    try {
                      await ref
                          .read(myNotesNotificationServiceProvider)
                          .deleteCurrentToken();
                    } catch (error, stack) {
                      await _reportSignOutCleanupFailure(
                        ref,
                        operation: 'deleting the current FCM token',
                        error: error,
                        stack: stack,
                      );
                    }
                    try {
                      await ref.read(messageImageServiceProvider).clearCache();
                    } catch (error, stack) {
                      await _reportSignOutCleanupFailure(
                        ref,
                        operation: 'clearing the message image cache',
                        error: error,
                        stack: stack,
                      );
                    }
                    await ref.read(authRepositoryProvider).signOut();
                    await ref.read(subscriptionServiceProvider).logOut();
                  },
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

Future<void> _reportSignOutCleanupFailure(
  WidgetRef ref, {
  required String operation,
  required Object error,
  required StackTrace stack,
}) async {
  final message = '[SignOut] Failed while $operation: $error';
  debugPrint('$message\n$stack');
  try {
    final crashlytics = ref.read(firebaseCrashlyticsProvider);
    await crashlytics.log(message);
    await crashlytics.recordError(
      error,
      stack,
      reason: 'Best-effort sign-out cleanup failed: $operation',
      fatal: false,
    );
  } catch (reportingError, reportingStack) {
    debugPrint(
      '[SignOut] Could not report cleanup failure to Crashlytics: '
      '$reportingError\n$reportingStack',
    );
  }
}

class _ProfileSocialCounts extends StatelessWidget {
  final int followerCount;
  final int followingCount;
  final VoidCallback onFollowersTap;
  final VoidCallback onFollowingTap;

  const _ProfileSocialCounts({
    required this.followerCount,
    required this.followingCount,
    required this.onFollowersTap,
    required this.onFollowingTap,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _ProfileCountButton(
          label: l10n.followers,
          value: followerCount,
          onTap: onFollowersTap,
        ),
        const SizedBox(width: 24),
        _ProfileCountButton(
          label: l10n.following,
          value: followingCount,
          onTap: onFollowingTap,
        ),
      ],
    );
  }
}

class _ProfileCountButton extends StatelessWidget {
  final String label;
  final int value;
  final VoidCallback onTap;

  const _ProfileCountButton({
    required this.label,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Column(
          children: [
            Text(
              '$value',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
