import 'package:flutter/material.dart';

import '../../../core/theme/app_palette.dart';
import '../services/theater_data.dart';

/// The "Skip Opening/Ending/Preview" pill that floats above the seekbar
/// while playback is inside a skippable chapter. Player-agnostic —
/// [position] is supplied by whichever screen owns the actual player, so
/// this renders identically for `TheaterScreen` (media_kit) and
/// `MobileTheaterControls` (video_player).
class SkipChip extends StatelessWidget {
  final List<Chapter> chapters;
  final Duration position;
  final ValueChanged<Duration> onSkip;

  const SkipChip({
    super.key,
    required this.chapters,
    required this.position,
    required this.onSkip,
  });

  Chapter? get _activeChapter {
    for (final c in chapters) {
      if (c.isSkippable &&
          position >= c.start &&
          position < (c.end - const Duration(seconds: 1))) {
        return c;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final target = _activeChapter;

    return Align(
      alignment: Alignment.centerRight,
      child: AnimatedOpacity(
        opacity: target != null ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 200),
        child: AnimatedSlide(
          offset: target != null ? Offset.zero : const Offset(0, 0.5),
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutBack,
          child: IgnorePointer(
            ignoring: target == null,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Material(
                color: AppPalette.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(20),
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: target == null ? null : () => onSkip(target.end),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          target?.skipLabel ?? 'Skip',
                          style: const TextStyle(
                            color: AppPalette.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Icon(
                          Icons.skip_next_rounded,
                          color: AppPalette.white,
                          size: 18,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}