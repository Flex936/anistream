import 'package:flutter/material.dart';
import '../../core/theme/app_palette.dart';

class AppNetworkImage extends StatelessWidget {
  final String? url;
  final double scale;

  const AppNetworkImage({super.key, this.url, this.scale = 1.0});

  @override
  Widget build(BuildContext context) {
    if (url == null || url!.isEmpty) {
      return const ColoredBox(
        color: AppPalette.overlay,
        child: Center(
          child: Icon(
            Icons.movie_creation_outlined,
            color: AppPalette.textMuted,
            size: 48,
          ),
        ),
      );
    }
    return AnimatedScale(
      scale: scale,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
      child: Image.network(
        url!,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
          if (wasSynchronouslyLoaded) return child;
          return Stack(
            fit: StackFit.expand,
            children: [
              const ColoredBox(color: AppPalette.overlay),
              AnimatedOpacity(
                opacity: frame != null ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 400),
                curve: Curves.easeOut,
                child: child,
              ),
            ],
          );
        },
        errorBuilder: (_, _, _) => const ColoredBox(
          color: AppPalette.overlay,
          child: Center(
            child: Icon(
              Icons.broken_image_outlined,
              color: AppPalette.textMuted,
              size: 48,
            ),
          ),
        ),
      ),
    );
  }
}
