import 'package:flutter/material.dart';
import '../../../core/theme/app_palette.dart';
import '../../../shared/widgets/frosted_container.dart';
import '../services/streaming_controller_base.dart';

class FrostedIconButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final bool uiPerformanceMode;
  final bool dpadModeActive;
  final String? tooltip;

  const FrostedIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.uiPerformanceMode = false,
    this.dpadModeActive = false,
    this.tooltip,
  });

  @override
  State<FrostedIconButton> createState() => _FrostedIconButtonState();
}

class _FrostedIconButtonState extends State<FrostedIconButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final showRing = _focused && widget.dpadModeActive;

    final buttonContent = Material(
      color: AppPalette.black.withValues(
        alpha: widget.uiPerformanceMode ? 0.8 : 0.4,
      ),
      child: InkWell(
        onTap: widget.onPressed,
        onFocusChange: (f) => setState(() => _focused = f),
        focusColor: AppPalette.white.withValues(alpha: 0.15),
        hoverColor: AppPalette.white.withValues(alpha: 0.2),
        child: Container(
          width: 48,
          height: 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: showRing ? AppPalette.primary : AppPalette.transparent,
              width: 2,
            ),
          ),
          child: Icon(widget.icon, color: AppPalette.white, size: 24),
        ),
      ),
    );

    final wrapped = FrostedContainer(
      uiPerformanceMode: widget.uiPerformanceMode,
      sigma: 10,
      borderRadius: BorderRadius.circular(24),
      child: buttonContent,
    );

    return widget.tooltip == null
        ? wrapped
        : Tooltip(message: widget.tooltip!, child: wrapped);
  }
}

class TheaterTopBar extends StatelessWidget {
  final int episode;
  final VoidCallback onBack;
  final bool uiPerformanceMode;
  final bool dpadModeActive;

  const TheaterTopBar({
    super.key,
    required this.episode,
    required this.onBack,
    this.uiPerformanceMode = false,
    this.dpadModeActive = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        FrostedIconButton(
          icon: Icons.arrow_back_rounded,
          onPressed: onBack,
          uiPerformanceMode: uiPerformanceMode,
          dpadModeActive: dpadModeActive,
          tooltip: 'Back',
        ),
        const SizedBox(width: 16),
        Text(
          'Episode $episode',
          style: const TextStyle(
            color: AppPalette.white,
            fontSize: 20,
            fontWeight: FontWeight.w700,
            shadows: [Shadow(color: AppPalette.black, blurRadius: 8)],
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
