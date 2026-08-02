import 'package:flutter/material.dart';

import '../../../core/extensions/build_context_extensions.dart';
import '../../../core/settings/settings_scope.dart';
import '../../../core/theme/app_palette.dart';
import '../../../data/anilist/models/anime.dart';
import '../../../shared/utils/html_utils.dart';
import '../../../shared/utils/perf_animations.dart';
import '../../../shared/widgets/hover_focus_builder.dart';
import './external_link_buttons.dart';

/// The synopsis + external-link content that lives directly below the
/// pinned hero header (see HeroHeaderDelegate) — moved out of the hero
/// itself since neither fits inside a bounded [minExtent, maxExtent] box.
///
/// Synopsis text is clamped to [_collapsedMaxLines] with a "Show more" /
/// "Show less" toggle rather than left unbounded — an unbounded synopsis
/// was the actual regression here: since this widget is no longer
/// squeezed into a fixed-height banner, dropping the old maxLines clamp
/// entirely (as the first version of this file did) let genuinely long
/// AniList descriptions run to a dozen-plus paragraphs with no way to
/// collapse them back down.
class AnimeSynopsisSection extends StatefulWidget {
  final Anime anime;

  const AnimeSynopsisSection({super.key, required this.anime});

  @override
  State<AnimeSynopsisSection> createState() => _AnimeSynopsisSectionState();
}

class _AnimeSynopsisSectionState extends State<AnimeSynopsisSection> {
  static const int _collapsedMaxLines = 4;

  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final bool isMobile = context.isMobile;
    final double hPad = isMobile ? 24.0 : 48.0;
    final typography = context.appTypography;
    final bool uiPerformanceMode = SettingsScope.of(context).uiPerformanceMode;

    final String synopsis = stripAnilistHtml(
      widget.anime.description,
      preserveLineBreaks: true,
    );
    final TextStyle synopsisStyle = typography.heroSynopsis.copyWith(
      color: AppPalette.textMuted,
    );

    return Padding(
      padding: EdgeInsets.fromLTRB(hPad, 24, hPad, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.anime.title.english != null &&
              widget.anime.title.english != widget.anime.title.romaji) ...[
            Text(
              widget.anime.title.english!,
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
                url: 'https://anilist.co/anime/${widget.anime.id}',
                color: const Color(0xFF3DB4F2),
              ),
              if (widget.anime.idMal != null)
                ExternalLinkButton(
                  label: 'MyAnimeList',
                  url: 'https://myanimelist.net/anime/${widget.anime.idMal}',
                  color: const Color(0xFF2E51A2),
                ),
            ],
          ),
          const SizedBox(height: 24),
          LayoutBuilder(
            builder: (context, constraints) {
              // Measures whether the FULL synopsis would actually
              // overflow _collapsedMaxLines at this width — the "Show
              // more" toggle only appears when it's genuinely needed.
              final TextPainter painter = TextPainter(
                text: TextSpan(text: synopsis, style: synopsisStyle),
                maxLines: _collapsedMaxLines,
                textDirection: Directionality.of(context),
              )..layout(maxWidth: constraints.maxWidth);
              final bool isOverflowing = painter.didExceedMaxLines;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AnimatedSize(
                    duration: perfDuration(
                      uiPerformanceMode,
                      const Duration(milliseconds: 250),
                    ),
                    curve: Curves.easeOutCubic,
                    alignment: Alignment.topCenter,
                    child: Text(
                      synopsis,
                      maxLines: _expanded ? null : _collapsedMaxLines,
                      overflow: _expanded
                          ? TextOverflow.visible
                          : TextOverflow.ellipsis,
                      style: synopsisStyle,
                    ),
                  ),
                  if (isOverflowing) ...[
                    const SizedBox(height: 8),
                    HoverFocusBuilder(
                      onTap: () => setState(() => _expanded = !_expanded),
                      builder: (context, hovered) => Text(
                        _expanded ? 'Show less' : 'Show more',
                        style: TextStyle(
                          color: hovered
                              ? AppPalette.primaryHover
                              : AppPalette.primary,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
