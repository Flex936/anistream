import 'dart:ui';
import 'package:flutter/material.dart';

/// Wraps [child] in a [BackdropFilter] blur unless [uiPerformanceMode] is
/// true, in which case the blur is skipped entirely (Android TV / low-power
/// devices). Consolidates the ~11 hand-rolled
/// `if (!uiPerformanceMode) { ... BackdropFilter ... }` blocks that used to
/// be scattered across the widget tree.
class FrostedContainer extends StatelessWidget {
  final Widget child;
  final bool uiPerformanceMode;
  final double sigma;
  final BorderRadius borderRadius;

  const FrostedContainer({
    super.key,
    required this.child,
    required this.uiPerformanceMode,
    this.sigma = 20,
    this.borderRadius = BorderRadius.zero,
  });

  @override
  Widget build(BuildContext context) {
    if (uiPerformanceMode) {
      // ── Clip.hardEdge instead of ClipRRect's default Clip.antiAlias:
      // hard-edge clipping is a cheap rect/rrect stencil with no sampled
      // edge smoothing, which is the whole point on hardware too weak to
      // afford the blur in the first place. Anti-aliased clipping is a
      // layer-based, sampled operation — one of the "complex clipping
      // paths" Performant mode exists to avoid. ──
      return borderRadius == BorderRadius.zero
          ? child
          : ClipRRect(
              borderRadius: borderRadius,
              clipBehavior: Clip.hardEdge,
              child: child,
            );
    }
    return ClipRRect(
      borderRadius: borderRadius,
      clipBehavior: Clip.antiAlias,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
        child: child,
      ),
    );
  }
}
