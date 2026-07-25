import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/entities/admin_moderation_review_entity.dart';
import '../../../l10n/l10n.dart';
import '../../../l10n/localized_formatters.dart';
import '../../providers/providers.dart';

class AdminModerationScreen extends ConsumerStatefulWidget {
  const AdminModerationScreen({super.key});

  @override
  ConsumerState<AdminModerationScreen> createState() =>
      _AdminModerationScreenState();
}

class _AdminModerationScreenState extends ConsumerState<AdminModerationScreen> {
  AdminModerationReviewStatus _status = AdminModerationReviewStatus.open;
  bool _submitting = false;

  @override
  Widget build(BuildContext context) {
    final isAdmin = ref.watch(adminClaimProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Moderation'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(adminModerationReviewsProvider),
          ),
        ],
      ),
      body: isAdmin.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _ErrorView(
          message: _callableErrorMessage(error),
          onRetry: () => ref.invalidate(adminClaimProvider),
        ),
        data: (allowed) {
          if (!allowed) {
            return const Center(child: Text('Admin access required.'));
          }
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<AdminModerationReviewStatus>(
                    segments: const [
                      ButtonSegment(
                        value: AdminModerationReviewStatus.open,
                        icon: Icon(Icons.pending_actions_outlined),
                        label: Text('Open'),
                      ),
                      ButtonSegment(
                        value: AdminModerationReviewStatus.resolved,
                        icon: Icon(Icons.check_circle_outline),
                        label: Text('Resolved'),
                      ),
                    ],
                    selected: {_status},
                    onSelectionChanged: (next) {
                      setState(() => _status = next.single);
                    },
                  ),
                ),
              ),
              Expanded(
                child: _ReviewList(status: _status, onAction: _review),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _review(
    AdminModerationReviewEntity review,
    AdminModerationAction action,
  ) async {
    if (_submitting || !review.canReview) return;
    final reason = await _reasonFor(action);
    if (!mounted || reason == null) return;
    setState(() => _submitting = true);
    try {
      await ref
          .read(adminModerationServiceProvider)
          .reviewContent(
            targetType: review.targetType,
            placeId: review.placeId!,
            messageId: review.messageId,
            action: action,
            reason: reason,
          );
      ref.invalidate(adminModerationReviewsProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Marked as ${_actionLabel(action)}.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_callableErrorMessage(error))));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<String?> _reasonFor(AdminModerationAction action) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_actionTitle(action)),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 500,
          minLines: 2,
          maxLines: 4,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(labelText: 'Reason'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Apply'),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }
}

class _ReviewList extends ConsumerWidget {
  final AdminModerationReviewStatus status;
  final Future<void> Function(
    AdminModerationReviewEntity review,
    AdminModerationAction action,
  )
  onAction;

  const _ReviewList({required this.status, required this.onAction});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reviews = ref.watch(adminModerationReviewsProvider(status));

    return reviews.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => _ErrorView(
        message: _callableErrorMessage(error),
        onRetry: () => ref.invalidate(adminModerationReviewsProvider(status)),
      ),
      data: (items) {
        if (items.isEmpty) {
          return Center(child: Text(context.l10n.noModerationReviews));
        }
        return RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(adminModerationReviewsProvider(status));
            await ref.read(adminModerationReviewsProvider(status).future);
          },
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              return _ReviewCard(
                review: items[index],
                showActions: status == AdminModerationReviewStatus.open,
                onAction: onAction,
              );
            },
          ),
        );
      },
    );
  }
}

class _ReviewCard extends StatelessWidget {
  final AdminModerationReviewEntity review;
  final bool showActions;
  final Future<void> Function(
    AdminModerationReviewEntity review,
    AdminModerationAction action,
  )
  onAction;

