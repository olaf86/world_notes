import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/providers.dart';

class NotePinAvatar extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String? storagePath;
  final double radius;

  const NotePinAvatar({
    super.key,
    required this.color,
    required this.icon,
    this.storagePath,
    this.radius = 22,
  });

  @override
  Widget build(BuildContext context) {
    final path = storagePath?.trim();
    if (path == null || path.isEmpty) {
      return _FallbackAvatar(color: color, icon: icon, radius: radius);
    }

    return _StoragePinAvatar(
      color: color,
      icon: icon,
      storagePath: path,
      radius: radius,
    );
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
    return SizedBox.square(
      dimension: size,
      child: ClipOval(
        child: imageUrl.when(
          loading: () =>
              _FallbackAvatar(color: color, icon: icon, radius: radius),
          error: (_, _) =>
              _FallbackAvatar(color: color, icon: icon, radius: radius),
          data: (url) => Stack(
            fit: StackFit.expand,
            children: [
              CachedNetworkImage(
                imageUrl: url,
                cacheKey: storagePath,
                cacheManager: ref
                    .watch(messageImageServiceProvider)
                    .cacheManager,
                fit: BoxFit.cover,
                placeholder: (_, _) =>
                    _FallbackAvatar(color: color, icon: icon, radius: radius),
                errorWidget: (_, _, _) =>
                    _FallbackAvatar(color: color, icon: icon, radius: radius),
              ),
              Align(
                alignment: Alignment.bottomRight,
                child: Container(
                  width: size * 0.42,
                  height: size * 0.42,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Theme.of(context).colorScheme.surface,
                      width: 1.5,
                    ),
                  ),
                  child: Icon(icon, color: Colors.white, size: size * 0.24),
                ),
              ),
            ],
          ),
        ),
      ),
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
