import 'package:flutter/material.dart';
import '../../core/extensions/build_context_extensions.dart';
import '../../core/theme/app_palette.dart';
import 'frosted_container.dart';

/// Glass toast visuals shared by the bottom snackbar and Theater's top
/// notification.
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
    final materials = context.appMaterials;

    return FrostedContainer(
      uiPerformanceMode: uiPerformanceMode,
      sigma: materials.prominent,
      // 50 exceeds half the height, so the capsule stays fully rounded at any
      // size.
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