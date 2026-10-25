import 'package:flutter/material.dart';

import '../../../core/extensions/build_context_extensions.dart';
import '../../../core/theme/app_palette.dart';
import '../../../shared/utils/perf_animations.dart';
import '../../../shared/widgets/frosted_container.dart';

/// Mid-playback buffering overlay shown while [PlaybackStallController]
/// reports a stall; the pre-first-frame state is [TheaterLoadingOverlay].
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
          sigma: context.appMaterials.standard,
          child: Container(
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
