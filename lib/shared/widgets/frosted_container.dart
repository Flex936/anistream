import 'dart:ui';
import 'package:flutter/material.dart';

/// Wraps [child] in a [BackdropFilter] blur unless [uiPerformanceMode] is
/// true, in which case the blur is skipped entirely (Android TV / low-power
/// devices). Central home for the glassmorphism blur so it isn't
/// hand-rolled per widget.
///
/// [build] returns a structurally different ancestor chain above [child]
/// depending on [uiPerformanceMode] and [borderRadius] (bare child, vs.
/// `ClipRRect`, vs. `ClipRRect > BackdropFilter`). Flutter's normal
/// reconciliation only reuses an `Element` when it finds the same widget
/// type in the same slot under the same parent, so toggling
/// [uiPerformanceMode] while this widget stays mounted would otherwise
/// unmount and remount [child]'s entire subtree, resetting any `Scrollable`,
/// `TextEditingController`, or `AnimationController` state it holds.
///
/// If a caller can toggle [uiPerformanceMode] live while this instance
/// stays mounted, and [child] holds state worth preserving across that
/// toggle, pass a stable [preservationKey] (a `GlobalKey` owned by the
/// caller's own `State`). Wrapping [child] in a `KeyedSubtree` with that
/// key lets Flutter relocate the existing `Element` to its new ancestor
/// chain instead of remounting it. Most consumers only read
/// [uiPerformanceMode] once at mount and don't need this.
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
      // Clip.hardEdge instead of ClipRRect's default Clip.antiAlias:
      // hard-edge clipping is a cheap rect/rrect stencil with no sampled
      // edge smoothing, which is the whole point on hardware too weak to
      // afford the blur in the first place. Anti-aliased clipping is a
      // layer-based, sampled operation — one of the complex clipping
      // paths Performant mode exists to avoid.
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
