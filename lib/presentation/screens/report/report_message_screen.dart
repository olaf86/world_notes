import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/entities/content_report.dart';
import '../../../l10n/l10n.dart';
import '../../providers/providers.dart';

class ReportedUserTarget {
  final String userId;
  final String displayName;

  const ReportedUserTarget({required this.userId, required this.displayName});
}

class ReportContentResult {
  final bool blocked;
  final bool blockFailed;

  const ReportContentResult({this.blocked = false, this.blockFailed = false});
}

class ReportContentScreen extends ConsumerStatefulWidget {
  final String placeId;
  final String? messageId;
  final ContentReportTarget target;
  final ReportedUserTarget? reportedUser;

  const ReportContentScreen({
    super.key,
    required this.placeId,
    required this.target,
    this.messageId,
    this.reportedUser,
  }) : assert(
         target == ContentReportTarget.note || messageId != null,
         'Message reports require messageId.',
       );

  @override
  ConsumerState<ReportContentScreen> createState() =>
      _ReportContentScreenState();
}

class _ReportContentScreenState extends ConsumerState<ReportContentScreen> {
  ReportReasonCode? _selectedReason;
  bool _submitting = false;
  bool _alsoBlock = false;

  Future<void> _submit() async {
    final reason = _selectedReason;
    if (reason == null || _submitting) return;

    setState(() => _submitting = true);
    try {
      if (widget.target == ContentReportTarget.message) {
        await ref
            .read(messageRepositoryProvider)
            .reportMessage(
              messageId: widget.messageId!,
              placeId: widget.placeId,
              reasonCode: reason,
            );
      } else {
        await ref
            .read(placeRepositoryProvider)
            .reportNote(placeId: widget.placeId, reasonCode: reason);
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _submitting = false);
      final l10n = context.l10n;
      final message = switch (error) {
        FirebaseFunctionsException(code: 'resource-exhausted') =>
          l10n.reportCooldown,
        FirebaseFunctionsException(code: 'not-found') => l10n.reportUnavailable,
        FirebaseFunctionsException(code: 'permission-denied') =>
          l10n.reportUnavailable,
        FirebaseFunctionsException(code: 'failed-precondition') =>
          l10n.reportUnavailable,
        _ => l10n.reportFailed(error),
      };
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
      return;
    }

    var blocked = false;
    var blockFailed = false;
    if (_alsoBlock && widget.reportedUser != null) {
      try {
        await ref
            .read(userBlockRepositoryProvider)
            .setBlocked(
              targetUserId: widget.reportedUser!.userId,
              blocked: true,
            );
        ref.invalidate(mapPinsProvider);
        blocked = true;
      } catch (_) {
        blockFailed = true;
      }
    }
    if (mounted) {
      Navigator.of(
        context,
      ).pop(ReportContentResult(blocked: blocked, blockFailed: blockFailed));
    }
  }

  String _reasonLabel(ReportReasonCode reason) {
    final l10n = context.l10n;
    return switch (reason) {
      ReportReasonCode.spam => l10n.reportReasonSpam,
      ReportReasonCode.harassment => l10n.reportReasonHarassment,
      ReportReasonCode.sexual => l10n.reportReasonSexual,
      ReportReasonCode.illegal => l10n.reportReasonIllegal,
      ReportReasonCode.other => l10n.reportReasonOther,
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final isMessage = widget.target == ContentReportTarget.message;
    final currentUserId = ref.watch(authStateProvider).valueOrNull?.id;
    final reportedUser = widget.reportedUser;
    final canAlsoBlock =
        reportedUser != null && reportedUser.userId != currentUserId;
    final alreadyBlocked = canAlsoBlock
        ? ref.watch(isUserBlockedProvider(reportedUser.userId)).valueOrNull
        : true;
    return Scaffold(
      appBar: AppBar(
        title: Text(isMessage ? l10n.reportMessageTitle : l10n.reportNoteTitle),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Text(
            isMessage ? l10n.reportMessageQuestion : l10n.reportNoteQuestion,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          for (final reason in ReportReasonCode.values) ...[
            ListTile(
              contentPadding: EdgeInsets.zero,
              enabled: !_submitting,
              title: Text(_reasonLabel(reason)),
              trailing: _selectedReason == reason
                  ? Icon(Icons.check, color: theme.colorScheme.primary)
                  : null,
              onTap: _submitting
                  ? null
                  : () => setState(() => _selectedReason = reason),
            ),
            const Divider(height: 1),
          ],
          const SizedBox(height: 12),
          DecoratedBox(
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                isMessage ? l10n.reportMessagePrivacy : l10n.reportNotePrivacy,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
          if (canAlsoBlock && alreadyBlocked == false) ...[
            const SizedBox(height: 12),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _alsoBlock,
              enabled: !_submitting,
              title: Text(l10n.reportAlsoBlockUser),
              subtitle: Text(l10n.reportAlsoBlockUserDescription),
              onChanged: _submitting
                  ? null
                  : (value) => setState(() => _alsoBlock = value ?? false),
            ),
          ],
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _selectedReason == null || _submitting ? null : _submit,
            icon: _submitting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.flag_outlined),
            label: Text(
              _submitting ? l10n.reportSubmitting : l10n.reportSubmitAction,
            ),
          ),
        ],
      ),
    );
  }
}