  const _ReviewCard({
    required this.review,
    required this.showActions,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final content = review.content.trim().isEmpty ? '(empty)' : review.content;

    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final source in review.reviewSources)
                  Chip(
                    label: Text(source),
                    visualDensity: VisualDensity.compact,
                  ),
                if (review.action != null)
                  Chip(
                    label: Text(review.action!),
                    visualDensity: VisualDensity.compact,
                  ),
                Chip(
                  label: Text(review.targetType.name),
                  visualDensity: VisualDensity.compact,
                ),
                if (review.maxScore != null)
                  Chip(
                    label: Text(review.maxScore!.toStringAsFixed(2)),
                    visualDensity: VisualDensity.compact,
                  ),
                if (review.hasImages)
                  const Chip(
                    avatar: Icon(Icons.image_outlined, size: 16),
                    label: Text('image'),
                    visualDensity: VisualDensity.compact,
                  ),
                if (review.reportCount != null && review.reportCount! > 0)
                  Chip(
                    avatar: const Icon(Icons.flag_outlined, size: 16),
                    label: Text('${review.reportCount} report(s)'),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
            const SizedBox(height: 10),
            SelectableText(content, style: theme.textTheme.bodyLarge),
            const SizedBox(height: 10),
            if (review.categories.isNotEmpty)
              _MetaLine(
                icon: Icons.category_outlined,
                text: review.categories.join(', '),
              ),
            if (review.riskSignals.isNotEmpty)
              _MetaLine(
                icon: Icons.warning_amber_outlined,
                text: review.riskSignals
                    .map((signal) => '${signal.category}:${signal.severity}')
                    .join(', '),
              ),
            if (review.reportReasonsSummary.isNotEmpty)
              _MetaLine(
                icon: Icons.flag_outlined,
                text: review.reportReasonsSummary.join(', '),
              ),
            _MetaLine(
              icon: Icons.place_outlined,
              text: [
                if (review.placeId != null) review.placeId!,
                if (review.messageId != null) review.messageId!,
              ].join(' / '),
            ),
            if (review.createdAt != null)
              _MetaLine(
                icon: Icons.schedule_outlined,
                text: formatNoteDateTime(
                  review.createdAt!,
                  locale: context.localeTag,
                ),
              ),
            if (!showActions && review.humanDecision != null)
              _MetaLine(
                icon: Icons.fact_check_outlined,
                text: [
                  review.humanDecision!,
                  if (review.decisionReason != null) review.decisionReason!,
                ].join(' / '),
              ),
            if (showActions) ...[
              const SizedBox(height: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  OutlinedButton.icon(
                    onPressed: review.canReview
                        ? () => onAction(review, AdminModerationAction.allow)
                        : null,
                    icon: const Icon(Icons.check_outlined),
                    label: const Text('Allow'),
                  ),
                  const SizedBox(height: 8),
                  if (review.targetType ==
                      AdminModerationTargetType.message) ...[
                    OutlinedButton.icon(
                      onPressed: review.canReview
                          ? () => onAction(
                              review,
                              AdminModerationAction.sensitive,
                            )
                          : null,
                      icon: const Icon(Icons.visibility_off_outlined),
                      label: const Text('Sensitive'),
                    ),
                    const SizedBox(height: 8),
                  ],
                  FilledButton.icon(
                    onPressed: review.canReview
                        ? () => onAction(review, AdminModerationAction.hidden)
                        : null,
                    icon: const Icon(Icons.block_outlined),
                    label: const Text('Hide'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MetaLine extends StatelessWidget {
  final IconData icon;
  final String text;

  const _MetaLine({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    if (text.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Expanded(
            child: SelectableText(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

String _actionLabel(AdminModerationAction action) {
  return switch (action) {
    AdminModerationAction.allow => 'allowed',
    AdminModerationAction.sensitive => 'sensitive',
    AdminModerationAction.hidden => 'hidden',
  };
}

String _actionTitle(AdminModerationAction action) {
  return switch (action) {
    AdminModerationAction.allow => 'Allow message',
    AdminModerationAction.sensitive => 'Mark sensitive',
    AdminModerationAction.hidden => 'Hide message',
  };
}

String _callableErrorMessage(Object error) {
  if (error is FirebaseFunctionsException) {
    return error.message ?? error.code;
  }
  return error.toString();
}
