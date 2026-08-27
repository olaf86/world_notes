import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/entities/admin_account_safety_entity.dart';
import '../../../l10n/l10n.dart';
import '../../../l10n/localized_formatters.dart';
import '../../providers/providers.dart';
import '../../widgets/app_alert_dialog.dart';

class AdminAccountSafetyScreen extends ConsumerStatefulWidget {
  const AdminAccountSafetyScreen({super.key});

  @override
  ConsumerState<AdminAccountSafetyScreen> createState() =>
      _AdminAccountSafetyScreenState();
}

class _AdminAccountSafetyScreenState
    extends ConsumerState<AdminAccountSafetyScreen> {
  final _uidController = TextEditingController();
  AdminAccountSafetyEntity? _safety;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _uidController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final uid = _uidController.text.trim();
    if (uid.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final safety = await ref
          .read(adminModerationServiceProvider)
          .getAccountSafety(targetUid: uid);
      if (mounted) setState(() => _safety = safety);
    } catch (error) {
      if (mounted) setState(() => _error = _errorMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _apply(AdminAccountSafetyAction action, String title) async {
    final safety = _safety;
    if (safety == null || _busy) return;
    final input = await _requestReason(title);
    if (!mounted || input == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(adminModerationServiceProvider)
          .updateAccountSafety(
            targetUid: safety.targetUid,
            action: action,
            reason: input.reason,
            reference: input.reference,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.l10n.adminSafetyAccepted)));
      setState(() => _busy = false);
      await _load();
    } catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = _errorMessage(error);
        });
      }
    }
  }

  Future<_AdminReason?> _requestReason(String title) async {
    final reason = TextEditingController();
    final reference = TextEditingController();
    final result = await showDialog<_AdminReason>(
      context: context,
      builder: (context) => AppAlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: reason,
              autofocus: true,
              maxLength: 500,
              minLines: 2,
              maxLines: 4,
              decoration: InputDecoration(
                labelText: context.l10n.adminSafetyReason,
              ),
            ),
            TextField(
              controller: reference,
              maxLength: 256,
              decoration: InputDecoration(
                labelText: context.l10n.adminSafetyReference,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () {
              final value = reason.text.trim();
              if (value.isEmpty) return;
              Navigator.pop(
                context,
                _AdminReason(value, reference.text.trim()),
              );
            },
            child: Text(context.l10n.adminSafetyApply),
          ),
        ],
      ),
    );
    reason.dispose();
    reference.dispose();
    return result;
  }

  Future<void> _adjustPoints() async {
    final controller = TextEditingController();
    final delta = await showDialog<int>(
      context: context,
      builder: (context) => AppAlertDialog(
        title: Text(context.l10n.adminSafetyAdjustPoints),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(signed: true),
          decoration: InputDecoration(
            labelText: context.l10n.adminSafetyPointDelta,
            helperText: context.l10n.adminSafetyPointDeltaHelp,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () {
              final value = int.tryParse(controller.text.trim());
              if (value == null || value == 0 || value < -100 || value > 100) {
                return;
              }
              Navigator.pop(context, value);
            },
            child: Text(context.l10n.adminSafetyContinue),
          ),
        ],
      ),
    );
    controller.dispose();
    if (!mounted || delta == null) return;
    await _apply(
      AdminAccountSafetyAction.adjustPoints(delta),
      context.l10n.adminSafetyAdjustPoints,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.adminAccountSafety)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _uidController,
            enabled: !_busy,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _load(),
            decoration: InputDecoration(
              labelText: context.l10n.adminSafetyTargetUid,
              suffixIcon: IconButton(
                tooltip: context.l10n.adminSafetyLoad,
                onPressed: _busy ? null : _load,
                icon: const Icon(Icons.search),
              ),
            ),
          ),
          if (_busy) ...[
            const SizedBox(height: 16),
            const LinearProgressIndicator(),
          ],
          if (_error != null) ...[
            const SizedBox(height: 16),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          if (_safety case final safety?) ...[
            const SizedBox(height: 16),
            _SafetySummary(safety: safety),
            const SizedBox(height: 16),
            _SafetyActions(
              enabled: !_busy,
              onAdjustPoints: _adjustPoints,
              onApply: _apply,
            ),
            const SizedBox(height: 24),
            Text(
              context.l10n.adminSafetyAuditHistory,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            if (safety.audits.isEmpty)
              Text(context.l10n.adminSafetyNoAudits)
            else
              for (final audit in safety.audits)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(audit.action['type']?.toString() ?? '-'),
                  subtitle: Text(audit.reason),
                  trailing: Text(
                    formatNoteDateTime(
                      audit.createdAt,
                      locale: context.localeTag,
                    ),
                    textAlign: TextAlign.end,
                  ),
                ),
          ],
        ],
      ),
    );
  }
}

