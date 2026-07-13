import 'package:flutter/material.dart';

import 'note_pin_avatar.dart';

class NoteListCard extends StatelessWidget {
  final Color avatarColor;
  final IconData avatarIcon;
  final String? avatarImageStoragePath;
  final String title;
  final String? subtitle;
  final Widget? titleAccessory;
  final List<NoteListMeta> metadata;
  final Widget? trailing;
  final VoidCallback? onTap;

  const NoteListCard({
    super.key,
    required this.avatarColor,
    required this.avatarIcon,
    this.avatarImageStoragePath,
    required this.title,
    this.subtitle,
    this.titleAccessory,
    this.metadata = const [],
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final trimmedSubtitle = subtitle?.trim();
    final hasSubtitle = trimmedSubtitle?.isNotEmpty == true;

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              NotePinAvatar(
                color: avatarColor,
                icon: avatarIcon,
                storagePath: avatarImageStoragePath,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: theme.textTheme.titleSmall,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (titleAccessory != null) ...[
                          const SizedBox(width: 8),
                          titleAccessory!,
                        ],
                        if (trailing != null) ...[
                          const SizedBox(width: 8),
                          trailing!,
                        ],
                      ],
                    ),
                    if (hasSubtitle)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          trimmedSubtitle!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    if (metadata.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          children: metadata
                              .map((item) => _NoteListMetaView(item: item))
                              .toList(),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class NoteListMeta {
  final IconData icon;
  final String label;
  final String? semanticLabel;
  final Color? color;

  const NoteListMeta({
    required this.icon,
    required this.label,
    this.semanticLabel,
    this.color,
  });
}

class _NoteListMetaView extends StatelessWidget {
  final NoteListMeta item;

  const _NoteListMetaView({required this.item});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = item.color ?? theme.colorScheme.onSurfaceVariant;

    return Semantics(
      container: true,
      label: item.semanticLabel ?? item.label,
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(item.icon, size: 13, color: color),
            const SizedBox(width: 3),
            Text(
              item.label,
              style: theme.textTheme.labelSmall?.copyWith(color: color),
            ),
          ],
        ),
      ),
    );
  }
}
