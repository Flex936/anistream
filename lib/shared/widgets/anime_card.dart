import 'package:flutter/material.dart';

import '../../core/settings/settings_scope.dart';
import '../../core/theme/app_palette.dart';
import '../../data/anilist/models/anime.dart';
import '../../features/anime_details/anime_details_screen.dart';
import '../utils/anime_status_style.dart';
import '../utils/perf_animations.dart';
import 'app_network_image.dart';
import 'frosted_container.dart';
import 'hover_focus_builder.dart';

class AnimeCard extends StatelessWidget {
  final Anime anime;
  final ValueChanged<Anime>? onSelect;
  final bool autofocus;

  const AnimeCard({
    super.key,
    required this.anime,
    this.onSelect,
    this.autofocus = false,
  });

  @override
  Widget build(BuildContext context) {
    final uiPerformanceMode = SettingsScope.of(context).uiPerformanceMode;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: HoverFocusBuilder(
            autofocus: autofocus,
            onTap: () {
              if (onSelect != null) {
                onSelect!(anime);
              } else {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => AnimeDetailsScreen(anime: anime),
                  ),
                );
              }
            },
            builder: (context, hovered) => AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              curve: Curves.easeOut,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: hovered
                      ? AppPalette.primary.withValues(alpha: 0.55)
                      : AppPalette.border,
                ),
                boxShadow: (hovered && !uiPerformanceMode)
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
                borderRadius: BorderRadius.circular(11),
                // ── Clip.hardEdge under Performant mode instead of the
                // ClipRRect default (Clip.antiAlias) — a sampled,
                // anti-aliased clip on every single poster in every
                // carousel/grid is exactly the "complex clipping path"
                // cost Performant mode exists to strip. ──
                clipBehavior: uiPerformanceMode
                    ? Clip.hardEdge
                    : Clip.antiAlias,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // ── cacheWidth added: this card renders at ~170dp in
                    // every carousel and at similar widths in search/grid
                    // layouts, but was decoding `extraLarge` (the largest
                    // AniList cover variant) at full resolution every time.
                    // Given this is the single most-instantiated poster
                    // widget in the app, that was real, repeated,
                    // avoidable decode + RAM cost. 450 covers up to ~2.6x
                    // device pixel ratio at the widest display width this
                    // card is actually used at. ──
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
                      visible: hovered,
                      uiPerformanceMode: uiPerformanceMode,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        HoverFocusBuilder(
          builder: (context, _) => Text(
            anime.title.display,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppPalette.textMain,
              fontSize: 13,
              fontWeight: FontWeight.w500,
              height: 1.35,
            ),
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

// ── Private Stateless Components ─────────────────────────────────────────────

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
    return FrostedContainer(
      uiPerformanceMode: uiPerformanceMode,
      sigma: 6,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: AppPalette.black.withValues(
            alpha: uiPerformanceMode ? 0.85 : 0.58,
          ),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withValues(alpha: 0.40)),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 9,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
          ),
        ),
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
        // ── Zero-duration under Performant mode: the overlay still shows
        // on hover/focus (TV remotes "hover" via D-Pad focus), it just
        // snaps in instead of fading, which skips the saveLayer an
        // interpolated opacity <1.0 would otherwise force every frame of
        // the transition. ──
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