class _SafetySummary extends StatelessWidget {
  const _SafetySummary({required this.safety});

  final AdminAccountSafetyEntity safety;

  @override
  Widget build(BuildContext context) {
    String date(DateTime? value, String none) => value == null
        ? none
        : formatNoteDateTime(value, locale: context.localeTag);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${context.l10n.adminSafetyPoints}: '
              '${safety.violationPoints}/100',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              '${context.l10n.adminSafetyAuthorityWorld}: '
              '${safety.authorityWorld}',
            ),
            Text(
              '${context.l10n.adminSafetyRestriction}: '
              '${date(safety.restrictedUntil, context.l10n.adminSafetyNone)}',
            ),
            Text(
              '${context.l10n.adminSafetyBan}: '
              '${safety.isPermanentlyBanned ? context.l10n.adminSafetyPermanent : date(safety.bannedUntil, context.l10n.adminSafetyNone)}',
            ),
          ],
        ),
      ),
    );
  }
}

class _SafetyActions extends StatelessWidget {
  const _SafetyActions({
    required this.enabled,
    required this.onAdjustPoints,
    required this.onApply,
  });

  final bool enabled;
  final Future<void> Function() onAdjustPoints;
  final Future<void> Function(AdminAccountSafetyAction, String) onApply;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        OutlinedButton(
          onPressed: enabled ? onAdjustPoints : null,
          child: Text(context.l10n.adminSafetyAdjustPoints),
        ),
        for (final days in const [1, 3, 7])
          OutlinedButton(
            onPressed: enabled
                ? () => onApply(
                    AdminAccountSafetyAction.setRestriction(days),
                    context.l10n.adminSafetySetRestriction(days),
                  )
                : null,
            child: Text(context.l10n.adminSafetySetRestriction(days)),
          ),
        OutlinedButton(
          onPressed: enabled
              ? () => onApply(
                  const AdminAccountSafetyAction.clearRestriction(),
                  context.l10n.adminSafetyClearRestriction,
                )
              : null,
          child: Text(context.l10n.adminSafetyClearRestriction),
        ),
        for (final days in const [7, 30])
          FilledButton.tonal(
            onPressed: enabled
                ? () => onApply(
                    AdminAccountSafetyAction.setBan(days),
                    context.l10n.adminSafetySetBan(days),
                  )
                : null,
            child: Text(context.l10n.adminSafetySetBan(days)),
          ),
        FilledButton.tonal(
          onPressed: enabled
              ? () => onApply(
                  const AdminAccountSafetyAction.setPermanentBan(),
                  context.l10n.adminSafetySetPermanentBan,
                )
              : null,
          child: Text(context.l10n.adminSafetySetPermanentBan),
        ),
        OutlinedButton(
          onPressed: enabled
              ? () => onApply(
                  const AdminAccountSafetyAction.clearBan(),
                  context.l10n.adminSafetyClearBan,
                )
              : null,
          child: Text(context.l10n.adminSafetyClearBan),
        ),
      ],
    );
  }
}

final class _AdminReason {
  const _AdminReason(this.reason, this.reference);

  final String reason;
  final String reference;
}

String _errorMessage(Object error) {
  if (error is FirebaseFunctionsException) return error.message ?? error.code;
  return error.toString();
}
