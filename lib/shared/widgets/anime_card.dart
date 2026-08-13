import 'dart:async';

import 'package:dpad/dpad.dart';
import 'package:flutter/material.dart';

import '../../core/extensions/build_context_extensions.dart';
import '../../core/input/input_mode_scope.dart';
import '../../core/settings/settings_scope.dart';
import '../../core/theme/app_palette.dart';
import '../../data/anilist/models/anime.dart';
import '../../features/anime_details/anime_details_screen.dart';
import '../utils/anime_status_style.dart';
import '../utils/perf_animations.dart';
import 'app_network_image.dart';
import 'frosted_container.dart';

class AnimeCard extends StatelessWidget {
  final Anime anime;
  final ValueChanged<Anime>? onSelect;
  final bool autofocus;

  /// Fixed height of the text block below the poster — the title line
  /// (cardTitleCompact) plus its surrounding spacing, plus the
  /// episode-count line. Grid callers that size their own
  /// `SliverGridDelegateWithMaxCrossAxisExtent` (SearchResultsScreen) need
  /// this on top of the width-driven poster height to size the cell
  /// without clipping the text.
  static const double kTextBlockHeight = 48;

  const AnimeCard({
    super.key,
    required this.anime,
    this.onSelect,
    this.autofocus = false,
  });

  @override
  Widget build(BuildContext context) {
    final uiPerformanceMode = SettingsScope.of(context).uiPerformanceMode;
    final dpadModeActive = context.dpadModeActive;

    final typography = context.appTypography;
    final radii = context.appRadii;
    final cardSizes = context.appCardSizes;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AspectRatio(
          // Matches AniList's own coverImage art (2:3) — see
          // AppCardSizes's doc comment for why this is the shared
          // canonical ratio rather than a per-screen crop.
          aspectRatio: cardSizes.posterAspectRatio,
          // The poster's hover overlay (_HoverOverlay) depends on
          // visuallyFocused, so there's no focus-independent subtree
          // worth passing through `child` — builder rebuilds the whole
          // visual tree, keyed off state.focused && dpadModeActive.
          child: DpadFocusable(
            autofocus: autofocus && dpadModeActive,
            onSelect: () {
              if (onSelect != null) {
                onSelect!(anime);
              } else {
                unawaited(
                  Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => AnimeDetailsScreen(anime: anime),
                    ),
                  ),
                );
              }
            },
            builder: (context, state, child) {
              // Visible only in confirmed D-Pad/TV mode (DESIGN.md § 4)
              // — DpadFocusable's own state.focused doesn't distinguish
              // a real TV remote from an incidental keyboard Tab, so
              // that distinction is made here instead.
              final bool visuallyFocused = state.focused && dpadModeActive;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                curve: Curves.easeOut,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(radii.small),
                  border: Border.all(
                    color: visuallyFocused
                        ? AppPalette.primary.withValues(alpha: 0.55)
                        : AppPalette.border,
                  ),
                  boxShadow: (visuallyFocused && !uiPerformanceMode)
                      ? [
                          BoxShadow(
                            color: AppPalette.primary.withValues(alpha: 0.18),
                            blurRadius: 24,
                            spreadRadius: 2,
                          ),
                        ]
                      : const [],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(radii.small),
                  clipBehavior: uiPerformanceMode
                      ? Clip.hardEdge
                      : Clip.antiAlias,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      AppNetworkImage(
                        url: anime.coverImage?.extraLarge,
                        cacheWidth: 450,
                        uiPerformanceMode: uiPerformanceMode,
                      ),
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: _PosterGradient(score: anime.averageScore),
                      ),
                      Positioned(
                        top: 8,
                        left: 8,
                        child: _StatusBadge(
                          label: anime.status?.statusLabel ?? 'UNKNOWN',
                          color:
                              anime.status?.statusColor ??
                              AppPalette.statusDefault,
                          uiPerformanceMode: uiPerformanceMode,
                        ),
                      ),
                      _HoverOverlay(
                        visible: visuallyFocused,
                        uiPerformanceMode: uiPerformanceMode,
                      ),
                    ],
                  ),
                ),
              );
            },
            child: const SizedBox.shrink(),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          anime.title.display,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: typography.cardTitleCompact.copyWith(
            color: AppPalette.textMain,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '${anime.nextAiringEpisode != null ? anime.nextAiringEpisode!.episode - 1 : anime.episodes ?? '?'} Episodes',
          style: const TextStyle(color: AppPalette.textMuted, fontSize: 11),
        ),
      ],
    );
  }
}

// Private stateless components.

class _PosterGradient extends StatelessWidget {
  final int? score;
  const _PosterGradient({this.score});

  @override
  Widget build(BuildContext context) {
    if (score == null) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 48, 10, 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppPalette.transparent,
            AppPalette.black.withValues(alpha: 0.70),
            AppPalette.black.withValues(alpha: 0.90),
          ],
          stops: const [0.0, 0.5, 1.0],
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.star_rounded, color: AppPalette.accent, size: 14),
          const SizedBox(width: 3),
          // Left as a plain literal — distinct from metaLabel (w600);
          // this rating badge is deliberately heavier.
          Text(
            (score! / 10).toStringAsFixed(1),
            style: const TextStyle(
              color: AppPalette.accent,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String label;
  final Color color;
  final bool uiPerformanceMode;

  const _StatusBadge({
    required this.label,
    required this.color,
    this.uiPerformanceMode = false,
  });

  @override
  Widget build(BuildContext context) {
    final typography = context.appTypography;
    final radii = context.appRadii;
    final materials = context.appMaterials;

    return FrostedContainer(
      uiPerformanceMode: uiPerformanceMode,
      sigma: materials.subtle,
      borderRadius: BorderRadius.circular(radii.tag),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: AppPalette.black.withValues(
            alpha: uiPerformanceMode ? 0.85 : 0.58,
          ),
          borderRadius: BorderRadius.circular(radii.tag),
          border: Border.all(color: color.withValues(alpha: 0.40)),
        ),
        child: Text(label, style: typography.badgeLabel.copyWith(color: color)),
      ),
    );
  }
}

class _HoverOverlay extends StatelessWidget {
  final bool visible;
  final bool uiPerformanceMode;

  const _HoverOverlay({required this.visible, this.uiPerformanceMode = false});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedOpacity(
        opacity: visible ? 1.0 : 0.0,
        // Zero-duration under Performant mode: the overlay still shows
        // on hover/focus (TV remotes "hover" via D-Pad focus), it just
        // snaps in instead of fading, skipping the saveLayer an
        // interpolated opacity <1.0 would otherwise force every frame.
        duration: perfDuration(
          uiPerformanceMode,
          const Duration(milliseconds: 150),
        ),
        child: ColoredBox(
          color: AppPalette.black.withValues(alpha: 0.42),
          child: Center(
            child: AnimatedSlide(
              offset: visible ? Offset.zero : const Offset(0.0, 0.12),
              duration: perfDuration(
                uiPerformanceMode,
                const Duration(milliseconds: 200),
              ),
              curve: Curves.easeOut,
              child: Container(
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(
                  color: AppPalette.primary,
                  shape: BoxShape.circle,
                  boxShadow: uiPerformanceMode
                      ? null
                      : [
                          BoxShadow(
                            color: AppPalette.primary.withValues(alpha: 0.55),
                            blurRadius: 22,
                            spreadRadius: 2,
                          ),
                        ],
                ),
                child: const Icon(
                  Icons.play_arrow_rounded,
                  color: AppPalette.white,
                  size: 30,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
