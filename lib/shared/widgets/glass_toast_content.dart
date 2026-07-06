import 'package:flutter/material.dart';
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
    return FrostedContainer(
      uiPerformanceMode: uiPerformanceMode,
      sigma: 30,
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
              style: const TextStyle(
                color: AppPalette.textMain,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
