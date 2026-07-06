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
      return borderRadius == BorderRadius.zero
          ? child
          : ClipRRect(borderRadius: borderRadius, child: child);
    }
    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
        child: child,
      ),
    );
  }
}
