import 'package:flutter/material.dart';

import '../../../data/anilist/models/anime.dart';
import 'hero_banner.dart';
import 'hero_header_compact.dart';

/// Pinned, shrink-driven hero header for [AnimeDetailsScreen] — the
/// collapsing-header sibling to the plain scrolling [HeroBanner] it used to
/// wrap directly. Cross-fades between the full [HeroBanner] (poster + title
/// + status chips) and [HeroHeaderCompact] (back button + single-line
/// title) as the user scrolls, driven by the standard
/// shrinkOffset/maxExtent/minExtent contract every
/// SliverPersistentHeaderDelegate exposes.
///
/// Deliberately renders both layers as a Stack + Opacity/IgnorePointer pair
/// rather than one widget hand-interpolating dozens of inline style
/// properties — HeroBanner and HeroHeaderCompact stay ordinary,
/// independently testable widgets driven by AppTypography/AppPalette/
/// AppRadii tokens, same as every other widget in this codebase.
class HeroHeaderDelegate extends SliverPersistentHeaderDelegate {
  final Anime anime;
  final VoidCallback? onBack;
  final bool uiPerformanceMode;
  final double maxExtentValue;
  final double minExtentValue;

  const HeroHeaderDelegate({
    required this.anime,
    this.onBack,
    this.uiPerformanceMode = false,
    this.maxExtentValue = 280,
    this.minExtentValue = 72,
  });

  @override
  double get maxExtent => maxExtentValue;

  @override
  double get minExtent => minExtentValue;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final double range = maxExtentValue - minExtentValue;
    final double t = range <= 0 ? 1.0 : (shrinkOffset / range).clamp(0.0, 1.0);

    // ── Performance mode: hard-swap at the midpoint instead of cross-fading
    // every scrolled pixel. Continuous per-frame Opacity interpolation on a
    // pinned header is exactly the compositor cost DESIGN.md § 2's
    // animation-duration rule exists to strip on weak/TV hardware — this is
    // that rule's equivalent for a scroll-driven effect, since perfDuration
    // itself only covers fixed-duration Animated* transitions. ──
    if (uiPerformanceMode) {
      final bool showCompact = t >= 0.5;
      return ClipRect(
        child: showCompact
            ? HeroHeaderCompact(
                anime: anime,
                onBack: onBack,
                uiPerformanceMode: uiPerformanceMode,
              )
            : HeroBanner(
                anime: anime,
                onBack: onBack,
                uiPerformanceMode: uiPerformanceMode,
              ),
      );
    }

    return ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: [
          IgnorePointer(
            ignoring: t >= 1.0,
            child: Opacity(
              opacity: 1.0 - t,
              child: HeroBanner(
                anime: anime,
                onBack: onBack,
                uiPerformanceMode: uiPerformanceMode,
              ),
            ),
          ),
          IgnorePointer(
            ignoring: t <= 0.0,
            child: Opacity(
              opacity: t,
              child: HeroHeaderCompact(
                anime: anime,
                onBack: onBack,
                uiPerformanceMode: uiPerformanceMode,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  bool shouldRebuild(covariant HeroHeaderDelegate oldDelegate) {
    return anime.id != oldDelegate.anime.id ||
        uiPerformanceMode != oldDelegate.uiPerformanceMode ||
        onBack != oldDelegate.onBack ||
        maxExtentValue != oldDelegate.maxExtentValue ||
        minExtentValue != oldDelegate.minExtentValue;
  }
}
