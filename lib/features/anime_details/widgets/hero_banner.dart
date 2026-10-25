import 'package:flutter/material.dart';

import '../../../core/extensions/build_context_extensions.dart';
import '../../../core/theme/app_palette.dart';
import '../../../data/anilist/models/anime.dart';
import '../../../shared/widgets/app_network_image.dart';
import 'external_link_buttons.dart';

/// Banner image under a darkening gradient, filling its Stack parent.
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

/// Subtitle, episode chip, and link row below the title. [leadingGap]
/// reserves the width of the status pill HeroHeaderDelegate places beside it.
class HeroBannerMetaBlock extends StatelessWidget {
  final Anime anime;
  final double leadingGap;

  const HeroBannerMetaBlock({
    super.key,
    required this.anime,
    this.leadingGap = 0,
  });

  @override
  Widget build(BuildContext context) {
    final bool hasEnglishSubtitle =
        anime.title.english != null &&
        anime.title.english != anime.title.romaji;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (hasEnglishSubtitle) ...[
          Text(
            anime.title.english!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppPalette.textMuted,
              fontSize: 18,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 12),
        ],
        Row(
          children: [
            SizedBox(width: leadingGap),
            Expanded(
              child: Wrap(
                spacing: 10,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (anime.episodes != null)
                    _MetaChip(
                      label: '${anime.episodes} Episodes',
                      color: AppPalette.textLight,
                    ),
                  ExternalLinkButton(
                    label: 'AniList',
                    url: 'https://anilist.co/anime/${anime.id}',
                    color: const Color(0xFF3DB4F2),
                  ),
                  if (anime.idMal != null)
                    ExternalLinkButton(
                      label: 'MyAnimeList',
                      url: 'https://myanimelist.net/anime/${anime.idMal}',
                      color: const Color(0xFF2E51A2),
                    ),
                ],
              ),
            ),
          ],
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
