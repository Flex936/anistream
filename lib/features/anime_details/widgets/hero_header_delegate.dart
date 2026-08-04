import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import '../../../core/theme/app_palette.dart';
import '../../../data/anilist/models/anime.dart';
import '../../../shared/utils/anime_status_style.dart';
import 'hero_banner.dart';
import 'hero_header_compact.dart';

const double kHeroHeaderNavBarClearance = 96;

/// Precisely measured (not guessed) geometry for the full-state status
/// pill. Deterministic: given the same label text and the fixed style
/// constants HeroStatusIndicator renders with, this always returns the
/// exact size HeroStatusIndicator would actually occupy at
/// labelOpacity == 1, without needing a RenderBox/post-frame round-trip.
typedef _PillMetrics = ({double width, double height});

_PillMetrics _measureStatusPill(String label, BuildContext context) {
  const TextStyle labelStyle = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w700,
  );
  final TextPainter painter = TextPainter(
    text: TextSpan(text: label, style: labelStyle),
    textDirection: Directionality.of(context),
    maxLines: 1,
  )..layout();

  const double dotSize = 8;
  const double gapAfterDot = 8;
  const double hPad = 10;
  const double vPad = 4;

  final double contentWidth = dotSize + gapAfterDot + painter.width;
  final double contentHeight = painter.height > dotSize
      ? painter.height
      : dotSize;

  return (width: contentWidth + hPad * 2, height: contentHeight + vPad * 2);
}

