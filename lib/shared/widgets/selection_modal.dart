import 'package:dpad/dpad.dart';
import 'package:flutter/material.dart';

import '../../core/extensions/build_context_extensions.dart';
import '../../core/theme/app_palette.dart';
import 'frosted_container.dart';

/// Centered-card modal shell: backdrop, header, subtitle, and a scrollable
/// [body] (DESIGN.md § 1.4).
class SelectionModal extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget body;
  final String regionMemoryKey;
  final bool uiPerformanceMode;
  final VoidCallback? onClose;
  final VoidCallback? onBackdropTap;
  final bool useGlassEffect;
  final double? width;
  final double maxHeight;

  static const double defaultWidth = 640;
  static const double defaultMaxHeight = 600;

  const SelectionModal({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.body,
    required this.regionMemoryKey,
    required this.uiPerformanceMode,
    this.onClose,
    this.onBackdropTap,
    this.useGlassEffect = true,
    this.width,
    this.maxHeight = defaultMaxHeight,
  });

  @override
  Widget build(BuildContext context) {
    final double resolvedWidth =
        width ??
        (context.isMobile
            ? MediaQuery.sizeOf(context).width - 32
            : defaultWidth);

    final double surfaceAlpha = !useGlassEffect
        ? 0.96
        : (uiPerformanceMode ? 0.98 : 0.90);

    final backdrop = Positioned.fill(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onBackdropTap,
        child: useGlassEffect
            ? FrostedContainer(
                uiPerformanceMode: uiPerformanceMode,
                sigma: context.appMaterials.prominent,
                child: Container(
                  color: AppPalette.black.withValues(
                    alpha: uiPerformanceMode ? 0.85 : 0.55,
                  ),
                ),
              )
            : Container(color: AppPalette.black.withValues(alpha: 0.85)),
      ),
    );

    final cardContent = Container(
      width: resolvedWidth,
      constraints: BoxConstraints(maxHeight: maxHeight),
      decoration: BoxDecoration(
        color: AppPalette.surface.withValues(alpha: surfaceAlpha),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppPalette.white.withValues(alpha: 0.1)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ModalHeader(icon: icon, title: title, onClose: onClose),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Text(
              subtitle,
              style: const TextStyle(color: AppPalette.textMuted, fontSize: 13),
            ),
          ),
          const Divider(color: AppPalette.border, height: 1),
          Flexible(child: body),
        ],
      ),
    );

    // The transparent Material gives every Text in the card a real
    // DefaultTextStyle; without an ancestor Material, Text paints with the
    // WidgetsApp default double underline.
    final card = Center(
      child: Material(
        color: Colors.transparent,
        child: useGlassEffect
            ? FrostedContainer(
                uiPerformanceMode: uiPerformanceMode,
                sigma: context.appMaterials.standard,
                borderRadius: BorderRadius.circular(16),
                child: cardContent,
              )
            : cardContent,
      ),
    );

    return Stack(
      children: [
        backdrop,
        DpadRegion(memoryKey: regionMemoryKey, child: card),
      ],
    );
  }
}

class _ModalHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback? onClose;

  const _ModalHeader({required this.icon, required this.title, this.onClose});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 8, 8),
      child: Row(
        children: [
          Icon(icon, color: AppPalette.primary, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                color: AppPalette.textMain,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (onClose != null)
            DpadFocusable(
              onSelect: onClose!,
              builder: (context, state, child) => Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: state.focused
                      ? AppPalette.white.withValues(alpha: 0.1)
                      : AppPalette.transparent,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.close_rounded,
                  color: AppPalette.textMuted,
                  size: 20,
                ),
              ),
              child: const SizedBox.shrink(),
            ),
        ],
      ),
    );
  }
}