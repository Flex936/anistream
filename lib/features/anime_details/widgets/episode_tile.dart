import 'package:flutter/material.dart';

import '../../../core/extensions/build_context_extensions.dart';
import '../../../core/theme/app_palette.dart';
import '../../../shared/widgets/hover_focus_builder.dart';

/// A single row in AnimeDetailsScreen's episode list.
class EpisodeTile extends StatelessWidget {
  final int episodeNumber;
  final int? userProgress;
  final bool isUpNext;
  final VoidCallback onToggle;
  final bool isCurrentlyLoading;
  final bool uiPerformanceMode;
  final bool useExoPlayer;

  const EpisodeTile({
    super.key,
    required this.episodeNumber,
    this.userProgress,
    this.isUpNext = false,
    required this.onToggle,
    this.isCurrentlyLoading = false,
    this.uiPerformanceMode = false,
    this.useExoPlayer = false,
  });

  @override
  Widget build(BuildContext context) {
    final isMobile = context.isMobile;
    final hPad = isMobile ? 16.0 : 28.0;

    final isWatched = userProgress != null && episodeNumber <= userProgress!;

    final Color numColor = isUpNext
        ? AppPalette.textMain
        : isWatched
        ? AppPalette.textMuted.withValues(alpha: 0.25)
        : AppPalette.textMuted.withValues(alpha: 0.35);

    final Color titleColor = isUpNext
        ? AppPalette.textMain
        : isWatched
        ? AppPalette.textMuted.withValues(alpha: 0.5)
        : AppPalette.textMuted;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        HoverFocusBuilder(
          autofocus: isUpNext || (userProgress == null && episodeNumber == 1),
          onTap: onToggle,
          builder: (context, hovered) => AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOutCubic,
            padding: EdgeInsets.symmetric(horizontal: hPad, vertical: 15),
            decoration: BoxDecoration(
              color: hovered
                  ? AppPalette.white.withValues(alpha: 0.025)
                  : AppPalette.transparent,
              border: Border(
                left: BorderSide(
                  color: isUpNext
                      ? AppPalette.primary.withValues(alpha: 0.3)
                      : AppPalette.transparent,
                  width: 3,
                ),
              ),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: isMobile ? 26 : 34,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      episodeNumber.toString().padLeft(2, '0'),
                      maxLines: 1,
                      softWrap: false,
                      style: TextStyle(
                        color: numColor,
                        fontSize: isMobile ? 16 : 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Row(
                    children: [
                      Text(
                        'Episode $episodeNumber',
                        style: TextStyle(
                          color: titleColor,
                          fontSize: 14,
                          fontWeight: isUpNext
                              ? FontWeight.w600
                              : FontWeight.w400,
                        ),
                      ),
                      if (isUpNext) ...[
                        const SizedBox(width: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppPalette.primary.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'UP NEXT',
                            style: TextStyle(
                              color: AppPalette.primary,
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ],
                      if (isWatched) ...[
                        const SizedBox(width: 8),
                        Icon(
                          Icons.check_rounded,
                          size: 14,
                          color: AppPalette.textMuted.withValues(alpha: 0.5),
                        ),
                      ],
                    ],
                  ),
                ),
                if (isCurrentlyLoading)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        AppPalette.primary,
                      ),
                    ),
                  )
                else
                  Icon(
                    Icons.play_arrow_rounded,
                    size: 24,
                    color: hovered
                        ? AppPalette.primary
                        : AppPalette.textMuted.withValues(alpha: 0.5),
                  ),
              ],
            ),
          ),
        ),
        const Divider(height: 1, thickness: 1, color: AppPalette.border),
      ],
    );
  }
}
