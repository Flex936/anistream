import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import '../../../core/theme/app_palette.dart';
import '../../../data/anilist/models/anime.dart';
import 'hero_banner.dart';
import 'hero_header_compact.dart';

/// Vertical clearance the persistent AniStreamNavBar needs below it before
/// any hero-header content can safely render — the navbar is transparent
/// until scrolled past 20px (see `_AppShellState._isScrolled`), so anything
/// painted above this line in EITHER the full or compact header state sits
/// directly behind/under its icon row with no guaranteed backdrop. Matches
/// the same 96 value HomeScreen/ScheduledScreen already use for their own
/// top scroll padding.
const double kHeroHeaderNavBarClearance = 96;

/// Pinned, shrink-driven hero header for AnimeDetailsScreen.
///
/// The title is NOT part of either HeroBanner or the compact chrome
/// widgets — it's owned directly here as a single Text whose
/// position/size is lerped between a "full" and "compact" Rect as
/// shrinkOffset climbs from 0 to (maxExtent - minExtent). That produces a
/// genuine "title migrates into a small top bar" motion instead of two
/// independent title copies cross-fading over each other, which is what
/// caused the double-title ghosting bug in the previous version: both
/// layers were wrapped in Opacity, so mid-transition NEITHER was fully
/// opaque, leaving a real gap in this pinned sliver's paint that let
/// AnimeSynopsisSection — scrolling up from underneath — show through.
///
/// Two fixes address that directly:
///  1. An unconditionally opaque ColoredBox is painted first, before
///     anything else, so this sliver's paint has no gap at any point in
///     the transition regardless of what's fading above it.
///  2. Poster thumbnail + status chips still cross-fade (there's no
///     sensible "morphed" position for a poster thumbnail to migrate to),
///     but finish fading out by t = 0.6 rather than t = 1.0, so nothing
///     is ever mid-fade at the exact moment the title finishes its move.
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
    // 280 leaves ~184px of usable content below the navbar clearance —
    // enough for the 114-tall poster thumb plus breathing room.
    this.maxExtentValue = 280,
    // clearance (96) + one comfortable content row (48) — the smallest
    // box that holds the back button + collapsed title without either
    // sitting behind the navbar or feeling cramped.
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
    // Poster/chips finish fading by 60% of the way through the collapse.
    final double fadeT = (t / 0.6).clamp(0.0, 1.0);

    final double width = MediaQuery.sizeOf(context).width;

    // Title geometry: bottom-left of the full banner -> a slim row just
    // below the navbar clearance. Single-line + ellipsis in BOTH states
    // deliberately — a continuous Rect/fontSize lerp can't reconcile a
    // 2-line height against a 1-line height mid-transition, so the title
    // never wraps regardless of collapse state. (Values below are
    // reasonable starting points, easy to nudge once seen live.)
    final Rect fullRect = Rect.fromLTWH(
      92,
      maxExtentValue - 52,
      width - 116,
      36,
    );
    final Rect compactRect = Rect.fromLTWH(80, 104, width - 104, 32);
    final Rect titleRect = uiPerformanceMode
        ? (t >= 0.5 ? compactRect : fullRect)
        : Rect.lerp(fullRect, compactRect, t)!;
    final double titleFontSize = uiPerformanceMode
        ? (t >= 0.5 ? 15.0 : 20.0)
        : lerpDouble(20.0, 15.0, t)!;

    return ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Opaque backing — see class doc, fix #1.
          const ColoredBox(color: AppPalette.base),

          // Banner artwork + gradient — fades out entirely by t = 1,
          // revealing the opaque backing as a natural darkening rather
          // than an artistic overlay once fully collapsed.
          Opacity(
            opacity: uiPerformanceMode ? (t >= 0.5 ? 0.0 : 1.0) : 1.0 - t,
            child: HeroBanner(
              anime: anime,
              uiPerformanceMode: uiPerformanceMode,
            ),
          ),

          // Back button — static across the whole transition; it's the
          // one element with an identical role and position in both
          // states, so there's nothing for it to morph between.
          Positioned(
            top: kHeroHeaderNavBarClearance,
            left: 16,
            child: HeroHeaderBackButton(
              onBack: onBack,
              uiPerformanceMode: uiPerformanceMode,
            ),
          ),

          // Status dot — only meaningful once the title has migrated
          // into the compact row, so it fades in over fix #2's window.
          Positioned(
            top: 116,
            left: 64,
            child: Opacity(
              opacity: uiPerformanceMode ? (t >= 0.5 ? 1.0 : 0.0) : t,
              child: HeroHeaderStatusDot(anime: anime),
            ),
          ),

          // The single, geometry-interpolated title.
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
                  letterSpacing: -0.4,
                ),
              ),
            ),
          ),

          // Poster + status chips — cross-fade only, no morphed position;
          // finishes by fadeT reaching 1 (t = 0.6, see class doc fix #2).
          Positioned(
            left: 16,
            bottom: 16,
            child: Opacity(
              opacity: uiPerformanceMode ? (t >= 0.3 ? 0.0 : 1.0) : 1.0 - fadeT,
              child: HeroBannerPosterAndChips(
                anime: anime,
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
