import 'dart:ui';
import 'package:flutter/material.dart';

import '../screens/anime_details_screen.dart';
import '../services/anilist_api.dart';
import '../theme/app_palette.dart';

class AnimeCard extends StatefulWidget {
  final Anime anime;
  // ── NEW: when provided by a parent screen, called instead of Navigator.push
  //        so the card stays inside the AppShell and the NavBar stays visible.
  final ValueChanged<Anime>? onSelect;

  const AnimeCard({super.key, required this.anime, this.onSelect});

  @override
  State<AnimeCard> createState() => _AnimeCardState();
}

class _AnimeCardState extends State<AnimeCard> {
  bool _hovered = false;

  Color _statusColor(String? status) => switch (status) {
    'RELEASING' => AppPalette.statusReleasing,
    'FINISHED' => AppPalette.statusFinished,
    'CANCELLED' => AppPalette.statusCancelled,
    'HIATUS' => AppPalette.statusHiatus,
    _ => AppPalette.statusDefault,
  };

  String _formatStatus(String? status) =>
      (status ?? 'UNKNOWN').replaceAll('_', ' ');

  @override
  Widget build(BuildContext context) {
    final anime = widget.anime;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Poster ──────────────────────────────────────────────────────────
        Expanded(
          child: MouseRegion(
            onEnter: (_) => setState(() => _hovered = true),
            onExit: (_) => setState(() => _hovered = false),
            child: GestureDetector(
              onTap: () {
                // ── CHANGED: prefer the shell callback; fall back to
                //    Navigator.push only when used outside an AppShell context.
                if (widget.onSelect != null) {
                  widget.onSelect!(anime);
                } else {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => AnimeDetailsScreen(anime: anime),
                    ),
                  );
                }
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _hovered
                        ? AppPalette.primary.withValues(alpha: 0.55)
                        : AppPalette.border,
                  ),
                  boxShadow: _hovered
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
                      _CoverImage(
                        url: anime.coverImage?.extraLarge,
                        hovered: _hovered,
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
                          label: _formatStatus(anime.status),
                          color: _statusColor(anime.status),
                        ),
                      ),
                      _HoverOverlay(visible: _hovered),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),

        // ── Title + episode count ────────────────────────────────────────────
        const SizedBox(height: 10),
        AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 200),
          style: TextStyle(
            color: _hovered ? AppPalette.primary : AppPalette.textMain,
            fontSize: 13,
            fontWeight: FontWeight.w500,
            height: 1.35,
          ),
          child: Text(
            anime.title.display,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '${anime.episodes ?? '?'} Episodes',
          style: const TextStyle(color: AppPalette.textMuted, fontSize: 11),
        ),
      ],
    );
  }
}

// ── Private sub-widgets (unchanged) ─────────────────────────────────────────

class _CoverImage extends StatelessWidget {
  final String? url;
  final bool hovered;
  const _CoverImage({this.url, required this.hovered});

  @override
  Widget build(BuildContext context) {
    if (url == null || url!.isEmpty) {
      return const ColoredBox(
        color: AppPalette.surface,
        child: Center(
          child: Icon(
            Icons.image_not_supported_outlined,
            color: AppPalette.textMuted,
            size: 36,
          ),
        ),
      );
    }
    return AnimatedScale(
      scale: hovered ? 1.05 : 1.0,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOut,
      child: Image.network(
        url!,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
          if (wasSynchronouslyLoaded) return child;
          return Stack(
            fit: StackFit.expand,
            children: [
              const ColoredBox(color: AppPalette.surface),
              AnimatedOpacity(
                opacity: frame != null ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 500),
                curve: Curves.easeOut,
                child: child,
              ),
            ],
          );
        },
        errorBuilder: (_, _, _) => const ColoredBox(
          color: AppPalette.surface,
          child: Center(
            child: Icon(
              Icons.broken_image_outlined,
              color: AppPalette.textMuted,
              size: 36,
            ),
          ),
        ),
      ),
    );
  }
}

class _PosterGradient extends StatelessWidget {
  final int? score;
  const _PosterGradient({this.score});

  @override
  Widget build(BuildContext context) {
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
      child: score != null
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.star_rounded,
                  color: AppPalette.accent,
                  size: 14,
                ),
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
            )
          : const SizedBox.shrink(),
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
        duration: const Duration(milliseconds: 200),
        child: ColoredBox(
          color: AppPalette.black.withValues(alpha: 0.42),
          child: Center(
            child: AnimatedSlide(
              offset: visible ? Offset.zero : const Offset(0.0, 0.12),
              duration: const Duration(milliseconds: 250),
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
