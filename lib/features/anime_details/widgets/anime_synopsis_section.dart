import 'package:flutter/material.dart';

import '../../../core/extensions/build_context_extensions.dart';
import '../../../core/theme/app_palette.dart';
import '../../../data/anilist/models/anime.dart';
import '../../../shared/utils/html_utils.dart';
import './external_link_buttons.dart';

/// The synopsis + external-link content that used to live inside
/// [HeroBanner]'s text column. Neither fits inside [HeroHeaderDelegate]'s
/// bounded [minExtent, maxExtent] box, so this renders as an ordinary
/// sliver sibling placed directly below the pinned header in
/// [AnimeDetailsScreen], above the "Episodes" section.
class AnimeSynopsisSection extends StatelessWidget {
  final Anime anime;

  const AnimeSynopsisSection({super.key, required this.anime});

  @override
  Widget build(BuildContext context) {
    final bool isMobile = context.isMobile;
    final double hPad = isMobile ? 24.0 : 48.0;
    final typography = context.appTypography;

    return Padding(
      padding: EdgeInsets.fromLTRB(hPad, 24, hPad, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (anime.title.english != null &&
              anime.title.english != anime.title.romaji) ...[
            Text(
              anime.title.english!,
              style: const TextStyle(
                color: AppPalette.textMuted,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 16),
          ],
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
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
          const SizedBox(height: 24),
          Text(
            stripAnilistHtml(anime.description, preserveLineBreaks: true),
            style: typography.heroSynopsis.copyWith(
              color: AppPalette.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}
