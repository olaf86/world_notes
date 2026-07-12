import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

class UserAvatarBadge extends StatelessWidget {
  static const defaultName = 'Creator';

  final String? name;
  final String? photoUrl;

  const UserAvatarBadge({super.key, this.name, this.photoUrl});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final effectiveName = name ?? defaultName;
    final url = photoUrl?.trim();

    return LayoutBuilder(
      builder: (context, constraints) {
        return DecoratedBox(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            shape: BoxShape.circle,
            border: Border.all(color: theme.colorScheme.surface, width: 1.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.18),
                blurRadius: 4,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: ClipOval(
            child: url == null || url.isEmpty
                ? _InitialAvatar(name: effectiveName)
                : Image(
                    image: CachedNetworkImageProvider(url),
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) =>
                        _InitialAvatar(name: effectiveName),
                  ),
          ),
        );
      },
    );
  }
}

class _InitialAvatar extends StatelessWidget {
  final String name;

  const _InitialAvatar({required this.name});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final initial = _initialFor(name);
    return ColoredBox(
      color: theme.colorScheme.primaryContainer,
      child: Center(
        child: initial == null
            ? Icon(
                Icons.person,
                size: 12,
                color: theme.colorScheme.onPrimaryContainer,
              )
            : Text(
                initial,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onPrimaryContainer,
                  fontWeight: FontWeight.w700,
                  height: 1,
                ),
              ),
      ),
    );
  }
}

String? _initialFor(String name) {
  final trimmed = name.trim();
  if (trimmed.isEmpty) return null;
  return String.fromCharCode(trimmed.runes.first).toUpperCase();
}
