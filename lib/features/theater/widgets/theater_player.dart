import 'package:flutter/material.dart';
import 'package:dpad/dpad.dart';
import '../../../core/theme/app_palette.dart';
import '../../../shared/widgets/frosted_container.dart';
import '../services/streaming_controller_base.dart';

class FrostedIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final bool uiPerformanceMode;
  final String? tooltip;

  const FrostedIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.uiPerformanceMode = false,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    // ── DpadFocusable replaces the old StatefulWidget's manual
    // InkWell.onFocusChange + local _focused bool — the ring is now
    // driven directly by state.focused, which dpad manages itself. No
    // nested InkWell: DpadFocusable already provides tap + Select-key
    // activation via onSelect, so an inner InkWell with its own onTap
    // would just double-handle the same press. ──
    final wrapped = FrostedContainer(
      uiPerformanceMode: uiPerformanceMode,
      sigma: 10,
      borderRadius: BorderRadius.circular(24),
      child: DpadFocusable(
        onSelect: onPressed,
        builder: (context, state, child) => Container(
          width: 48,
          height: 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppPalette.black.withValues(
              alpha: uiPerformanceMode ? 0.8 : 0.4,
            ),
            shape: BoxShape.circle,
            border: Border.all(
              color: state.focused
                  ? AppPalette.primary
                  : AppPalette.transparent,
              width: 2,
            ),
          ),
          child: Icon(icon, color: AppPalette.white, size: 24),
        ),
        child: const SizedBox.shrink(),
      ),
    );

    return tooltip == null
        ? wrapped
        : Tooltip(message: tooltip!, child: wrapped);
  }
}

class TheaterTopBar extends StatelessWidget {
  final int episode;
  final VoidCallback onBack;
  final bool uiPerformanceMode;

  const TheaterTopBar({
    super.key,
    required this.episode,
    required this.onBack,
    this.uiPerformanceMode = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        FrostedIconButton(
          icon: Icons.arrow_back_rounded,
          onPressed: onBack,
          uiPerformanceMode: uiPerformanceMode,
          tooltip: 'Back',
        ),
        const SizedBox(width: 16),
        Text(
          'Episode $episode',
          style: const TextStyle(
            color: AppPalette.white,
            fontSize: 20,
            fontWeight: FontWeight.w700,
            shadows: [Shadow(blurRadius: 8)],
          ),
        ),
      ],
    );
  }
}

/// Loading overlay shown while the torrent is buffering. Unchanged — no
/// interactive/focusable elements live here, so there's nothing for D-Pad
/// mode to affect.
class TheaterLoadingOverlay extends StatelessWidget {
  final int episode;
  final BaseStreamingController controller;

  const TheaterLoadingOverlay({
    super.key,
    required this.episode,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppPalette.black.withValues(alpha: 0.85),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 48,
              height: 48,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                valueColor: AlwaysStoppedAnimation<Color>(AppPalette.primary),
              ),
            ),
            const SizedBox(height: 32),
            Text(
              'Episode $episode',
              style: const TextStyle(
                color: AppPalette.white,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 32),
            Text(
              controller.statusText,
              style: TextStyle(
                color: controller.hasError
                    ? AppPalette.statusCancelled
                    : AppPalette.primary,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
