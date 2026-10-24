import 'dart:ui';
import 'package:flutter/material.dart';

/// Wraps [child] in a [BackdropFilter] blur, skipped entirely under
/// [uiPerformanceMode]. Pass a stable [preservationKey] if the mode can toggle
/// live while [child] holds state (DESIGN.md § 1.4).
class FrostedContainer extends StatelessWidget {
  final Widget child;
  final bool uiPerformanceMode;
  final double sigma;
  final BorderRadius borderRadius;
  final Key? preservationKey;

  const FrostedContainer({
    super.key,
    required this.child,
    required this.uiPerformanceMode,
    this.sigma = 20,
    this.borderRadius = BorderRadius.zero,
    this.preservationKey,
  });

  @override
  Widget build(BuildContext context) {
    final content = preservationKey == null
        ? child
        : KeyedSubtree(key: preservationKey, child: child);

    if (uiPerformanceMode) {
      // Hard-edge clip instead of anti-aliased: cheaper on weak hardware
      // (DESIGN.md § 2).
      return borderRadius == BorderRadius.zero
          ? content
          : ClipRRect(
              borderRadius: borderRadius,
              clipBehavior: Clip.hardEdge,
              child: content,
            );
    }
    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
        child: content,
      ),
    );
  }
}