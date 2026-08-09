import 'package:flutter/material.dart';

import '../../../core/extensions/build_context_extensions.dart';
import '../../../core/settings/settings_scope.dart';
import '../../../core/theme/app_palette.dart';
import '../../../data/anilist/models/anime.dart';
import '../../../shared/utils/html_utils.dart';
import '../../../shared/utils/perf_animations.dart';
import '../../../shared/widgets/hover_focus_builder.dart';

/// The synopsis section that lives directly below the pinned hero header
/// (see HeroHeaderDelegate). Renders only the synopsis text and its
/// "Show more"/"Show less" toggle — the English subtitle and the
/// AniList/MyAnimeList link row render inside the hero banner itself
/// (see HeroBannerMetaBlock in hero_banner.dart), below the title.
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
      child: LayoutBuilder(
        builder: (context, constraints) {
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
                child: Stack(
                  children: [
                    Text(
                      synopsis,
                      maxLines: _expanded ? null : _collapsedMaxLines,
                      overflow: _expanded
                          ? TextOverflow.visible
                          : TextOverflow.ellipsis,
                      style: synopsisStyle,
                    ),
                    if (!_expanded && isOverflowing)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: IgnorePointer(
                          child: Container(
                            height: 22,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  AppPalette.base.withValues(alpha: 0),
                                  AppPalette.base,
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (isOverflowing) ...[
                const SizedBox(height: 6),
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
    );
  }
}
