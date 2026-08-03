import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import '../../../core/theme/app_palette.dart';
import '../../../data/anilist/models/anime.dart';
import '../../../shared/utils/anime_status_style.dart';
import 'hero_banner.dart';
import 'hero_header_compact.dart';

const double kHeroHeaderNavBarClearance = 96;

/// Precisely measured (not guessed) geometry for the full-state status
/// pill — see class doc below for why this exists at all. Deterministic:
/// given the same label text and the fixed style constants
/// HeroStatusIndicator renders with, this always returns the exact same
/// size HeroStatusIndicator would actually occupy at labelOpacity == 1,
/// without needing a RenderBox/post-frame round-trip to find out.
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

  // Matches HeroStatusIndicator's Row exactly: 8px dot, 8px gap, label.
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
/// The title has TWO representations that crossfade near t = 0, rather
/// than one continuous geometric lerp covering the whole scroll range
/// like the rest of this header:
///  - At rest (the crossfade's 0 end): a normal flow Text, maxLines: 2,
///    softWrap enabled — long titles wrap instead of truncating.
///  - Scrolling (the crossfade's 1 end): the existing single-line
///    Rect/fontSize lerp mechanism, unchanged in kind from earlier
///    rounds.
/// This split exists because Flutter has no way to continuously
/// interpolate a wrapped 2-line text block into a 1-line one —
/// maxLines is discrete, not lerpable — so a title long enough to need
/// 2 lines can only ever hand off between the two representations, not
/// smoothly morph. The crossfade (over `_kAtRestFadeRange` of the
/// scroll range) is what keeps that handoff from being a hard, jarring
/// pop the instant scrolling starts.
///
/// The status pill does NOT need this split — HeroStatusIndicator's own
/// full-state size is precisely computable via `_measureStatusPill`
/// (see its doc comment), so a single continuous Offset lerp from that
/// EXACT computed position to the compact dot position is both correct
/// at t = 0 and smooth throughout — no discrete jump to paper over. That
/// same measurement is also what HeroBannerMetaBlock's `leadingGap` uses
/// now, instead of a previously-guessed constant that broke the moment
/// a status label longer than "FINISHED" showed up.
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
    // Bumped 344 -> 360 to comfortably fit a 2-line title at rest
    // without the meta row crowding the bottom edge.
    this.maxExtentValue = 360,
    this.minExtentValue = kHeroHeaderNavBarClearance + 56,
  });

  @override
  double get maxExtent => maxExtentValue;

  @override
  double get minExtent => minExtentValue;

  // How much of the scroll range the at-rest -> lerp title crossfade
  // spans — short and near-instant, but not an instant hard cut.
  static const double _kAtRestFadeRange = 0.08;

  // Matches ExternalLinkButton's current rendered height — the tallest
  // item in HeroBannerMetaBlock's row today, used to vertically center
  // the status pill against it. Revisit once external_link_buttons.dart
  // gets its own restyle pass.
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

    // ── At-rest title measurement — how tall the wrap-enabled title
    // ACTUALLY renders at this width, for this specific anime's title
    // text, rather than assuming a fixed 1- or 2-line height. This is
    // what lets everything below the title (subtitle, status pill, meta
    // row) position itself correctly regardless of whether a given
    // title happens to wrap to 1 or 2 lines. ──
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
    // Subtitle's own height isn't individually measured — it's always
    // single-line (no wrap bug reported for it), so a close constant is
    // fine here without the same precision the title needed.
    final double metaRowTop = metaContainerTop + (hasEnglishSubtitle ? 35 : 0);

    // ── Status pill — single continuous Offset lerp, correct at both
    // ends now: fullStatusOffset centers the pill against
    // _kMetaRowHeight instead of just top-aligning it (fix for #2), and
    // compactStatusOffset is unchanged from before. ──
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

    // ── Title crossfade — see class doc. ──
    final double atRestOpacity = uiPerformanceMode
        ? (t > 0 ? 0.0 : 1.0)
        : 1.0 - (t / _kAtRestFadeRange).clamp(0.0, 1.0);
    final double lerpOpacity = uiPerformanceMode
        ? (t > 0 ? 1.0 : 0.0)
        : (t / _kAtRestFadeRange).clamp(0.0, 1.0);

    final Rect fullTitleRect = Rect.fromLTWH(
      20,
      atRestTop,
      contentMaxWidth,
      44,
    );
    final Rect compactTitleRect = Rect.fromLTWH(
      172,
      compactBandCenterY - 16,
      screenSize.width - 172 - 16,
      32,
    );
    final Rect titleRect = uiPerformanceMode
        ? (t >= 0.5 ? compactTitleRect : fullTitleRect)
        : Rect.lerp(fullTitleRect, compactTitleRect, t)!;
    final double titleFontSize = uiPerformanceMode
        ? (t >= 0.5 ? 17.0 : 32.0)
        : lerpDouble(32.0, 17.0, t)!;

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

          // At-rest title — wrap-enabled, only built while it could
          // plausibly be visible.
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

          // Scrolling title — single-line Rect/fontSize lerp, unchanged
          // mechanism from earlier rounds.
          if (lerpOpacity > 0)
            Positioned.fromRect(
              rect: titleRect,
              child: Opacity(
                opacity: lerpOpacity,
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
