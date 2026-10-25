import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/extensions/build_context_extensions.dart';
import '../../../core/theme/app_palette.dart';
import '../../../shared/widgets/frosted_container.dart';
import '../../../shared/widgets/hover_focus_builder.dart';

/// Back button, last in HeroHeaderDelegate's Stack so it keeps paint and
/// hit-test priority over the fading siblings.
class HeroHeaderBackButton extends StatelessWidget {
  final VoidCallback? onBack;
  final bool uiPerformanceMode;

  const HeroHeaderBackButton({
    super.key,
    this.onBack,
    this.uiPerformanceMode = false,
  });

  void _handleTap(BuildContext context) {
    if (onBack != null) {
      onBack!();
    } else {
      unawaited(Navigator.maybePop(context));
    }
  }

  @override
  Widget build(BuildContext context) {
    return HoverFocusBuilder(
      onTap: () => _handleTap(context),
      builder: (context, hovered) {
        final content = AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOutCubic,
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: hovered
                ? AppPalette.white.withValues(alpha: 0.15)
                : AppPalette.black.withValues(
                    alpha: uiPerformanceMode ? 0.8 : 0.4,
                  ),
            shape: BoxShape.circle,
            border: Border.all(color: AppPalette.white.withValues(alpha: 0.1)),
          ),
          child: const Icon(
            Icons.arrow_back_rounded,
            size: 18,
            color: AppPalette.textMain,
          ),
        );

        return FrostedContainer(
          uiPerformanceMode: uiPerformanceMode,
          sigma: context.appMaterials.subtle,
          borderRadius: BorderRadius.circular(20),
          child: content,
        );
      },
    );
  }
}

/// A dot that grows into a dot+label pill as [labelOpacity] rises to 1.
class HeroStatusIndicator extends StatelessWidget {
  final Color color;
  final String label;
  final double labelOpacity;

  const HeroStatusIndicator({
    super.key,
    required this.color,
    required this.label,
    required this.labelOpacity,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: 10 * labelOpacity,
        vertical: 4 * labelOpacity,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12 * labelOpacity),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.25 * labelOpacity)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          if (labelOpacity > 0) ...[
            const SizedBox(width: 8),
            Opacity(
              opacity: labelOpacity,
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: color,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
