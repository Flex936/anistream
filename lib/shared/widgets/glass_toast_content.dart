import 'package:flutter/material.dart';
import '../../core/extensions/build_context_extensions.dart';
import '../../core/theme/app_palette.dart';
import 'frosted_container.dart';

/// Shared visual content for both `AppleSnackBar` (bottom) and
/// `AppleTopSnackBar` (top overlay) — previously duplicated almost
/// verbatim between the two.
class GlassToastContent extends StatelessWidget {
  final String message;
  final IconData icon;
  final Color iconColor;
  final bool uiPerformanceMode;

  const GlassToastContent({
    super.key,
    required this.message,
    required this.icon,
    required this.iconColor,
    required this.uiPerformanceMode,
  });

  @override
  Widget build(BuildContext context) {
    final typography = context.appTypography;

    return FrostedContainer(
      uiPerformanceMode: uiPerformanceMode,
      sigma: 30,
      // ── Both radii here are LEFT as plain literals, not routed through
      // AppRadii. This is a fully-rounded capsule/stadium toast — 50
      // exceeds half this container's height specifically to guarantee a
      // full pill curve regardless of exact size, the same "stadium"
      // pattern flagged in watchlist_cards.dart's _PlayOverlay and
      // calendar_card.dart's episode-label pill. None of tag/small/large
      // are a semantic match. ──
      borderRadius: BorderRadius.circular(50),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: AppPalette.surface.withValues(
            alpha: uiPerformanceMode ? 0.98 : 0.75,
          ),
          borderRadius: BorderRadius.circular(50),
          border: Border.all(color: AppPalette.white.withValues(alpha: 0.15)),
          boxShadow: uiPerformanceMode
              ? null
              : [
                  BoxShadow(
                    color: AppPalette.black.withValues(alpha: 0.25),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: iconColor, size: 20),
            const SizedBox(width: 10),
            Text(
              message,
              style: typography.toastMessage.copyWith(
                color: AppPalette.textMain,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
