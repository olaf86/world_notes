import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/providers.dart';

class MyNotesNotificationIconButton extends ConsumerStatefulWidget {
  const MyNotesNotificationIconButton({super.key});

  @override
  ConsumerState<MyNotesNotificationIconButton> createState() =>
      _MyNotesNotificationIconButtonState();
}

class _MyNotesNotificationIconButtonState
    extends ConsumerState<MyNotesNotificationIconButton> {
  bool _updating = false;

  Future<void> _toggle(bool enabled) async {
    if (_updating) return;
    setState(() => _updating = true);
    final nextValue = !enabled;
    try {
      final granted = await setMyNotesNotificationsEnabled(ref, nextValue);
      if (!granted && mounted) {
        showMyNotesNotificationPermissionSnackBar(context);
      }
    } catch (_) {
      if (mounted) {
        showMyNotesNotificationUpdateErrorSnackBar(context, nextValue);
      }
    } finally {
      if (mounted) setState(() => _updating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabledAsync = ref.watch(myNotesNotificationEnabledProvider);
    final enabled = enabledAsync.valueOrNull ?? false;
    final disabled = _updating || enabledAsync.isLoading;

    if (_updating) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16),
        child: Center(
          child: SizedBox.square(
            dimension: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    return IconButton(
      tooltip: enabled
          ? 'Turn off maintained-note notifications'
          : 'Turn on maintained-note notifications',
      icon: Icon(
        enabled
            ? Icons.notifications_active_outlined
            : Icons.notifications_off_outlined,
      ),
      onPressed: disabled ? null : () => _toggle(enabled),
    );
  }
}

class MyNotesNotificationSwitchTile extends ConsumerStatefulWidget {
  const MyNotesNotificationSwitchTile({super.key});

  @override
  ConsumerState<MyNotesNotificationSwitchTile> createState() =>
      _MyNotesNotificationSwitchTileState();
}

class _MyNotesNotificationSwitchTileState
    extends ConsumerState<MyNotesNotificationSwitchTile> {
  bool _updating = false;

  Future<void> _setEnabled(bool enabled) async {
    if (_updating) return;
    setState(() => _updating = true);
    try {
      final granted = await setMyNotesNotificationsEnabled(ref, enabled);
      if (!granted && mounted) {
        showMyNotesNotificationPermissionSnackBar(context);
      }
    } catch (_) {
      if (mounted) {
        showMyNotesNotificationUpdateErrorSnackBar(context, enabled);
      }
    } finally {
      if (mounted) setState(() => _updating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabledAsync = ref.watch(myNotesNotificationEnabledProvider);
    final enabled = enabledAsync.valueOrNull ?? false;

    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: const Text('Maintained notes'),
      subtitle: const Text(
        'Receive notifications when notes you maintain get new messages.',
      ),
      value: enabled,
      onChanged: _updating || enabledAsync.isLoading ? null : _setEnabled,
    );
  }
}

class MyNotesNotificationPreviewSwitchTile extends ConsumerStatefulWidget {
  const MyNotesNotificationPreviewSwitchTile({super.key});

  @override
  ConsumerState<MyNotesNotificationPreviewSwitchTile> createState() =>
      _MyNotesNotificationPreviewSwitchTileState();
}

class _MyNotesNotificationPreviewSwitchTileState
    extends ConsumerState<MyNotesNotificationPreviewSwitchTile> {
  bool _updating = false;

  Future<void> _setEnabled(bool enabled) async {
    if (_updating) return;
    setState(() => _updating = true);
    try {
      await ref
          .read(myNotesNotificationServiceProvider)
          .setMessagePreviewEnabled(enabled);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not update notification previews.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _updating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final notificationsEnabledAsync = ref.watch(
      myNotesNotificationEnabledProvider,
    );
    final previewEnabledAsync = ref.watch(
      myNotesNotificationPreviewEnabledProvider,
    );
    final notificationsEnabled = notificationsEnabledAsync.valueOrNull ?? false;
    final previewEnabled = previewEnabledAsync.valueOrNull ?? true;
    final disabled =
        !notificationsEnabled ||
        _updating ||
        notificationsEnabledAsync.isLoading ||
        previewEnabledAsync.isLoading;

    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: const Text('Message previews'),
      subtitle: const Text('Show message text in maintained-note alerts.'),
      value: previewEnabled,
      onChanged: disabled ? null : _setEnabled,
    );
  }
}

Future<bool> setMyNotesNotificationsEnabled(WidgetRef ref, bool enabled) async {
  final service = ref.read(myNotesNotificationServiceProvider);
  if (enabled) {
    return service.enableMyNotesNotifications();
  }
  await service.disableMyNotesNotifications();
  return true;
}

void showMyNotesNotificationPermissionSnackBar(BuildContext context) {
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
      content: Text(
        'Notifications are not allowed. Enable notifications in system '
        'settings to receive new message alerts.',
      ),
    ),
  );
}

void showMyNotesNotificationUpdateErrorSnackBar(
  BuildContext context,
  bool enabled,
) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        enabled
            ? 'Could not enable maintained-note notifications.'
            : 'Could not disable maintained-note notifications.',
      ),
    ),
  );
}
