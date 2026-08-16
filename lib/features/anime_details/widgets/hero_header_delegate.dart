import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import '../../../core/theme/app_palette.dart';
import '../../../data/anilist/models/anime.dart';
import '../../../shared/utils/anime_status_style.dart';
import 'hero_banner.dart';
import 'hero_header_compact.dart';

/// Static fallback used only as [HeroHeaderDelegate.minExtentValue]'s
/// default parameter value (which must be a compile-time constant).
/// `AnimeDetailsScreen` overrides this with a context-derived value —
/// `MediaQuery.paddingOf(context).top` — so the collapsed header always
/// matches the navbar's real rendered height on the current device
/// (Scaffold's `extendBodyBehindAppBar` already folds the navbar's full
/// height into that padding value for any body descendant — see the
/// `navClearance` comment below). `build()` below never reads this
/// constant directly; it recomputes the same dynamic clearance locally
/// from live `MediaQuery` data.
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
/// The title has two representations that crossfade into each other as
/// the header collapses: an at-rest layer (wrap-enabled, up to 2 lines,
/// positioned at its natural spot) and a scrolling layer (single-line,
/// with its `Rect` and font size interpolated across the scroll range).
/// `crossfadeT` — derived from `_kAtRestFadeRange` — controls how much of
/// each layer is visible at a given scroll position; their opacities
/// always sum to 1, so the two are never both fully visible at once.
/// `fullTitleRect` uses the at-rest layer's actual measured height
/// (`titlePainter.height`, 1 or 2 lines depending on the title), and
/// both layers anchor their text the same way during the crossfade (see
/// `titleAlignment` below), which is what keeps the handoff between them
/// visually clean.
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

    // Scaffold's extendBodyBehindAppBar injects an inner MediaQuery for
    // any body descendant whose padding.top already equals the navbar's
    // full rendered height (nominal height plus real device inset) —
    // this delegate lives inside AnimeDetailsScreen, itself shown as
    // AppShell's body, so no separate navbar-height term is added here.
    // 0 on Android TV/desktop, matching the navbar's own real height
    // there too.
    final double navClearance = MediaQuery.paddingOf(context).top;

    const double compactBandHeight = 56;
    final double compactBandCenterY = navClearance + compactBandHeight / 2;

    final Color statusColor =
        anime.status?.statusColor ?? AppPalette.statusDefault;
    final String statusLabel = anime.status?.statusLabel ?? 'UNKNOWN';
    final _PillMetrics pillMetrics = _measureStatusPill(statusLabel, context);

    final bool hasEnglishSubtitle =
        anime.title.english != null &&
        anime.title.english != anime.title.romaji;

    // Sits just below the back button's own band (navClearance to
    // navClearance + compactBandHeight), with the same 16px breathing
    // gap the original fixed value (96 + 56 + 16 = 168) had baked in —
    // but derived from navClearance now, so it tracks the real device
    // inset instead of assuming a status bar height that may not match
    // this device. Left as a bare constant, a large enough top inset
    // pushes the back button's bottom edge at or past this position,
    // visually colliding with the at-rest title text below it.
    final double atRestTop = navClearance + compactBandHeight + 16;
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

    // atRestOpacity and lerpOpacity (below) sum to exactly 1 throughout,
    // so the at-rest and scrolling title layers dissolve into each other
    // without ever fully overlapping or leaving a gap.
    final double crossfadeT = (t / _kAtRestFadeRange).clamp(0.0, 1.0);
    final double atRestOpacity = uiPerformanceMode
        ? (t > 0 ? 0.0 : 1.0)
        : 1.0 - crossfadeT;
    final double lerpOpacity = uiPerformanceMode
        ? (t > 0 ? 1.0 : 0.0)
        : crossfadeT;

    // Matches the at-rest layer's measured content (titlePainter.height
    // — 1 or 2 lines, whichever this title needs).
    final Rect fullTitleRect = Rect.fromLTWH(
      20,
      atRestTop,
      contentMaxWidth,
      titlePainter.height,
    );
    // Derived from the dot's real position plus its fixed 8px diameter
    // and a 12px breathing gap — the same "measure it, don't guess"
    // principle applied to the full-state leadingGap.
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
                // range after the crossfade completes (titleAlignmentT
                // stays 0 until crossfadeT reaches 1). topLeft keeps the
                // crossfade dissolving cleanly against the at-rest
                // layer's own top-anchored text; centerLeft lines the
                // fully-collapsed title up against compactTitleRect's
                // back-button/dot vertical center.
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
            top: navClearance,
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
