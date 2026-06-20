import 'package:flutter/material.dart';

import '../../../data/anilist/models/anime.dart';
import '../../../core/theme/app_palette.dart';

class CalendarCard extends StatefulWidget {
  final Anime anime;
  final String Function(int timestamp) formatLocalTime;
  final String Function(int timestamp) getTimeRemaining;
  final bool autofocus;

  const CalendarCard({
    super.key,
    required this.anime,
    required this.formatLocalTime,
    required this.getTimeRemaining,
    this.autofocus = false,
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

    return FocusableActionDetector(
      autofocus: widget.autofocus,
      onShowHoverHighlight: (v) => setState(() => _hovered = v),
      onShowFocusHighlight: (v) => setState(() => _hovered = v),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
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
                    _CoverImage(
                      url: anime.coverImage?.large,
                      hovered: _hovered,
                    ),

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
