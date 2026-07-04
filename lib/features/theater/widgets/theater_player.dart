import 'dart:ui';
import 'package:flutter/material.dart';
import '../../../core/theme/app_palette.dart';
import '../services/streaming_controller_base.dart';

class FrostedIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final bool uiPerformanceMode;

  const FrostedIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.uiPerformanceMode = false,
  });

  @override
  Widget build(BuildContext context) {
    Widget buttonContent = Material(
      color: AppPalette.black.withValues(alpha: uiPerformanceMode ? 0.8 : 0.4),
      child: InkWell(
        onTap: onPressed,
        hoverColor: AppPalette.white.withValues(alpha: 0.2),
        child: Container(
          width: 48,
          height: 48,
          alignment: Alignment.center,
          child: Icon(icon, color: AppPalette.white, size: 24),
        ),
      ),
    );

    if (!uiPerformanceMode) {
      buttonContent = BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: buttonContent,
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: buttonContent,
    );
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

/// Loading overlay shown while the torrent is buffering.
///
/// Accepts [BaseStreamingController] so it works with both the local
/// libtorrent engine and the remote Go server — the status text and error
/// flag are part of the shared interface.
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
