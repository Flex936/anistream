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

    // ── Pulled once at the top of build() ──
    final typography = context.appTypography;
    final radii = context.appRadii;

    // ── DpadFocusable replaces HoverFocusBuilder. Multiple nested parts
    // (the border/shadow, the episode-label overlay's opacity, the title
    // color) all depend on the focus state, so — same as AnimeCard —
    // there's no focus-independent subtree worth passing through `child`;
    // builder rebuilds the whole visual tree, keyed off state.focused
    // instead of the old hovered bool. ──
    return DpadFocusable(
      autofocus: autofocus,
      onSelect: () => onTap?.call(),
      builder: (context, state, child) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          AspectRatio(
            aspectRatio: 2 / 3,
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
                // ── Clip.hardEdge under Performant mode — see
                // FrostedContainer's doc comment for the rationale. ──
                clipBehavior: uiPerformanceMode
                    ? Clip.hardEdge
                    : Clip.antiAlias,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // ── cacheWidth added: displayed at 160dp in
                    // ScheduledScreen's day shelves, was decoding
                    // `coverImage.large` at full resolution. ──
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
                            // ── Deliberately LEFT as a plain literal, not
                            // routed through AppRadii. This is a
                            // fully-rounded stadium/pill badge — 20
                            // exceeds half this small container's height
                            // specifically to guarantee a full pill curve,
                            // the same "stadium" pattern flagged in
                            // watchlist_cards.dart's _PlayOverlay. None of
                            // tag/small/large are a semantic match. ──
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
          // ── Left as a plain literal (fontSize: 10, no weight set) —
          // doesn't match any identified cluster. ──
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
