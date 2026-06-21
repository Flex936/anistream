import 'package:flutter/material.dart';

import '../../../data/anilist/models/anime.dart';
import '../../../core/theme/app_palette.dart';
import '../../../shared/widgets/app_network_image.dart';
import '../../../shared/widgets/hover_focus_builder.dart';

class CalendarCard extends StatelessWidget {
  final Anime anime;
  final String Function(int timestamp) formatLocalTime;
  final String Function(int timestamp) getTimeRemaining;
  final bool autofocus;
  final VoidCallback? onTap;

  const CalendarCard({
    super.key,
    required this.anime,
    required this.formatLocalTime,
    required this.getTimeRemaining,
    this.autofocus = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final nextEp = anime.nextAiringEpisode!;
    final epLabel = nextEp.episode > 0
        ? 'Ep ${nextEp.episode}'
        : 'Ep ${anime.episodes ?? "?"}';

    return HoverFocusBuilder(
      autofocus: autofocus,
      onTap: onTap,
      builder: (context, hovered) => Column(
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
                  color: hovered
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
                    AppNetworkImage(
                      url: anime.coverImage?.large,
                      scale: hovered ? 1.05 : 1.0,
                    ),
                    AnimatedOpacity(
                      opacity: hovered ? 1.0 : 0.0,
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
                          formatLocalTime(nextEp.airingAt),
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
              color: hovered ? AppPalette.primary : AppPalette.textMain,
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
            getTimeRemaining(nextEp.airingAt),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AppPalette.textMuted, fontSize: 9),
          ),
        ],
      ),
    );
  }
}
