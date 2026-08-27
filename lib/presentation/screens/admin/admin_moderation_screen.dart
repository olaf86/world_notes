import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/entities/admin_moderation_review_entity.dart';
import '../../../l10n/l10n.dart';
import '../../../l10n/localized_formatters.dart';
import '../../providers/providers.dart';
import '../../widgets/app_alert_dialog.dart';
import 'admin_account_safety_screen.dart';

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
        title: Text(context.l10n.moderation),
        actions: [
          IconButton(
            tooltip: context.l10n.adminAccountSafety,
            icon: const Icon(Icons.admin_panel_settings_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const AdminAccountSafetyScreen(),
              ),
            ),
          ),
          IconButton(
            tooltip: context.l10n.commonRefresh,
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
            return Center(child: Text(context.l10n.adminAccessRequired));
          }
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<AdminModerationReviewStatus>(
                    segments: [
                      ButtonSegment(
                        value: AdminModerationReviewStatus.open,
                        icon: const Icon(Icons.pending_actions_outlined),
                        label: Text(context.l10n.moderationOpen),
                      ),
                      ButtonSegment(
                        value: AdminModerationReviewStatus.resolved,
                        icon: const Icon(Icons.check_circle_outline),
                        label: Text(context.l10n.moderationResolved),
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
    if (_submitting) return;
    final reason = await _reasonFor(action);
    if (!mounted || reason == null) return;
    setState(() => _submitting = true);
    try {
      await ref
          .read(adminModerationServiceProvider)
          .reviewContent(
            targetType: review.targetType,
            placeId: review.placeId,
            targetId: review.targetId,
            action: action,
            reason: reason,
          );
      ref.invalidate(adminModerationReviewsProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.l10n.moderationMarkedAs(
              _actionStatusLabel(action, context.l10n),
            ),
          ),
        ),
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
      builder: (context) => AppAlertDialog(
        title: Text(_actionTitle(action, context.l10n)),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 500,
          minLines: 2,
          maxLines: 4,
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(labelText: context.l10n.reasonLabel),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: Text(context.l10n.applyAction),
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
    final content = review.content.trim().isEmpty
        ? context.l10n.emptyContent
        : review.content;

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
                  Chip(
                    avatar: const Icon(Icons.image_outlined, size: 16),
                    label: Text(context.l10n.imageLabel),
                    visualDensity: VisualDensity.compact,
                  ),
                if (review.reportCount != null && review.reportCount! > 0)
                  Chip(
                    avatar: const Icon(Icons.flag_outlined, size: 16),
                    label: Text(context.l10n.reportCount(review.reportCount!)),
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
                review.placeId,
                if (review.targetId != review.placeId) review.targetId,
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
                    onPressed: () =>
                        onAction(review, AdminModerationAction.allow),
                    icon: const Icon(Icons.check_outlined),
                    label: Text(context.l10n.moderationAllowAction),
                  ),
                  const SizedBox(height: 8),
                  if (review.targetType ==
                      AdminModerationTargetType.message) ...[
                    OutlinedButton.icon(
                      onPressed: () =>
                          onAction(review, AdminModerationAction.sensitive),
                      icon: const Icon(Icons.visibility_off_outlined),
                      label: Text(context.l10n.moderationSensitiveAction),
                    ),
                    const SizedBox(height: 8),
                  ],
                  FilledButton.icon(
                    onPressed: () =>
                        onAction(review, AdminModerationAction.hidden),
                    icon: const Icon(Icons.block_outlined),
                    label: Text(context.l10n.moderationHideAction),
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
              label: Text(context.l10n.commonRetry),
            ),
          ],
        ),
      ),
    );
  }
}

String _actionStatusLabel(AdminModerationAction action, AppLocalizations l10n) {
  return switch (action) {
    AdminModerationAction.allow => l10n.moderationAllowedStatus,
    AdminModerationAction.sensitive => l10n.moderationSensitiveStatus,
    AdminModerationAction.hidden => l10n.moderationHiddenStatus,
  };
}

String _actionTitle(AdminModerationAction action, AppLocalizations l10n) {
  return switch (action) {
    AdminModerationAction.allow => l10n.moderationAllowTitle,
    AdminModerationAction.sensitive => l10n.moderationSensitiveTitle,
    AdminModerationAction.hidden => l10n.moderationHideTitle,
  };
}

String _callableErrorMessage(Object error) {
  if (error is FirebaseFunctionsException) {
    return error.message ?? error.code;
  }
  return error.toString();
}
