import 'dart:async';

import 'package:flutter/material.dart';
import '../../core/theme/app_palette.dart';
import '../utils/perf_animations.dart';

class AppNetworkImage extends StatelessWidget {
  final String? url;
  final double scale;
  final int? cacheWidth; // Limits physical pixel decoding in RAM
  final bool uiPerformanceMode;

  const AppNetworkImage({
    super.key,
    this.url,
    this.scale = 1.0,
    this.cacheWidth,
    this.uiPerformanceMode = false,
  });

  @override
  Widget build(BuildContext context) {
    if (url == null || url!.isEmpty) {
      return const _SkeletonShimmer(
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
      duration: perfDuration(
        uiPerformanceMode,
        const Duration(milliseconds: 300),
      ),
      curve: Curves.easeOut,
      child: Image.network(
        url!,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        cacheWidth: cacheWidth,
        // Cheaper resampling under performance mode (DESIGN.md § 2).
        filterQuality: uiPerformanceMode
            ? FilterQuality.low
            : FilterQuality.medium,
        frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
          if (wasSynchronouslyLoaded) return child;

          // The keyed switcher disposes the skeleton and its
          // AnimationController once the cross-fade ends, so nothing keeps
          // ticking after load.
          return AnimatedSwitcher(
            duration: perfDuration(
              uiPerformanceMode,
              const Duration(milliseconds: 400),
            ),
            layoutBuilder: (currentChild, previousChildren) => Stack(
              fit: StackFit.expand,
              children: [...previousChildren, ?currentChild],
            ),
            child: frame != null
                ? KeyedSubtree(key: const ValueKey('loaded'), child: child)
                : const KeyedSubtree(
                    key: ValueKey('skeleton'),
                    child: _SkeletonShimmer(),
                  ),
          );
        },
        errorBuilder: (_, _, _) => const _SkeletonShimmer(
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

// Animated skeleton loader.
class _SkeletonShimmer extends StatefulWidget {
  final Widget? child;
  const _SkeletonShimmer({this.child});

  @override
  State<_SkeletonShimmer> createState() => _SkeletonShimmerState();
}

class _SkeletonShimmerState extends State<_SkeletonShimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    unawaited(_controller.repeat());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final x = -1.0 + (_controller.value * 3.0);
        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: FractionalOffset(x, 0),
              end: FractionalOffset(x + 1.0, 0),
              colors: [
                AppPalette.overlay,
                AppPalette.border.withValues(alpha: 0.5),
                AppPalette.overlay,
              ],
              stops: const [0.0, 0.5, 1.0],
            ),
          ),
          child: widget.child,
        );
      },
    );
  }
}