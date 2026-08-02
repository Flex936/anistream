import 'package:flutter/material.dart';

import '../../../core/extensions/build_context_extensions.dart';
import '../../../core/theme/app_palette.dart';
import '../../../data/anilist/models/anime.dart';
import '../../../shared/utils/anime_status_style.dart';
import '../../../shared/widgets/app_network_image.dart';

/// The background art layer of the collapsing hero header — banner image
/// + darkening gradient only. Everything else that used to live here
/// (back button, poster thumbnail, title) is now owned by
/// HeroHeaderDelegate directly, or by HeroBannerPosterAndChips /
/// HeroHeaderBackButton — see hero_header_delegate.dart's class doc for
/// why splitting these apart fixes the double-title ghosting bug.
class HeroBanner extends StatelessWidget {
  final Anime anime;
  final bool uiPerformanceMode;

  const HeroBanner({
    super.key,
    required this.anime,
    this.uiPerformanceMode = false,
  });

  @override
  Widget build(BuildContext context) {
    final String? bannerUrl = anime.bannerImage ?? anime.coverImage?.extraLarge;

    return Stack(
      fit: StackFit.expand,
      children: [
        if (bannerUrl != null)
          AppNetworkImage(url: bannerUrl, uiPerformanceMode: uiPerformanceMode)
        else
          const ColoredBox(color: AppPalette.surface),
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                // Bumped from 0.2 -> 0.35 at the top stop specifically so
                // the back button/status area stays legible against
                // bright artwork before the navbar's own scroll-driven
                // backdrop (AppShell._isScrolled) has kicked in.
                AppPalette.base.withValues(alpha: 0.35),
                AppPalette.base.withValues(alpha: 0.75),
                AppPalette.base,
              ],
              stops: const [0.0, 0.6, 1.0],
            ),
          ),
        ),
      ],
    );
  }
}

/// Poster thumbnail + status chips — the part of the old full-state hero
/// that still makes sense as a straightforward opacity fade (there's no
/// sensible "morphed" position for a poster thumbnail to migrate to,
/// unlike the title). Positioned by HeroHeaderDelegate, not by itself.
class HeroBannerPosterAndChips extends StatelessWidget {
  final Anime anime;
  final bool uiPerformanceMode;

  const HeroBannerPosterAndChips({
    super.key,
    required this.anime,
    this.uiPerformanceMode = false,
  });

  @override
  Widget build(BuildContext context) {
    final String? posterUrl = anime.coverImage?.extraLarge;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (posterUrl != null)
          _PosterThumb(url: posterUrl, uiPerformanceMode: uiPerformanceMode),
        const SizedBox(width: 16),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            _MetaChip(
              label: anime.status?.statusLabel ?? 'UNKNOWN',
              color: anime.status?.statusColor ?? AppPalette.statusDefault,
            ),
            if (anime.episodes != null)
              _MetaChip(
                label: '${anime.episodes} Episodes',
                color: AppPalette.textLight,
              ),
          ],
        ),
      ],
    );
  }
}

class _PosterThumb extends StatelessWidget {
  final String url;
  final bool uiPerformanceMode;
  const _PosterThumb({required this.url, this.uiPerformanceMode = false});

  @override
  Widget build(BuildContext context) {
    final radii = context.appRadii;

    return Container(
      width: 76,
      height: 114,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radii.small),
        boxShadow: uiPerformanceMode
            ? null
            : [
                BoxShadow(
                  color: AppPalette.black.withValues(alpha: 0.5),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radii.small),
        clipBehavior: uiPerformanceMode ? Clip.hardEdge : Clip.antiAlias,
        child: AppNetworkImage(
          url: url,
          cacheWidth: 200,
          uiPerformanceMode: uiPerformanceMode,
        ),
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  final String label;
  final Color color;
  const _MetaChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    final typography = context.appTypography;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Text(label, style: typography.metaLabel.copyWith(color: color)),
    );
  }
}
