import 'package:flutter/material.dart';

import '../../../core/theme/app_palette.dart';

/// Floating pill-shaped action chip used in Theater's control bar for a
/// transient, dismissible playback action — the OP/ED/preview skip chip
/// (`_PlaybackTimeline` in `theater_controls.dart`) and the Next Episode
/// chip both build on this shared visual rather than each hand-rolling
/// their own `Material`+`InkWell`+show/hide animation.
///
/// Purely presentational: [visible] drives the show/hide animation and
/// hit-testing: it fades and slides in as it becomes true, and
/// [IgnorePointer] keeps it untappable — [onTap] is never invoked —
/// while false, matching the mutually-exclusive "only one chip in this
/// slot at a time" convention its callers share. Callers own their own
/// domain logic (what to seek to, what episode to advance to); this
/// widget only knows how to render and animate the chip itself.
class PlaybackActionChip extends StatelessWidget {
  final bool visible;
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const PlaybackActionChip({
    super.key,
    required this.visible,
    required this.label,
    this.icon = Icons.skip_next_rounded,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: visible ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 200),
      child: AnimatedSlide(
        offset: visible ? Offset.zero : const Offset(0, 0.5),
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutBack,
        child: IgnorePointer(
          ignoring: !visible,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Material(
              color: AppPalette.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(20),
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                // Doubled up with the IgnorePointer above rather than
                // relying on it alone — matches the defensive guard the
                // original inline skip-chip already had around its own
                // seek call.
                onTap: visible ? onTap : null,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        label,
                        style: const TextStyle(
                          color: AppPalette.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Icon(icon, color: AppPalette.white, size: 18),
                    ],
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
