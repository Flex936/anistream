import 'package:flutter/material.dart';
import '../../services/anilist_query_service.dart';
import '../../theme/app_palette.dart';

/// Compact 2 : 3 portrait card used inside each day column of the schedule.
///
/// • Always-visible airing-time badge (top-right, green tinted)
/// • Hover: cover scales up, gradient overlay fades in with episode pill
/// • Title (single line, turns primary on hover)
/// • Live countdown supplied by [getTimeRemaining]
class CalendarCard extends StatefulWidget {
  final Anime anime;
  final String Function(int timestamp) formatLocalTime;
  final String Function(int timestamp) getTimeRemaining;

  const CalendarCard({
    super.key,
    required this.anime,
    required this.formatLocalTime,
    required this.getTimeRemaining,
  });

  @override
  State<CalendarCard> createState() => _CalendarCardState();
}

class _CalendarCardState extends State<CalendarCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final anime = widget.anime;
    final nextEp = anime.nextAiringEpisode!;
    final epLabel = nextEp.episode > 0
        ? 'Ep ${nextEp.episode}'
        : 'Ep ${anime.episodes ?? "?"}';

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Cover + badges ───────────────────────────────────────────────
          AspectRatio(
            aspectRatio: 2 / 3,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: _hovered
                      ? AppPalette.primary.withValues(alpha: 0.50)
                      : AppPalette.border,
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x4D000000),
                    blurRadius: 8,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(9),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // Cover image
                    _CoverImage(
                      url: anime.coverImage?.large,
                      hovered: _hovered,
                    ),

                    // Hover overlay: gradient + episode pill
                    AnimatedOpacity(
                      opacity: _hovered ? 1.0 : 0.0,
                      duration: const Duration(milliseconds: 250),
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
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: AppPalette.primary.withValues(
                                  alpha: 0.55,
                                ),
                                blurRadius: 8,
                              ),
                            ],
                          ),
                          child: Text(
                            epLabel,
                            style: const TextStyle(
                              color: AppPalette.white,
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ),

                    // Airing-time badge — always visible, top-right
                    Positioned(
                      top: 6,
                      right: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppPalette.black.withValues(alpha: 0.72),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: AppPalette.statusReleasing.withValues(
                              alpha: 0.30,
                            ),
                          ),
                        ),
                        child: Text(
                          widget.formatLocalTime(nextEp.airingAt),
                          style: const TextStyle(
                            color: AppPalette.statusReleasing,
                            fontSize: 8,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          const SizedBox(height: 6),

          // ── Title ────────────────────────────────────────────────────────
          AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 150),
            style: TextStyle(
              color: _hovered ? AppPalette.primary : AppPalette.textMain,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              height: 1.3,
            ),
            child: Text(
              anime.title.romaji ?? anime.title.english ?? 'Unknown',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),

          const SizedBox(height: 2),

          // ── Countdown ────────────────────────────────────────────────────
          Text(
            widget.getTimeRemaining(nextEp.airingAt),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AppPalette.textMuted, fontSize: 9),
          ),
        ],
      ),
    );
  }
}

// ── _CoverImage ───────────────────────────────────────────────────────────────

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
            size: 22,
          ),
        ),
      );
    }

    return AnimatedScale(
      scale: hovered ? 1.05 : 1.0,
      duration: const Duration(milliseconds: 300),
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
                duration: const Duration(milliseconds: 400),
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
              size: 22,
            ),
          ),
        ),
      ),
    );
  }
}
