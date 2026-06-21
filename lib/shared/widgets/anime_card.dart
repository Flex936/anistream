import 'dart:ui';
import 'package:flutter/material.dart';

import '../utils/anime_status_style.dart';
import '../../features/anime_details/anime_details_screen.dart';
import '../../data/anilist/models/anime.dart';
import '../../core/theme/app_palette.dart';
import 'app_network_image.dart';
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
                boxShadow: hovered
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
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    AppNetworkImage(url: anime.coverImage?.extraLarge),
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
                      ),
                    ),
                    _HoverOverlay(visible: hovered),
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
          '${anime.nextAiringEpisode != null ? anime.nextAiringEpisode!.episode : anime.episodes ?? '?'} Episodes',
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
  const _StatusBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: AppPalette.black.withValues(alpha: 0.58),
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
      ),
    );
  }
}

class _HoverOverlay extends StatelessWidget {
  final bool visible;
  const _HoverOverlay({required this.visible});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedOpacity(
        opacity: visible ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 150),
        child: ColoredBox(
          color: AppPalette.black.withValues(alpha: 0.42),
          child: Center(
            child: AnimatedSlide(
              offset: visible ? Offset.zero : const Offset(0.0, 0.12),
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              child: Container(
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(
                  color: AppPalette.primary,
                  shape: BoxShape.circle,
                  boxShadow: [
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
