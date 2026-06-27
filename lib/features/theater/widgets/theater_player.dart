import 'dart:ui';
import 'package:flutter/material.dart';
import '../../../core/theme/app_palette.dart';
import '../services/streaming_controller.dart';

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
    // ── The core button UI ──
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

    // ── Apply blur only if performance mode is OFF ──
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

class TheaterLoadingOverlay extends StatefulWidget {
  final int episode;
  final StreamingController controller;
  final VoidCallback? onBack;

  const TheaterLoadingOverlay({
    super.key,
    required this.episode,
    required this.controller,
    this.onBack,
  });

  @override
  State<TheaterLoadingOverlay> createState() => _TheaterLoadingOverlayState();
}

class _TheaterLoadingOverlayState extends State<TheaterLoadingOverlay> {
  bool _showBack = false;

  @override
  void initState() {
    super.initState();
    // Show the back button after 8 s so it's not immediately distracting but
    // is visible quickly enough that the user doesn't feel trapped.
    Future.delayed(const Duration(seconds: 8), () {
      if (mounted) setState(() => _showBack = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      // The loading overlay was already solid, so no blur to remove here!
      color: AppPalette.black.withValues(alpha: 0.85),
      child: Stack(
        children: [
          // ── Centered spinner + status ──
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 48,
                  height: 48,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      AppPalette.primary,
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                Text(
                  'Episode ${widget.episode}',
                  style: const TextStyle(
                    color: AppPalette.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 32),
                ListenableBuilder(
                  listenable: widget.controller,
                  builder:
                      (context, _) => Text(
                        widget.controller.statusText,
                        style: TextStyle(
                          color:
                              widget.controller.hasError
                                  ? AppPalette.statusCancelled
                                  : AppPalette.primary,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                        textAlign: TextAlign.center,
                      ),
                ),
              ],
            ),
          ),

          // ── Delayed back button ──
          if (widget.onBack != null)
            Positioned(
              top: 40,
              left: 24,
              child: AnimatedOpacity(
                opacity: _showBack ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 400),
                child: IgnorePointer(
                  ignoring: !_showBack,
                  child: FrostedIconButton(
                    icon: Icons.arrow_back_rounded,
                    onPressed: widget.onBack!,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
