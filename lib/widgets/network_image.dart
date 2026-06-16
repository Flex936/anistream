import 'package:flutter/material.dart';
import '../theme/app_palette.dart';

/// Small network image with a dark skeleton placeholder and fade-in on load.
class AppNetworkImage extends StatelessWidget {
  final String? url;

  const AppNetworkImage({super.key, this.url});

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

    return Image.network(
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
    );
  }
}
