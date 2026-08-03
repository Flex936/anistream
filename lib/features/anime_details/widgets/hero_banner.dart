import 'package:flutter/material.dart';

import '../../../core/extensions/build_context_extensions.dart';
import '../../../core/theme/app_palette.dart';
import '../../../data/anilist/models/anime.dart';
import '../../../shared/widgets/app_network_image.dart';
import 'external_link_buttons.dart';

/// The background art layer of the collapsing hero header — banner image
/// + darkening gradient only. Unchanged from the previous round; the
/// enlarged banner height is a maxExtentValue change owned by
/// HeroHeaderDelegate, not this widget, since HeroBanner just fills
/// whatever height a Stack.expand parent hands it.
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

/// The full-state metadata group that sits below the (delegate-owned,
/// title-morphing) title block: the English subtitle, the episode-count
/// chip, and the AniList/MyAnimeList link row. Fades in place as a single
/// unit — no motion of its own, unlike the title or the status indicator
/// (HeroStatusIndicator), which both interpolate position across the
/// scroll instead of just opacity.
///
/// The status pill itself is deliberately NOT rendered here — it's owned
/// directly by HeroHeaderDelegate as an independently-positioned,
/// continuously-morphing widget (full pill -> bare dot next to the
/// title), the same way the title itself already works. [leadingGap]
/// reserves the horizontal space that pill occupies in its full-state
/// position, so this block's own row lines up beside it rather than
/// overlapping it.
///
/// The AniList/MyAnimeList buttons are moved here from
/// AnimeSynopsisSection, which still renders its own copy of them until
/// that file is updated in a later phase — expect a brief duplicate
/// AniList/MyAnimeList row on screen until then.
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
