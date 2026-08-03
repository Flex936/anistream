import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import '../../../core/theme/app_palette.dart';
import '../../../data/anilist/models/anime.dart';
import '../../../shared/utils/anime_status_style.dart';
import 'hero_banner.dart';
import 'hero_header_compact.dart';

const double kHeroHeaderNavBarClearance = 96;

/// Pinned, shrink-driven hero header for AnimeDetailsScreen.
///
/// Full-state vertical order, top to bottom: title, then
/// HeroBannerMetaBlock (English subtitle + episode chip + AniList/
/// MyAnimeList buttons), with the status pill positioned independently
/// to its left. Both the title AND the status indicator morph position
/// continuously into the collapsed bar as shrinkOffset climbs — the
/// title via a Rect+fontSize lerp (unchanged mechanism from earlier
/// rounds), the status indicator via a simpler Offset lerp, since
/// HeroStatusIndicator now shrinks its own chip decoration down to a
/// bare dot as its labelOpacity fades (see hero_header_compact.dart) —
/// there's no separate size for the delegate itself to interpolate.
///
/// Three back-button-reliability fixes live here, replacing the
/// previous per-element hand-tuned offsets:
///  1. The back button is the LAST Stack child — topmost paint and
///     hit-test priority, so nothing painted after it can steal its tap.
///  2. HeroBannerMetaBlock — the one fading group with interactive
///     children (the AniList/MyAnimeList buttons) — is wrapped in
///     IgnorePointer once its own opacity reaches 0, so an invisible
///     widget can never silently swallow a tap meant for whatever sits
///     beneath it.
///  3. The back button, the status indicator's compact position, and
///     the title's compact position all derive their vertical center
///     from the SAME `compactBandCenterY` constant, rather than three
///     independently guessed offsets — which is what caused the
///     misaligned scrolled-down bar this round is fixing.
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
    // Bumped from 280 -> 344 per the "slightly bigger banner" request —
    // leaves room for title + subtitle + meta row without feeling
    // cramped at the new, larger font sizes.
    this.maxExtentValue = 344,
    // clearance (96) + one comfortable compact-bar row (56).
    this.minExtentValue = kHeroHeaderNavBarClearance + 56,
  });

  @override
  double get maxExtent => maxExtentValue;

  @override
  double get minExtent => minExtentValue;

  bool get _hasEnglishSubtitle =>
      anime.title.english != null && anime.title.english != anime.title.romaji;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final double range = maxExtentValue - minExtentValue;
    final double t = range <= 0 ? 1.0 : (shrinkOffset / range).clamp(0.0, 1.0);
    // Banner art + meta block finish fading by 60% of the way through.
    final double fadeT = (t / 0.6).clamp(0.0, 1.0);
    // Status label fades faster still — by ~35% — so only the bare dot
    // is left well before the title finishes its own move.
    final double labelT = (t / 0.35).clamp(0.0, 1.0);

    final Size screenSize = MediaQuery.sizeOf(context);
    final bool isLandscape = screenSize.width > screenSize.height;
    // "Titles can't be longer than half the screen's width in landscape" —
    // applies to both the title AND the meta block below it, so the
    // whole text column shares one consistent right edge.
    final double contentMaxWidth = isLandscape
        ? (screenSize.width / 2) - 20
        : screenSize.width - 40;

    // ── Shared compact-band geometry — see class doc, fix #3. ──
    const double compactBandHeight = 56;
    const double compactBandCenterY =
        kHeroHeaderNavBarClearance + compactBandHeight / 2;

    // Title — bigger font (32, down to 17 collapsed; was 20/15).
    final Rect fullTitleRect = Rect.fromLTWH(20, 176, contentMaxWidth, 44);
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

    // Where HeroBannerMetaBlock's own container starts vs. where its
    // internal ROW (episode chip + links) starts — these differ by the
    // English-subtitle line's height + gap when one exists, which is why
    // the status pill's full position needs to know about it too (it
    // sits beside that row, not beside the subtitle).
    const double metaContainerTop = 236;
    final double metaRowTop = metaContainerTop + (_hasEnglishSubtitle ? 35 : 0);

    final Offset fullStatusOffset = Offset(20, metaRowTop);
    final Offset compactStatusOffset = Offset(64, compactBandCenterY - 4);
    final Offset statusOffset = uiPerformanceMode
        ? (t >= 0.5 ? compactStatusOffset : fullStatusOffset)
        : Offset.lerp(fullStatusOffset, compactStatusOffset, t)!;
    final double labelOpacity = uiPerformanceMode
        ? (t >= 0.35 ? 0.0 : 1.0)
        : 1.0 - labelT;

    final Color statusColor =
        anime.status?.statusColor ?? AppPalette.statusDefault;
    final String statusLabel = anime.status?.statusLabel ?? 'UNKNOWN';

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

          Positioned(
            left: statusOffset.dx,
            top: statusOffset.dy,
            child: HeroStatusIndicator(
              color: statusColor,
              label: statusLabel,
              labelOpacity: labelOpacity,
            ),
          ),

          // HeroBannerMetaBlock — English subtitle + episode chip +
          // AniList/MyAnimeList row. leadingGap reserves the horizontal
          // space the status pill's full-state position occupies, so
          // this block's own row starts just past it rather than
          // overlapping it.
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
                child: HeroBannerMetaBlock(anime: anime, leadingGap: 108),
              ),
            ),
          ),

          // Back button — LAST child, vertically centered against the
          // same compact-band constant as everything else. See class doc
          // fixes #1 and #3.
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
