import 'package:dpad/dpad.dart';
import 'package:flutter/material.dart';

import '../../../core/extensions/build_context_extensions.dart';
import '../../../core/input/input_mode_scope.dart';
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
    // The ring is driven directly by DpadFocusable's state.focused. No
    // nested InkWell: DpadFocusable already provides tap + Select-key
    // activation via onSelect, so an inner InkWell with its own onTap
    // would double-handle the same press.
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
              color: (state.focused && context.dpadModeActive)
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

  /// Gated by `AppSettings.showFreezeRecoveryButton` — the restart
  /// button next to [onBack] is only rendered when this is true, so
  /// unaffected users never see it. See that setting's doc comment and
  /// ARCHITECTURE.md § 7 for what it recovers from.
  final bool showFreezeRecoveryButton;

  /// Always provided regardless of [showFreezeRecoveryButton], matching
  /// [onBack]'s always-required shape — only whether the button renders
  /// is conditional, not whether the callback exists.
  final VoidCallback onRestart;

  const TheaterTopBar({
    super.key,
    required this.episode,
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
          'Episode $episode',
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

/// Theater's own in-flow status toast — the AniList "Progress saved"
/// confirmation and the auto-skip "Skipping Opening in 2s..." countdown
/// both render through this widget, fed by a shared
/// `TopNotificationController` (services/top_notification_controller.dart)
/// on both `TheaterScreen` (media_kit) and `ExoTheaterScreen`
/// (video_player). It's a plain sibling of [TheaterTopBar] inside each
/// screen's own `Stack`, positioned [kTopBarClearance] below the top bar
/// rather than over it, and wrapped in [IgnorePointer] since a transient
/// status message is never itself an interactive target — between the
/// two, the back button in [TheaterTopBar] stays reachable regardless of
/// whether a notification is currently showing.
///
/// [message] is null when nothing is currently showing; [icon]/
/// [iconColor] are only meaningful while it's non-null and fall back to a
/// neutral value otherwise, since they're invisible at that point anyway
/// (the same fallback approach `theater_controls.dart`'s skip-chip takes
/// for its own label text).
class TheaterTopNotification extends StatelessWidget {
  final String? message;
  final IconData? icon;
  final Color? iconColor;
  final bool uiPerformanceMode;

  /// Vertical clearance this notification reserves below a screen's own
  /// top-bar offset (`24 + MediaQuery.paddingOf(context).top`) — enough
  /// to sit below [TheaterTopBar] rather than over it, regardless of
  /// whether the controls overlay is currently shown or hidden. Shared by
  /// both consumers so neither hardcodes its own copy of this offset.
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

/// Loading overlay shown while the torrent is buffering. No
/// interactive/focusable elements live here, so D-Pad mode doesn't
/// affect it.
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
