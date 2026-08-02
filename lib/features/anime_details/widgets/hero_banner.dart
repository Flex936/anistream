import 'package:flutter/material.dart';

import '../../../core/extensions/build_context_extensions.dart';
import '../../../core/theme/app_palette.dart';
import '../../../data/anilist/models/anime.dart';
import '../../../shared/utils/anime_status_style.dart';
import '../../../shared/widgets/app_network_image.dart';

/// The background art layer of the collapsing hero header — banner image
/// + darkening gradient only. Everything else lives in HeroHeaderDelegate
/// directly, or in HeroBannerStatusChips / HeroHeaderBackButton below.
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
    final String? bannerUrl =
        anime.bannerImage ?? anime.coverImage?.extraLarge;

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

/// Status/episode-count chips only — the poster thumbnail previously
/// rendered alongside these has been removed entirely: it duplicated the
/// poster already shown wherever the user navigated here from
/// (AnimeCard, WatchlistCard, CalendarCard), and its removal is what
/// frees up the room the title now uses. This also fixes the
/// title/chip overlap bug — see HeroHeaderDelegate's class doc — by no
/// longer needing to share a horizontal row with anything else.
class HeroBannerStatusChips extends StatelessWidget {
  final Anime anime;
  const HeroBannerStatusChips({super.key, required this.anime});

  @override
  Widget build(BuildContext context) {
    return Wrap(
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