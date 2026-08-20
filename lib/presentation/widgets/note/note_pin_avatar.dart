import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/providers.dart';

class NotePinAvatar extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String? storagePath;
  final double radius;
  final Widget? badge;

  const NotePinAvatar({
    super.key,
    required this.color,
    required this.icon,
    this.storagePath,
    this.radius = 22,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    final path = storagePath?.trim();
    final hasStorageImage = path != null && path.isNotEmpty;
    final avatar = hasStorageImage
        ? _StoragePinAvatar(
            color: color,
            icon: icon,
            storagePath: path,
            radius: radius,
          )
        : _FallbackAvatar(color: color, icon: icon, radius: radius);

    return _BadgedPinAvatar(
      radius: radius,
      badge: _badgeFor(hasStorageImage: hasStorageImage),
      child: avatar,
    );
  }

  Widget? _badgeFor({required bool hasStorageImage}) {
    if (badge != null) return badge;
    if (!hasStorageImage) return null;
    return _PlaceIconBadge(color: color, icon: icon);
  }
}

class _StoragePinAvatar extends ConsumerWidget {
  final Color color;
  final IconData icon;
  final String storagePath;
  final double radius;

  const _StoragePinAvatar({
    required this.color,
    required this.icon,
    required this.storagePath,
    required this.radius,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final size = radius * 2;
    final imageUrl = ref.watch(messageImageUrlProvider(storagePath));
    return ClipOval(
      child: SizedBox.square(
        dimension: size,
        child: imageUrl.when(
          loading: () =>
              _FallbackAvatar(color: color, icon: icon, radius: radius),
          error: (_, _) =>
              _FallbackAvatar(color: color, icon: icon, radius: radius),
          data: (url) {
            final imageService = ref.watch(messageImageServiceProvider);
            return CachedNetworkImage(
              imageUrl: url,
              cacheKey: imageService.cacheKey(storagePath),
              cacheManager: imageService.cacheManager,
              fit: BoxFit.cover,
              placeholder: (_, _) =>
                  _FallbackAvatar(color: color, icon: icon, radius: radius),
              errorWidget: (_, _, _) =>
                  _FallbackAvatar(color: color, icon: icon, radius: radius),
            );
          },
        ),
      ),
    );
  }
}

class _BadgedPinAvatar extends StatelessWidget {
  final double radius;
  final Widget child;
  final Widget? badge;

  const _BadgedPinAvatar({
    required this.radius,
    required this.child,
    required this.badge,
  });

  @override
  Widget build(BuildContext context) {
    final size = radius * 2;
    final badgeSize = size * 0.42;
    final badgeOutset = badgeSize * 0.22;

    if (badge == null) {
      return SizedBox.square(dimension: size, child: child);
    }

    return SizedBox(
      width: size + badgeOutset,
      height: size + badgeOutset,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          PositionedDirectional(
            top: 0,
            start: 0,
            child: SizedBox.square(dimension: size, child: child),
          ),
          PositionedDirectional(
            end: 0,
            bottom: 0,
            child: SizedBox.square(dimension: badgeSize, child: badge),
          ),
        ],
      ),
    );
  }
}

class _PlaceIconBadge extends StatelessWidget {
  final Color color;
  final IconData icon;

  const _PlaceIconBadge({required this.color, required this.icon});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest.shortestSide;
        return Container(
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(
              color: Theme.of(context).colorScheme.surface,
              width: 1.5,
            ),
          ),
          child: Icon(icon, color: Colors.white, size: size * 0.58),
        );
      },
    );
  }
}

class _FallbackAvatar extends StatelessWidget {
  final Color color;
  final IconData icon;
  final double radius;

  const _FallbackAvatar({
    required this.color,
    required this.icon,
    required this.radius,
  });

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: radius,
      backgroundColor: color,
      child: Icon(icon, color: Colors.white, size: radius),
    );
  }
}
