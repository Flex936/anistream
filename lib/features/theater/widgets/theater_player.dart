import 'package:dpad/dpad.dart';
import 'package:flutter/material.dart';

import '../../../core/extensions/build_context_extensions.dart';
import '../../../core/theme/app_palette.dart';
import '../../../shared/utils/perf_animations.dart';
import '../../../shared/widgets/frosted_container.dart';
import '../../../shared/widgets/glass_toast_content.dart';
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
    // DpadFocusable handles tap and Select, so no inner InkWell.
    final wrapped = FrostedContainer(
      uiPerformanceMode: uiPerformanceMode,
      sigma: context.appMaterials.subtle,
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
  /// "Episode N" or a custom label; see `TheaterScreen.displayTitle`.
  final String title;
  final VoidCallback onBack;
  final bool uiPerformanceMode;

  /// Shows the restart button; ARCHITECTURE.md § 7 describes the freeze it
  /// recovers from.
  final bool showFreezeRecoveryButton;
  final VoidCallback onRestart;

  const TheaterTopBar({
    super.key,
    required this.title,
    required this.onBack,
    required this.onRestart,
    this.uiPerformanceMode = false,
    this.showFreezeRecoveryButton = false,
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
          title,
          style: const TextStyle(
            color: AppPalette.white,
            fontSize: 20,
            fontWeight: FontWeight.w700,
            shadows: [Shadow(blurRadius: 8)],
          ),
        ),
        if (showFreezeRecoveryButton) ...[
          const SizedBox(width: 16),
          FrostedIconButton(
            icon: Icons.refresh_rounded,
            onPressed: onRestart,
            uiPerformanceMode: uiPerformanceMode,
            tooltip: 'Restart Player',
          ),
        ],
      ],
    );
  }
}

/// In-flow status toast (AniList "Progress saved", auto-skip countdown) fed
/// by `TopNotificationController`. A null [message] hides it; [icon] and
/// [iconColor] fall back to neutral values then.
class TheaterTopNotification extends StatelessWidget {
  final String? message;
  final IconData? icon;
  final Color? iconColor;
  final bool uiPerformanceMode;

  /// Clearance below a screen's top-bar offset
  /// (`24 + MediaQuery.paddingOf(context).top`), so the toast clears
  /// [TheaterTopBar].
  static const double kTopBarClearance = 64.0;

  const TheaterTopNotification({
    super.key,
    required this.message,
    required this.icon,
    required this.iconColor,
    this.uiPerformanceMode = false,
  });

  @override
  Widget build(BuildContext context) {
    final visible = message != null;

    return IgnorePointer(
      child: Align(
        alignment: Alignment.topCenter,
        child: AnimatedSlide(
          offset: visible ? Offset.zero : const Offset(0, -1.5),
          duration: perfDuration(
            uiPerformanceMode,
            const Duration(milliseconds: 400),
          ),
          curve: Curves.easeOutCubic,
          child: AnimatedOpacity(
            opacity: visible ? 1.0 : 0.0,
            duration: perfDuration(
              uiPerformanceMode,
              const Duration(milliseconds: 300),
            ),
            child: GlassToastContent(
              message: message ?? '',
              icon: icon ?? Icons.info_outline_rounded,
              iconColor: iconColor ?? AppPalette.primary,
              uiPerformanceMode: uiPerformanceMode,
            ),
          ),
        ),
      ),
    );
  }
}

/// Loading overlay shown while the torrent buffers; nothing in it is focusable.
class TheaterLoadingOverlay extends StatelessWidget {
  /// "Episode N" or a custom label; see `TheaterScreen.displayTitle`.
  final String title;
  final BaseStreamingController controller;

  const TheaterLoadingOverlay({
    super.key,
    required this.title,
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
              title,
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
