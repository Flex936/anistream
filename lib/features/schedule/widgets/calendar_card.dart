import 'package:dpad/dpad.dart';
import 'package:flutter/material.dart';

import '../../../core/extensions/build_context_extensions.dart';
import '../../../core/theme/app_palette.dart';
import '../../../data/anilist/models/anime.dart';
import '../../../shared/utils/perf_animations.dart';
import '../../../shared/widgets/app_network_image.dart';

class CalendarCard extends StatelessWidget {
  final Anime anime;
  final String Function(int timestamp) formatLocalTime;
  final String Function(int timestamp) getTimeRemaining;
  final bool autofocus;
  final VoidCallback? onTap;
  final bool uiPerformanceMode;

  /// Fixed height of the text block below the poster — the title line
  /// plus its surrounding spacing, plus the airing-time-remaining line.
  /// `ScheduledScreen`'s day shelves add this on top of the width-driven
  /// poster height to size each shelf.
  static const double kTextBlockHeight = 44;

  const CalendarCard({
    super.key,
    required this.anime,
    required this.formatLocalTime,
    required this.getTimeRemaining,
    this.autofocus = false,
    this.onTap,
    this.uiPerformanceMode = false,
  });

  @override
  Widget build(BuildContext context) {
    final nextEp = anime.nextAiringEpisode!;
    final epLabel = nextEp.episode > 0
        ? 'Ep ${nextEp.episode}'
        : 'Ep ${anime.episodes ?? "?"}';

    final typography = context.appTypography;
    final radii = context.appRadii;
    final cardSizes = context.appCardSizes;

    // DpadFocusable drives the border/shadow, the episode-label overlay's
    // opacity, and the title color, all off a single state.focused value
    // — builder rebuilds the whole visual tree rather than splitting out
    // a focus-independent `child`, since nearly everything here depends
    // on focus state anyway.
    return DpadFocusable(
      autofocus: autofocus,
      onSelect: () => onTap?.call(),
      builder: (context, state, child) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          AspectRatio(
            // Matches AniList's coverImage art (2:3) — the same
            // canonical ratio every other poster card in the app shares
            // via AppCardSizes.
            aspectRatio: cardSizes.posterAspectRatio,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(radii.small),
                border: Border.all(
                  color: state.focused
                      ? AppPalette.primary.withValues(alpha: 0.80)
                      : AppPalette.border,
                  width: state.focused ? 2 : 1,
                ),
                boxShadow: uiPerformanceMode
                    ? null
                    : const [
                        BoxShadow(
                          color: Color(0x4D000000),
                          blurRadius: 8,
                          offset: Offset(0, 4),
                        ),
                      ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(radii.small),
                // Clip.hardEdge under Performant mode — see
                // FrostedContainer's doc comment for the rationale.
                clipBehavior: uiPerformanceMode
                    ? Clip.hardEdge
                    : Clip.antiAlias,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // cacheWidth matched to this card's 170dp display
                    // width in ScheduledScreen's day shelves.
                    AppNetworkImage(
                      url: anime.coverImage?.large,
                      cacheWidth: 400,
                      uiPerformanceMode: uiPerformanceMode,
                    ),
                    AnimatedOpacity(
                      opacity: state.focused ? 1.0 : 0.0,
                      duration: perfDuration(
                        uiPerformanceMode,
                        const Duration(milliseconds: 250),
                      ),
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [
                              AppPalette.black.withValues(alpha: 0.80),
                              AppPalette.transparent,
                            ],
                          ),
                        ),
                        alignment: Alignment.bottomLeft,
                        padding: const EdgeInsets.all(6),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: AppPalette.primary,
                            // Fully-rounded stadium/pill badge — 20
                            // exceeds half this container's height to
                            // guarantee a full pill curve regardless of
                            // content length, so it's left as a plain
                            // literal rather than one of the tag/small/
                            // large tiers.
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            epLabel,
                            style: typography.badgeLabel.copyWith(
                              color: AppPalette.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 6,
                      right: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: AppPalette.black.withValues(
                            alpha: uiPerformanceMode ? 0.9 : 0.72,
                          ),
                          borderRadius: BorderRadius.circular(radii.tag),
                          border: Border.all(
                            color: AppPalette.statusReleasing.withValues(
                              alpha: 0.40,
                            ),
                          ),
                        ),
                        child: Text(
                          formatLocalTime(nextEp.airingAt),
                          style: typography.badgeLabel.copyWith(
                            color: AppPalette.statusReleasing,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 150),
            style: typography.cardTitleCompact.copyWith(
              color: state.focused ? AppPalette.primary : AppPalette.textMain,
            ),
            child: Text(
              anime.title.romaji ?? anime.title.english ?? 'Unknown',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            getTimeRemaining(nextEp.airingAt),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AppPalette.textMuted, fontSize: 10),
          ),
        ],
      ),
      child: const SizedBox.shrink(),
    );
  }
}
