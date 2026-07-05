import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/providers.dart';

class ReportMessageScreen extends ConsumerStatefulWidget {
  final String placeId;
  final String messageId;

  const ReportMessageScreen({
    super.key,
    required this.placeId,
    required this.messageId,
  });

  @override
  ConsumerState<ReportMessageScreen> createState() =>
      _ReportMessageScreenState();
}

class _ReportMessageScreenState extends ConsumerState<ReportMessageScreen> {
  static const _reasons = [
    'Spam or advertising',
    'Harassment or bullying',
    'Adult or explicit content',
    'Illegal content',
    'Other',
  ];

  String? _selectedReason;
  bool _submitting = false;

  Future<void> _submit() async {
    final reason = _selectedReason;
    if (reason == null || _submitting) return;

    final currentUser = ref.read(authStateProvider).valueOrNull;
    if (currentUser == null) return;

    setState(() => _submitting = true);
    try {
      await ref
          .read(messageRepositoryProvider)
          .reportMessage(
            messageId: widget.messageId,
            placeId: widget.placeId,
            reporterId: currentUser.id,
            reason: reason,
          );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to submit report: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Report message')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Text(
            'Why are you reporting this message?',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          for (final reason in _reasons) ...[
            ListTile(
              contentPadding: EdgeInsets.zero,
              enabled: !_submitting,
              title: Text(reason),
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
                'Your user ID, this message ID, the note ID, and the selected '
                'reason will be shared with administrators for review.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
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
            label: Text(_submitting ? 'Submitting...' : 'Submit report'),
          ),
        ],
      ),
    );
  }
}
