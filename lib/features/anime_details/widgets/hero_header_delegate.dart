import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import '../../../core/theme/app_palette.dart';
import '../../../data/anilist/models/anime.dart';
import 'hero_banner.dart';
import 'hero_header_compact.dart';

const double kHeroHeaderNavBarClearance = 96;

/// Pinned, shrink-driven hero header for AnimeDetailsScreen.
///
/// Full-state layout is now a single vertical column — title, then the
/// status/episode chips directly below it — rather than the previous
/// side-by-side poster+chips row that shared its vertical band with the
/// title's own bottom-left position. That side-by-side layout was the
/// actual cause of the title/metadata overlap: title text and the chip
/// row occupied overlapping y-ranges regardless of scroll position, most
/// visible mid-transition. Stacking them removes the shared band
/// entirely — the title sits higher, the chips sit in their own row
/// below it, and the chips only ever fade in place rather than moving,
/// so there's no point in the scroll range where the two can cross.
///
/// The poster thumbnail is gone too (redundant — see
/// HeroBannerStatusChips's doc comment), which is what frees up the
/// horizontal room the enlarged title (20 -> 28px) now uses.
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
    this.minExtentValue = kHeroHeaderNavBarClearance + 48,
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
    final double fadeT = (t / 0.6).clamp(0.0, 1.0);
    final double width = MediaQuery.sizeOf(context).width;

    // Title geometry — full state sits ABOVE the chip row (see class
    // doc), not beside a poster. Single-line + ellipsis in both states,
    // same reasoning as before: a continuous Rect/fontSize lerp can't
    // reconcile different wrap behavior mid-transition.
    final Rect fullRect = Rect.fromLTWH(
      20,
      maxExtentValue - 84,
      width - 40,
      44,
    );
    final Rect compactRect = Rect.fromLTWH(80, 104, width - 104, 32);
    final Rect titleRect = uiPerformanceMode
        ? (t >= 0.5 ? compactRect : fullRect)
        : Rect.lerp(fullRect, compactRect, t)!;
    final double titleFontSize = uiPerformanceMode
        ? (t >= 0.5 ? 15.0 : 28.0)
        : lerpDouble(28.0, 15.0, t)!;

    return ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: [
          const ColoredBox(color: AppPalette.base),

          Opacity(
            opacity: uiPerformanceMode ? (t >= 0.5 ? 0.0 : 1.0) : 1.0 - t,
            child: HeroBanner(
              anime: anime,
              uiPerformanceMode: uiPerformanceMode,
            ),
          ),

          Positioned(
            top: kHeroHeaderNavBarClearance,
            left: 16,
            child: HeroHeaderBackButton(
              onBack: onBack,
              uiPerformanceMode: uiPerformanceMode,
            ),
          ),

          Positioned(
            top: 116,
            left: 64,
            child: Opacity(
              opacity: uiPerformanceMode ? (t >= 0.5 ? 1.0 : 0.0) : t,
              child: HeroHeaderStatusDot(anime: anime),
            ),
          ),

          Positioned.fromRect(
            rect: titleRect,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                anime.title.display,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: AppPalette.textMain,
                  fontSize: titleFontSize,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.5,
                ),
              ),
            ),
          ),

          // Chip row — fixed position, opacity-only fade (no morph),
          // finishing by t = 0.6, well clear of the title's own band at
          // every point in the transition (see class doc).
          Positioned(
            left: 20,
            top: maxExtentValue - 32,
            right: 20,
            child: Opacity(
              opacity: uiPerformanceMode ? (t >= 0.3 ? 0.0 : 1.0) : 1.0 - fadeT,
              child: HeroBannerStatusChips(anime: anime),
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