/// Pinned, shrink-driven hero header for AnimeDetailsScreen.
///
/// The title has TWO representations that hand off near t = 0 via a
/// SEQUENTIAL fade — the at-rest (wrap-enabled, up to 2 lines) layer
/// fades fully to 0 over the FIRST half of `_kAtRestFadeRange`, then
/// only once it's gone does the scrolling (single-line, Rect/fontSize-
/// lerped) layer fade 0 -> 1 over the second half. The two are never
/// both partially visible at once.
///
/// This replaces an earlier version that faded both layers
/// SIMULTANEOUSLY over the same window, which produced a doubled/
/// smeared "cut off" look wherever both were partially opaque at once —
/// made worse by two consistency bugs fixed alongside this one:
///  - `fullTitleRect`'s height used to be a hardcoded single-line value
///    (44) even while the at-rest layer above it could genuinely be 2
///    lines tall (via `titlePainter.height`, already computed for
///    `metaContainerTop`'s sake) — so the lerp layer's box was shorter
///    than what it was overlapping.
///  - The lerp layer used to vertically CENTER its text inside that box
///    (`Alignment.centerLeft`), while the at-rest layer's text simply
///    started at the top of its own unconstrained-height box — two
///    different vertical anchors for what's supposed to read as the
///    same title. Now both anchor to `Alignment.topLeft`, so the
///    handoff lands exactly where the at-rest title's first line was.
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
    this.maxExtentValue = 360,
    this.minExtentValue = kHeroHeaderNavBarClearance + 56,
  });

  @override
  double get maxExtent => maxExtentValue;

  @override
  double get minExtent => minExtentValue;
  static const double _kAtRestFadeRange = 0.00;

  static const double _kMetaRowHeight = 32;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final double range = maxExtentValue - minExtentValue;
    final double t = range <= 0 ? 1.0 : (shrinkOffset / range).clamp(0.0, 1.0);
    final double fadeT = (t / 0.6).clamp(0.0, 1.0);
    final double labelT = (t / 0.35).clamp(0.0, 1.0);

    final Size screenSize = MediaQuery.sizeOf(context);
    final bool isLandscape = screenSize.width > screenSize.height;
    final double contentMaxWidth = isLandscape
        ? (screenSize.width / 2) - 20
        : screenSize.width - 40;

    const double compactBandHeight = 56;
    const double compactBandCenterY =
        kHeroHeaderNavBarClearance + compactBandHeight / 2;

    final Color statusColor =
        anime.status?.statusColor ?? AppPalette.statusDefault;
    final String statusLabel = anime.status?.statusLabel ?? 'UNKNOWN';
    final _PillMetrics pillMetrics = _measureStatusPill(statusLabel, context);

    final bool hasEnglishSubtitle =
        anime.title.english != null &&
        anime.title.english != anime.title.romaji;

    const double atRestTop = 168;
    final TextPainter titlePainter = TextPainter(
      text: TextSpan(
        text: anime.title.display,
        style: const TextStyle(
          fontSize: 32,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.5,
        ),
      ),
      textDirection: Directionality.of(context),
      maxLines: 2,
    )..layout(maxWidth: contentMaxWidth);

    final double metaContainerTop = atRestTop + titlePainter.height + 12;
    final double metaRowTop = metaContainerTop + (hasEnglishSubtitle ? 35 : 0);

    final Offset fullStatusOffset = Offset(
      20,
      metaRowTop + (_kMetaRowHeight - pillMetrics.height) / 2,
    );
    final Offset compactStatusOffset = Offset(64, compactBandCenterY - 4);
    final Offset statusOffset = uiPerformanceMode
        ? (t >= 0.5 ? compactStatusOffset : fullStatusOffset)
        : Offset.lerp(fullStatusOffset, compactStatusOffset, t)!;
    final double labelOpacity = uiPerformanceMode
        ? (t >= 0.35 ? 0.0 : 1.0)
        : 1.0 - labelT;

    // ── Title crossfade — genuinely simultaneous again (opacities sum
    // to exactly 1 throughout), not the sequential fade-out-then-fade-in
    // split from the previous round. That split was only needed because
    // the two layers used to disagree on height/alignment; now that
    // fullTitleRect uses the real measured titlePainter.height and both
    // layers share a common alignment strategy (see titleAlignment
    // below), a plain crossfade dissolves cleanly instead of doubling
    // or blinking to nothing at the midpoint. ──
    final double crossfadeT = (t / _kAtRestFadeRange).clamp(0.0, 1.0);
    final double atRestOpacity = uiPerformanceMode
        ? (t > 0 ? 0.0 : 1.0)
        : 1.0 - crossfadeT;
    final double lerpOpacity = uiPerformanceMode
        ? (t > 0 ? 1.0 : 0.0)
        : crossfadeT;

    // Height now matches the at-rest layer's ACTUAL measured content
    // (titlePainter.height — 1 or 2 lines, whatever this title needs)
    // instead of a hardcoded single-line value.
    final Rect fullTitleRect = Rect.fromLTWH(
      20,
      atRestTop,
      contentMaxWidth,
      titlePainter.height,
    );
    // Was a hardcoded 172 — unrelated to the compact dot's actual size,
    // which is what left the huge dead gap in the screenshot. Now
    // derived from the dot's real position + its fixed 8px diameter +
    // a 12px breathing gap, the same "measure it, don't guess"
    // principle already applied to the full-state leadingGap.
    final double compactTitleLeft = compactStatusOffset.dx + 8 + 12;
    final Rect compactTitleRect = Rect.fromLTWH(
      compactTitleLeft,
      compactBandCenterY - 16,
      screenSize.width - compactTitleLeft - 16,
      32,
    );
    final Rect titleRect = uiPerformanceMode
        ? (t >= 0.5 ? compactTitleRect : fullTitleRect)
        : Rect.lerp(fullTitleRect, compactTitleRect, t)!;
    final double titleFontSize = uiPerformanceMode
        ? (t >= 0.5 ? 17.0 : 32.0)
        : lerpDouble(32.0, 17.0, t)!;

    // 0 for the entire crossfade window (topLeft — matches the at-rest
    // layer's own anchor), then eases to 1 (centerLeft) across the rest
    // of the scroll range as t continues toward full collapse.
    final double titleAlignmentT = uiPerformanceMode
        ? (t >= 0.5 ? 1.0 : 0.0)
        : ((t - _kAtRestFadeRange) / (1.0 - _kAtRestFadeRange)).clamp(0.0, 1.0);
    final Alignment titleAlignment = Alignment.lerp(
      Alignment.topLeft,
      Alignment.centerLeft,
      titleAlignmentT,
    )!;

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

          if (atRestOpacity > 0)
            Positioned(
              left: 20,
              right: screenSize.width - 20 - contentMaxWidth,
              top: atRestTop,
              child: Opacity(
                opacity: atRestOpacity,
                child: Text(
                  anime.title.display,
                  maxLines: 2,
                  softWrap: true,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppPalette.textMain,
                    fontSize: 32,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.5,
                  ),
                ),
              ),
            ),

          if (lerpOpacity > 0)
            Positioned.fromRect(
              rect: titleRect,
              child: Opacity(
                opacity: lerpOpacity,
                // Lerps topLeft -> centerLeft across the remaining scroll
                // range AFTER the crossfade completes (not during it —
                // titleAlignmentT stays 0 until crossfadeT reaches 1).
                // topLeft is what makes the crossfade dissolve cleanly
                // against the at-rest layer's own top-anchored text;
                // centerLeft is what makes the fully-collapsed title
                // line up against compactTitleRect's back-button/dot
                // vertical center. A fixed topLeft throughout was
                // correct for the former and wrong for the latter —
                // this fixes the off-center look without reintroducing
                // the crossfade-time mismatch the fixed value fixed.
                child: Align(
                  alignment: titleAlignment,
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
            ),

          Positioned(
            left: statusOffset.dx,
            top: statusOffset.dy,
            child: HeroStatusIndicator(
              color: statusColor,
              label: statusLabel,
              labelOpacity: labelOpacity,
            ),
          ),

          Positioned(
            left: 20,
            top: metaContainerTop,
            width: contentMaxWidth,
            child: IgnorePointer(
              ignoring: t >= 0.6,
              child: Opacity(
                opacity: uiPerformanceMode
                    ? (t >= 0.3 ? 0.0 : 1.0)
                    : 1.0 - fadeT,
                child: HeroBannerMetaBlock(
                  anime: anime,
                  leadingGap: pillMetrics.width + 12,
                ),
              ),
            ),
          ),

          Positioned(
            left: 16,
            top: kHeroHeaderNavBarClearance,
            height: compactBandHeight,
            child: Align(
              alignment: Alignment.centerLeft,
              child: HeroHeaderBackButton(
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
