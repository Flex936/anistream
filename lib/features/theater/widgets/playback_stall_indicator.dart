import 'package:flutter/material.dart';

import '../../../core/extensions/build_context_extensions.dart';
import '../../../core/theme/app_palette.dart';
import '../../../shared/utils/perf_animations.dart';
import '../../../shared/widgets/frosted_container.dart';

/// Theater's mid-playback "buffering" indicator — shown while
/// [PlaybackStallController] (services/playback_stall_controller.dart)
/// detects mpv blocked waiting on data during otherwise-normal playback.
/// Distinct from [TheaterLoadingOverlay] (theater_player.dart), which
/// owns the pre-play loading state before the first frame ever renders,
/// and distinct from a deliberate pause, which
/// [PlaybackStallController] explicitly excludes.
///
/// Deliberately lighter than [TheaterLoadingOverlay]: the video stays
/// visible underneath (just dimmed and blurred) rather than fully
/// hidden behind a near-opaque background, signaling "this will resolve
/// on its own" rather than "nothing to see yet." Wrapped in
/// [IgnorePointer] for the same reason [TheaterTopNotification] is — a
/// transient status indicator is never itself an interactive target,
/// and controls/seek/pause underneath must stay reachable while it's
/// showing.
class PlaybackStallIndicator extends StatelessWidget {
  final bool visible;
  final bool uiPerformanceMode;

  const PlaybackStallIndicator({
    super.key,
    required this.visible,
    this.uiPerformanceMode = false,
  });

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedOpacity(
        opacity: visible ? 1.0 : 0.0,
        duration: perfDuration(
          uiPerformanceMode,
          const Duration(milliseconds: 250),
        ),
        child: FrostedContainer(
          uiPerformanceMode: uiPerformanceMode,
          // AppMaterials' standard tier (16px) — the same content-surface
          // blur TheaterLoadingOverlay's spirit calls for, reused here
          // rather than introducing a new tier for a lighter-weight
          // sibling overlay.
          sigma: context.appMaterials.standard,
          child: Container(
            // Lighter than TheaterLoadingOverlay's 0.85 — the video stays
            // legible underneath rather than being hidden outright.
            // Heavier under performance mode since there's no blur to
            // lean on for legibility there.
            color: AppPalette.black.withValues(
              alpha: uiPerformanceMode ? 0.6 : 0.35,
            ),
            child: const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 40,
                    height: 40,
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        AppPalette.primary,
                      ),
                    ),
                  ),
                  SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
